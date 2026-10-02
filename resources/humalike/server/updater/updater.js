'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

const PRODUCT = 'humalike-fivem';
const BUNDLE_SCHEMA = 1;
const DEFAULT_SOURCE = 'https://api.github.com/repos/Humalike/humalike-fivem-npc';
const BUNDLE_ASSET = 'humalike.update.json';
const SIGNATURE_ASSET = 'humalike.update.json.sig';
const STATE_DIR = '.humalike-update';
const MAX_JSON_BYTES = 2 * 1024 * 1024;
const MAX_BUNDLE_BYTES = 64 * 1024 * 1024;
const REQUEST_TIMEOUT_MS = 30000;
const MAX_REDIRECTS = 5;
const COMPANION = 'humalike-updater';
const RESTART_COMMANDS = ['refresh', 'ensure', 'stop', 'start'];

// Rotate: add the new key, ship a release signed with the old one, then drop it.
const TRUSTED_KEYS = [
    '-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA1JcqNqtX3ETrweHYLtrD5qH9X1328JUhAD2FCnlE7Rg=\n-----END PUBLIC KEY-----\n',
];

const SEMVER = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/;
const SAFE_SEGMENT = /^[A-Za-z0-9_@+-][A-Za-z0-9._@+-]*$/;

class UpdateError extends Error {}

function parseVersion(text) {
    const match = SEMVER.exec(String(text || '').trim());
    if (!match) return null;
    return {
        text: match[0],
        core: [Number(match[1]), Number(match[2]), Number(match[3])],
        pre: match[4] ? match[4].split('.') : [],
    };
}

function compareVersions(left, right) {
    const a = typeof left === 'string' ? parseVersion(left) : left;
    const b = typeof right === 'string' ? parseVersion(right) : right;
    if (!a || !b) throw new UpdateError(`cannot compare versions ${left} and ${right}`);
    for (let i = 0; i < 3; i += 1) {
        if (a.core[i] !== b.core[i]) return a.core[i] < b.core[i] ? -1 : 1;
    }
    if (!a.pre.length || !b.pre.length) {
        if (a.pre.length === b.pre.length) return 0;
        return a.pre.length ? -1 : 1;
    }
    for (let i = 0; i < Math.max(a.pre.length, b.pre.length); i += 1) {
        const x = a.pre[i];
        const y = b.pre[i];
        if (x === undefined) return -1;
        if (y === undefined) return 1;
        const xNumeric = /^\d+$/.test(x);
        const yNumeric = /^\d+$/.test(y);
        if (xNumeric && yNumeric) {
            if (Number(x) !== Number(y)) return Number(x) < Number(y) ? -1 : 1;
        } else if (xNumeric !== yNumeric) {
            return xNumeric ? -1 : 1;
        } else if (x !== y) {
            return x < y ? -1 : 1;
        }
    }
    return 0;
}

function parseMode(raw) {
    const value = String(raw || '').trim().toLowerCase();
    if (value === '' || value === 'auto' || value === 'on' || value === 'true' || value === '1') return 'auto';
    if (value === 'off' || value === 'false' || value === '0' || value === 'none') return 'off';
    return 'notify';
}

function releaseInfo(release) {
    if (!release || typeof release !== 'object' || release.draft) return null;
    const version = parseVersion(String(release.tag_name || '').replace(/^v/, ''));
    if (!version) return null;
    const assets = Array.isArray(release.assets) ? release.assets : [];
    const find = (name) => assets.find((asset) => asset && asset.name === name) || null;
    return {
        version: version.text,
        withdrawn: release.prerelease === true,
        bundle: find(BUNDLE_ASSET),
        signature: find(SIGNATURE_ASSET),
    };
}

// A release re-marked as pre-release is withdrawn: its servers move back to latest.
function decide({ current, pin, latest, pinned, running }) {
    if (!parseVersion(current)) return { action: 'none', reason: `running version ${current} is not a release version` };
    if (pin) {
        if (!parseVersion(pin)) return { action: 'error', reason: `humalike_version "${pin}" is not a version` };
        if (compareVersions(pin, current) === 0) return { action: 'none', reason: `pinned to ${pin}` };
        if (!pinned) return { action: 'error', reason: `pinned version ${pin} has no release` };
        return { action: 'install', target: pinned, reason: `pinned to ${pin}` };
    }
    if (!latest) return { action: 'none', reason: 'no published release' };
    const order = compareVersions(latest.version, current);
    if (order > 0) return { action: 'install', target: latest, reason: `${latest.version} is available` };
    if (order === 0) return { action: 'none', reason: 'up to date' };
    if (running && running.withdrawn) {
        return { action: 'install', target: latest, reason: `${current} was withdrawn, rolling back to ${latest.version}` };
    }
    return { action: 'none', reason: `running ${current}, newer than the latest release ${latest.version}` };
}

function safeRelativePath(relative) {
    if (typeof relative !== 'string' || relative === '' || relative.length > 400) return false;
    if (relative.includes('\\') || relative.includes('\0') || relative.startsWith('/')) return false;
    const segments = relative.split('/');
    if (segments[0] === STATE_DIR) return false;
    return segments.every((segment) => segment !== '.' && segment !== '..' && SAFE_SEGMENT.test(segment));
}

function sha256(buffer) {
    return crypto.createHash('sha256').update(buffer).digest('hex');
}

function verifySignature(bundleBytes, signatureText, keys = TRUSTED_KEYS) {
    const signature = Buffer.from(String(signatureText || '').trim(), 'base64');
    if (signature.length !== 64) return false;
    return keys.some((key) => {
        try {
            return crypto.verify(null, bundleBytes, crypto.createPublicKey(key), signature);
        } catch (error) {
            return false;
        }
    });
}

function openBundle(bundleBytes, signatureText, expectedVersion, keys = TRUSTED_KEYS) {
    if (!verifySignature(bundleBytes, signatureText, keys)) {
        throw new UpdateError('update signature is not valid for any trusted key');
    }
    let bundle;
    try {
        bundle = JSON.parse(bundleBytes.toString('utf8'));
    } catch (error) {
        throw new UpdateError('update bundle is not JSON');
    }
    if (bundle.schema !== BUNDLE_SCHEMA || bundle.product !== PRODUCT || bundle.resource !== 'humalike') {
        throw new UpdateError('update bundle is not a humalike resource bundle');
    }
    if (bundle.version !== expectedVersion) {
        throw new UpdateError(`update bundle is version ${bundle.version}, expected ${expectedVersion}`);
    }
    if (!Array.isArray(bundle.files) || bundle.files.length === 0) {
        throw new UpdateError('update bundle has no files');
    }
    const seen = new Set();
    const files = bundle.files.map((entry) => {
        if (!entry || !safeRelativePath(entry.path) || seen.has(entry.path)) {
            throw new UpdateError(`update bundle has an unsafe or duplicate path: ${entry && entry.path}`);
        }
        seen.add(entry.path);
        const content = Buffer.from(String(entry.data || ''), 'base64');
        if (content.length !== entry.size || sha256(content) !== entry.sha256) {
            throw new UpdateError(`update file ${entry.path} does not match its signed hash`);
        }
        return { path: entry.path, content };
    });
    if (!seen.has('fxmanifest.lua')) throw new UpdateError('update bundle has no fxmanifest.lua');
    return { version: bundle.version, revision: bundle.revision, files };
}

// FXServer refuses mkdir on a resource's own root, even a no-op recursive one.
function ensureDir(dir) {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (error) {
        return null;
    }
}

function listFiles(root, relative) {
    const base = path.join(root, relative);
    if (!fs.existsSync(base)) return [];
    const out = [];
    for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
        const child = relative ? `${relative}/${entry.name}` : entry.name;
        if (entry.isDirectory()) out.push(...listFiles(root, child));
        else if (entry.isFile()) out.push(child);
    }
    return out;
}

function installBundle(resourceDir, bundle, currentVersion) {
    const stateDir = path.join(resourceDir, STATE_DIR);
    const staging = path.join(stateDir, 'staging');
    const previous = path.join(stateDir, 'previous');
    fs.rmSync(staging, { recursive: true, force: true });
    ensureDir(staging);
    for (const file of bundle.files) {
        const target = path.join(staging, file.path);
        ensureDir(path.dirname(target));
        fs.writeFileSync(target, file.content);
    }

    const incoming = new Set(bundle.files.map((file) => file.path));
    const record = readJson(path.join(stateDir, 'installed.json'));
    const recorded = record && Array.isArray(record.files) ? record.files.filter(safeRelativePath) : null;
    // Without a record only the globbed NUI build is pruned.
    const stale = (recorded || listFiles(resourceDir, 'nui/host/dist'))
        .filter((relative) => !incoming.has(relative));

    fs.rmSync(previous, { recursive: true, force: true });
    const touched = [...incoming, ...stale].filter((relative) => {
        try {
            return fs.statSync(path.join(resourceDir, relative)).isFile();
        } catch (error) {
            return false;
        }
    });
    ensureDir(previous);
    for (const relative of touched) {
        const backup = path.join(previous, relative);
        ensureDir(path.dirname(backup));
        fs.copyFileSync(path.join(resourceDir, relative), backup);
    }
    fs.writeFileSync(path.join(previous, '.version'), `${currentVersion}\n`);

    const recordPath = path.join(stateDir, 'installed.json');
    const recordTemp = `${recordPath}.tmp`;
    const moved = [];
    try {
        for (const file of bundle.files) {
            const target = path.join(resourceDir, file.path);
            ensureDir(path.dirname(target));
            fs.renameSync(path.join(staging, file.path), target);
            moved.push(file.path);
        }
        for (const relative of stale) fs.rmSync(path.join(resourceDir, relative), { force: true });
        fs.writeFileSync(
            recordTemp,
            `${JSON.stringify({ version: bundle.version, revision: bundle.revision, files: [...incoming].sort() }, null, 2)}\n`,
        );
        fs.renameSync(recordTemp, recordPath);
    } catch (error) {
        const unrestored = [];
        for (const relative of touched) {
            try {
                fs.copyFileSync(path.join(previous, relative), path.join(resourceDir, relative));
            } catch (restoreError) {
                unrestored.push(relative);
            }
        }
        for (const relative of moved) {
            if (touched.includes(relative)) continue;
            try {
                fs.rmSync(path.join(resourceDir, relative), { force: true });
            } catch (cleanupError) {
                unrestored.push(relative);
            }
        }
        if (unrestored.length > 0) {
            // The backups in `previous` stay in place for a manual restore.
            throw new UpdateError(
                `could not write update files and the rollback is incomplete for ${unrestored.join(', ')}; `
                + `the previous files are kept in ${previous}: ${error.message}`,
            );
        }
        throw new UpdateError(`could not write update files, previous version restored: ${error.message}`);
    } finally {
        fs.rmSync(staging, { recursive: true, force: true });
        fs.rmSync(recordTemp, { force: true });
    }
}

function request(url, { maxBytes, headers = {}, redirects = 0 } = {}) {
    return new Promise((resolve, reject) => {
        let parsed;
        try {
            parsed = new URL(url);
        } catch (error) {
            reject(new UpdateError(`bad update URL ${url}`));
            return;
        }
        const client = parsed.protocol === 'https:' ? https : parsed.protocol === 'http:' ? http : null;
        if (!client) {
            reject(new UpdateError(`unsupported update URL ${url}`));
            return;
        }
        const req = client.get(parsed, {
            headers: { 'User-Agent': 'humalike-fivem-updater', ...headers },
            timeout: REQUEST_TIMEOUT_MS,
        }, (res) => {
            if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location) {
                res.resume();
                if (redirects >= MAX_REDIRECTS) {
                    reject(new UpdateError('too many redirects'));
                    return;
                }
                const next = new URL(res.headers.location, parsed).toString();
                resolve(request(next, { maxBytes, headers: {}, redirects: redirects + 1 }));
                return;
            }
            const chunks = [];
            let size = 0;
            res.on('data', (chunk) => {
                size += chunk.length;
                if (size > maxBytes) {
                    req.destroy(new UpdateError(`response from ${parsed.host} is larger than ${maxBytes} bytes`));
                    return;
                }
                chunks.push(chunk);
            });
            res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
            res.on('error', reject);
        });
        req.on('timeout', () => req.destroy(new UpdateError(`request to ${parsed.host} timed out`)));
        req.on('error', reject);
    });
}

async function fetchRelease(source, suffix) {
    const response = await request(`${source}/releases/${suffix}`, {
        maxBytes: MAX_JSON_BYTES,
        headers: { Accept: 'application/vnd.github+json' },
    });
    if (response.status === 404) return null;
    if (response.status !== 200) throw new UpdateError(`release lookup ${suffix} answered HTTP ${response.status}`);
    try {
        return releaseInfo(JSON.parse(response.body.toString('utf8')));
    } catch (error) {
        throw new UpdateError(`release lookup ${suffix} returned invalid JSON`);
    }
}

async function download(asset, label) {
    if (!asset || !asset.browser_download_url) throw new UpdateError(`release has no ${label}`);
    const response = await request(asset.browser_download_url, { maxBytes: MAX_BUNDLE_BYTES });
    if (response.status !== 200) throw new UpdateError(`${label} download answered HTTP ${response.status}`);
    return response.body;
}

async function runUpdate(env, { force = false } = {}) {
    const log = env.log;
    if (env.mode === 'off' && !force) return { action: 'none', reason: 'auto update is off' };
    const current = env.currentVersion;
    const pin = env.pin;
    const latest = pin ? null : await env.fetchRelease('latest');
    const pinned = pin ? await env.fetchRelease(`tags/v${pin}`) : null;
    let running = null;
    if (!pin && latest && parseVersion(current) && compareVersions(latest.version, current) < 0) {
        running = await env.fetchRelease(`tags/v${current}`);
    }
    const decision = decide({ current, pin, latest, pinned, running });
    if (decision.action === 'error') {
        log(`update: ${decision.reason}`);
        return decision;
    }
    if (decision.action === 'none') {
        log(`update: ${decision.reason} (running ${current})`);
        return decision;
    }
    const target = decision.target;
    if (env.mode === 'notify' && !force) {
        log(`update: ${decision.reason}; running ${current}. Set humalike_auto_update auto or run humalike_update to install it.`);
        return { action: 'notify', target, reason: decision.reason };
    }

    const statePath = path.join(env.resourceDir, STATE_DIR, 'state.json');
    const state = readJson(statePath) || {};
    if (!force && state.attempted === target.version && current !== target.version) {
        log(`update: ${target.version} was installed before but ${current} is still running; not retrying. Restart the server, or run humalike_update to try again.`);
        return { action: 'none', reason: 'previous attempt did not take effect' };
    }

    const bundleBytes = await env.download(target.bundle, 'update bundle');
    const signature = (await env.download(target.signature, 'update signature')).toString('utf8');
    const bundle = openBundle(bundleBytes, signature, target.version, env.trustedKeys || TRUSTED_KEYS);
    installBundle(env.resourceDir, bundle, current);
    ensureDir(path.dirname(statePath));
    fs.writeFileSync(statePath, `${JSON.stringify({ attempted: target.version, from: current, at: new Date().toISOString() })}\n`);

    if (env.canRestart()) {
        log(`update: installed ${target.version} (was ${current}); ${COMPANION} restarts humalike to apply it`);
        env.restart();
        return { action: 'installed', target, restarted: true, reason: decision.reason };
    }
    const grants = [`ensure ${COMPANION}`, ...RESTART_COMMANDS.map((command) => `add_ace resource.${COMPANION} command.${command} allow`)].join('; ');
    log(`update: installed ${target.version} (was ${current}); it applies on the next server restart. To apply updates automatically, add to server.cfg: ${grants}`);
    return { action: 'installed', target, restarted: false, reason: decision.reason };
}

function fivemEnvironment() {
    const resourceName = GetCurrentResourceName();
    const source = String(GetConvar('humalike_update_source', DEFAULT_SOURCE) || DEFAULT_SOURCE).replace(/\/+$/, '');
    const principal = `resource.${COMPANION}`;
    return {
        resourceName,
        resourceDir: GetResourcePath(resourceName),
        currentVersion: String(GetResourceMetadata(resourceName, 'version', 0) || ''),
        mode: parseMode(GetConvar('humalike_auto_update', 'auto')),
        pin: String(GetConvar('humalike_version', '') || '').trim().replace(/^v/, ''),
        log: (message) => console.log(`[humalike] ${message}`),
        fetchRelease: (suffix) => fetchRelease(source, suffix),
        download,
        canRestart: () => GetResourceState(COMPANION) === 'started'
            && RESTART_COMMANDS.every((command) => IsPrincipalAceAllowed(principal, `command.${command}`)),
        // A resource restarting itself from async code crashes FXServer
        // (citizenfx/fivem#1421), so humalike-updater does it.
        restart: () => emit('humalike:update:restart'),
    };
}

let running = false;
async function guardedRun(options) {
    if (running) return;
    running = true;
    try {
        await runUpdate(fivemEnvironment(), options);
    } catch (error) {
        console.log(`[humalike] update failed, keeping the current version: ${error.message}`);
    } finally {
        running = false;
    }
}

if (typeof GetCurrentResourceName === 'function' && typeof RegisterCommand === 'function') {
    setTimeout(() => guardedRun({}), 0);
    RegisterCommand('humalike_update', (source) => {
        if (Number(source) !== 0) return;
        guardedRun({ force: true });
    }, true);
}

if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        BUNDLE_ASSET,
        COMPANION,
        RESTART_COMMANDS,
        SIGNATURE_ASSET,
        STATE_DIR,
        TRUSTED_KEYS,
        UpdateError,
        compareVersions,
        decide,
        installBundle,
        openBundle,
        parseMode,
        parseVersion,
        releaseInfo,
        runUpdate,
        safeRelativePath,
        verifySignature,
    };
}
