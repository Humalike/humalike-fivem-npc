'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const updater = require('../../resources/humalike/server/updater/updater.js');

const keys = crypto.generateKeyPairSync('ed25519');
const publicPem = keys.publicKey.export({ type: 'spki', format: 'pem' });
const trusted = [publicPem];

function bundleFor(version, files) {
    const bundle = {
        schema: 1,
        product: 'humalike-fivem',
        resource: 'humalike',
        version,
        revision: 'a'.repeat(40),
        files: Object.entries(files).map(([file, text]) => {
            const data = Buffer.from(text);
            return {
                path: file,
                size: data.length,
                sha256: crypto.createHash('sha256').update(data).digest('hex'),
                data: data.toString('base64'),
            };
        }),
    };
    return Buffer.from(JSON.stringify(bundle));
}

function signed(bytes, key = keys.privateKey) {
    return crypto.sign(null, bytes, key).toString('base64');
}

function release(version, { withdrawn = false } = {}) {
    return {
        version,
        withdrawn,
        bundle: { browser_download_url: `bundle:${version}` },
        signature: { browser_download_url: `sig:${version}` },
    };
}

function resourceDir(files) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'humalike-updater-'));
    for (const [file, text] of Object.entries(files)) {
        fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true });
        fs.writeFileSync(path.join(dir, file), text);
    }
    return dir;
}

function read(dir, file) {
    return fs.readFileSync(path.join(dir, file), 'utf8');
}

test('versions compare as SemVer', () => {
    assert.equal(updater.compareVersions('0.5.1', '0.5.1'), 0);
    assert.equal(updater.compareVersions('0.5.2', '0.5.10'), -1);
    assert.equal(updater.compareVersions('1.0.0', '0.9.9'), 1);
    assert.equal(updater.compareVersions('1.0.0-rc.1', '1.0.0'), -1);
    assert.equal(updater.compareVersions('1.0.0-rc.2', '1.0.0-rc.10'), -1);
    assert.equal(updater.parseVersion('v1.0.0'), null);
});

test('mode defaults to auto and unknown values only notify', () => {
    assert.equal(updater.parseMode(''), 'auto');
    assert.equal(updater.parseMode('AUTO'), 'auto');
    assert.equal(updater.parseMode('off'), 'off');
    assert.equal(updater.parseMode('false'), 'off');
    assert.equal(updater.parseMode('notify'), 'notify');
    assert.equal(updater.parseMode('maybe'), 'notify');
});

test('releases without tags or drafts are ignored', () => {
    assert.equal(updater.releaseInfo({ tag_name: 'v0.6.0', draft: true }), null);
    assert.equal(updater.releaseInfo({ tag_name: 'nightly' }), null);
    const info = updater.releaseInfo({
        tag_name: 'v0.6.0',
        prerelease: true,
        assets: [{ name: updater.BUNDLE_ASSET }, { name: updater.SIGNATURE_ASSET }],
    });
    assert.equal(info.version, '0.6.0');
    assert.equal(info.withdrawn, true);
    assert.ok(info.bundle && info.signature);
});

test('decide installs newer releases and stays put otherwise', () => {
    assert.equal(updater.decide({ current: '0.5.1', latest: release('0.6.0') }).action, 'install');
    assert.equal(updater.decide({ current: '0.6.0', latest: release('0.6.0') }).action, 'none');
    assert.equal(updater.decide({ current: '0.5.1', latest: null }).action, 'none');
    assert.equal(updater.decide({ current: 'dev', latest: release('0.6.0') }).action, 'none');
});

test('decide never downgrades an unreleased build but rolls back a withdrawn one', () => {
    const latest = release('0.6.0');
    assert.equal(updater.decide({ current: '0.7.0', latest, running: null }).action, 'none');
    assert.equal(updater.decide({ current: '0.7.0', latest, running: release('0.7.0') }).action, 'none');
    const rollback = updater.decide({ current: '0.7.0', latest, running: release('0.7.0', { withdrawn: true }) });
    assert.equal(rollback.action, 'install');
    assert.equal(rollback.target.version, '0.6.0');
});

test('a pin moves to that exact version in either direction', () => {
    assert.equal(updater.decide({ current: '0.6.0', pin: '0.5.1', pinned: release('0.5.1') }).target.version, '0.5.1');
    assert.equal(updater.decide({ current: '0.5.1', pin: '0.6.0', pinned: release('0.6.0') }).target.version, '0.6.0');
    assert.equal(updater.decide({ current: '0.5.1', pin: '0.5.1', pinned: release('0.5.1') }).action, 'none');
    assert.equal(updater.decide({ current: '0.5.1', pin: '0.9.9', pinned: null }).action, 'error');
    assert.equal(updater.decide({ current: '0.5.1', pin: 'latest', pinned: null }).action, 'error');
});

test('a bundle opens only with a trusted signature and matching contents', () => {
    const bytes = bundleFor('0.6.0', { 'fxmanifest.lua': "version '0.6.0'\n", 'server/a.lua': 'print(1)\n' });
    const opened = updater.openBundle(bytes, signed(bytes), '0.6.0', trusted);
    assert.deepEqual(opened.files.map((file) => file.path), ['fxmanifest.lua', 'server/a.lua']);

    const stranger = crypto.generateKeyPairSync('ed25519').privateKey;
    assert.throws(() => updater.openBundle(bytes, signed(bytes, stranger), '0.6.0', trusted), /signature/);
    assert.throws(() => updater.openBundle(bytes, 'not-a-signature', '0.6.0', trusted), /signature/);
    assert.throws(() => updater.openBundle(bytes, signed(bytes), '0.6.1', trusted), /version/);

    const tampered = Buffer.from(bytes.toString().replace('"revision":"aaaa', '"revision":"bbbb'));
    assert.notDeepEqual(tampered, bytes);
    assert.throws(() => updater.openBundle(tampered, signed(bytes), '0.6.0', trusted), /signature/);
});

test('a signed bundle is still refused when a file does not match its listed hash', () => {
    const json = JSON.parse(bundleFor('0.6.0', { 'fxmanifest.lua': 'x' }).toString());
    json.files[0].data = Buffer.from('y').toString('base64');
    const bytes = Buffer.from(JSON.stringify(json));
    assert.throws(() => updater.openBundle(bytes, signed(bytes), '0.6.0', trusted), /does not match/);
});

test('unsafe paths and bundles without a manifest are refused even when signed', () => {
    for (const bad of ['../evil.lua', '/etc/passwd', 'a/../../b', 'a\\b.lua', '.humalike-update/state.json', '']) {
        const bytes = bundleFor('0.6.0', { 'fxmanifest.lua': 'x', [bad]: 'boom' });
        assert.throws(() => updater.openBundle(bytes, signed(bytes), '0.6.0', trusted), /unsafe/, bad);
    }
    const noManifest = bundleFor('0.6.0', { 'server/a.lua': 'x' });
    assert.throws(() => updater.openBundle(noManifest, signed(noManifest), '0.6.0', trusted), /fxmanifest/);
});

test('installing replaces files, keeps the previous version and prunes stale NUI chunks', () => {
    const dir = resourceDir({
        'fxmanifest.lua': "version '0.5.1'\n",
        'server/old.lua': 'old\n',
        'nui/host/dist/assets/index-OLD.js': 'old chunk\n',
        'custom.txt': 'owner file\n',
    });
    const bytes = bundleFor('0.6.0', {
        'fxmanifest.lua': "version '0.6.0'\n",
        'nui/host/dist/assets/index-NEW.js': 'new chunk\n',
    });
    updater.installBundle(dir, updater.openBundle(bytes, signed(bytes), '0.6.0', trusted), '0.5.1');

    assert.equal(read(dir, 'fxmanifest.lua'), "version '0.6.0'\n");
    assert.equal(read(dir, 'nui/host/dist/assets/index-NEW.js'), 'new chunk\n');
    assert.equal(fs.existsSync(path.join(dir, 'nui/host/dist/assets/index-OLD.js')), false);
    assert.equal(read(dir, 'server/old.lua'), 'old\n');
    assert.equal(read(dir, 'custom.txt'), 'owner file\n');
    assert.equal(read(dir, '.humalike-update/previous/fxmanifest.lua'), "version '0.5.1'\n");
    assert.equal(read(dir, '.humalike-update/previous/.version'), '0.5.1\n');
    assert.equal(fs.existsSync(path.join(dir, '.humalike-update/staging')), false);
});

test('a second update removes files the previous release shipped and the new one does not', () => {
    const dir = resourceDir({ 'custom.txt': 'owner file\n' });
    const first = bundleFor('0.6.0', { 'fxmanifest.lua': '6', 'server/gone.lua': 'x' });
    updater.installBundle(dir, updater.openBundle(first, signed(first), '0.6.0', trusted), '0.5.1');
    const second = bundleFor('0.7.0', { 'fxmanifest.lua': '7' });
    updater.installBundle(dir, updater.openBundle(second, signed(second), '0.7.0', trusted), '0.6.0');

    assert.equal(fs.existsSync(path.join(dir, 'server/gone.lua')), false);
    assert.equal(read(dir, 'custom.txt'), 'owner file\n');
    const record = JSON.parse(read(dir, '.humalike-update/installed.json'));
    assert.deepEqual(record.files, ['fxmanifest.lua']);
    assert.equal(record.version, '0.7.0');
});

test('a failed write restores the files that were there', () => {
    const dir = resourceDir({ 'fxmanifest.lua': 'old\n', 'server/a.lua': 'old a\n' });
    fs.mkdirSync(path.join(dir, 'server/b.lua'));
    const bytes = bundleFor('0.6.0', { 'fxmanifest.lua': 'new\n', 'server/a.lua': 'new a\n', 'server/b.lua': 'b' });
    assert.throws(
        () => updater.installBundle(dir, updater.openBundle(bytes, signed(bytes), '0.6.0', trusted), '0.5.1'),
        /previous version restored/,
    );
    assert.equal(read(dir, 'fxmanifest.lua'), 'old\n');
    assert.equal(read(dir, 'server/a.lua'), 'old a\n');
});

test('a rollback that cannot restore a file says so and keeps the backups', () => {
    const dir = resourceDir({ 'fxmanifest.lua': 'old\n', 'server/a.lua': 'old a\n' });
    fs.mkdirSync(path.join(dir, 'server/b.lua'));
    const bytes = bundleFor('0.6.0', { 'fxmanifest.lua': 'new\n', 'server/a.lua': 'new a\n', 'server/b.lua': 'b' });
    const backups = path.join(dir, '.humalike-update/previous');
    const copy = fs.copyFileSync;
    fs.copyFileSync = (from, to, ...rest) => {
        if (from === path.join(backups, 'server/a.lua')) throw new Error('disk full');
        return copy(from, to, ...rest);
    };
    try {
        assert.throws(
            () => updater.installBundle(dir, updater.openBundle(bytes, signed(bytes), '0.6.0', trusted), '0.5.1'),
            (error) => /rollback is incomplete for server\/a\.lua/.test(error.message)
                && error.message.includes(backups)
                && !/previous version restored/.test(error.message),
        );
    } finally {
        fs.copyFileSync = copy;
    }
    assert.equal(read(dir, 'fxmanifest.lua'), 'old\n');
    assert.equal(read(dir, '.humalike-update/previous/server/a.lua'), 'old a\n');
});

function environment(dir, overrides = {}) {
    const bundles = {};
    const events = { logs: [], restarts: 0 };
    const env = {
        resourceName: 'humalike',
        resourceDir: dir,
        currentVersion: '0.5.1',
        mode: 'auto',
        pin: '',
        trustedKeys: trusted,
        log: (message) => events.logs.push(message),
        releases: {},
        fetchRelease: async (suffix) => env.releases[suffix] || null,
        download: async (asset) => {
            const [kind, version] = asset.browser_download_url.split(':');
            return kind === 'bundle' ? bundles[version] : Buffer.from(signed(bundles[version]));
        },
        canRestart: () => true,
        restart: () => { events.restarts += 1; },
        ...overrides,
    };
    return {
        env,
        events,
        publish(version, files = { 'fxmanifest.lua': `version '${version}'\n` }) {
            bundles[version] = bundleFor(version, files);
        },
    };
}

test('a startup with a newer release installs it and restarts', async () => {
    const dir = resourceDir({ 'fxmanifest.lua': "version '0.5.1'\n" });
    const { env, events, publish } = environment(dir);
    publish('0.6.0');
    env.releases.latest = release('0.6.0');
    const result = await updater.runUpdate(env);
    assert.equal(result.action, 'installed');
    assert.equal(events.restarts, 1);
    assert.equal(read(dir, 'fxmanifest.lua'), "version '0.6.0'\n");
});

test('without the ACE grants the update is written and waits for the next restart', async () => {
    const dir = resourceDir({ 'fxmanifest.lua': "version '0.5.1'\n" });
    const { env, events, publish } = environment(dir, { canRestart: () => false });
    publish('0.6.0');
    env.releases.latest = release('0.6.0');
    const result = await updater.runUpdate(env);
    assert.equal(result.restarted, false);
    assert.equal(events.restarts, 0);
    assert.match(events.logs.at(-1), /ensure humalike-updater/);
    for (const command of ['refresh', 'ensure', 'stop', 'start']) {
        assert.match(events.logs.at(-1), new RegExp(`add_ace resource\\.humalike-updater command\\.${command} allow`));
    }
    assert.equal(updater.COMPANION, 'humalike-updater');
    assert.deepEqual(updater.RESTART_COMMANDS, ['refresh', 'ensure', 'stop', 'start']);
});

test('notify and off modes never touch files', async () => {
    for (const mode of ['notify', 'off']) {
        const dir = resourceDir({ 'fxmanifest.lua': 'old\n' });
        const { env, events, publish } = environment(dir, { mode });
        publish('0.6.0');
        env.releases.latest = release('0.6.0');
        await updater.runUpdate(env);
        assert.equal(read(dir, 'fxmanifest.lua'), 'old\n', mode);
        assert.equal(events.restarts, 0, mode);
    }
});

test('an install that did not take effect is not retried on every start', async () => {
    const dir = resourceDir({ 'fxmanifest.lua': 'old\n' });
    const { env, events, publish } = environment(dir);
    publish('0.6.0');
    env.releases.latest = release('0.6.0');
    await updater.runUpdate(env);
    const again = await updater.runUpdate(env);
    assert.equal(again.action, 'none');
    assert.equal(events.restarts, 1);
    const forced = await updater.runUpdate(env, { force: true });
    assert.equal(forced.action, 'installed');
});

test('a pinned server rolls back to the pinned release', async () => {
    const dir = resourceDir({ 'fxmanifest.lua': "version '0.6.0'\n" });
    const { env, publish } = environment(dir, { currentVersion: '0.6.0', pin: '0.5.1' });
    publish('0.5.1');
    env.releases['tags/v0.5.1'] = release('0.5.1');
    const result = await updater.runUpdate(env);
    assert.equal(result.target.version, '0.5.1');
    assert.equal(read(dir, 'fxmanifest.lua'), "version '0.5.1'\n");
});

test('withdrawing a release rolls its servers back to latest', async () => {
    const dir = resourceDir({ 'fxmanifest.lua': "version '0.7.0'\n" });
    const { env, publish } = environment(dir, { currentVersion: '0.7.0' });
    publish('0.6.0');
    env.releases.latest = release('0.6.0');
    env.releases['tags/v0.7.0'] = release('0.7.0', { withdrawn: true });
    const result = await updater.runUpdate(env);
    assert.equal(result.target.version, '0.6.0');
});

test('a bad signature leaves the installed version untouched', async () => {
    const dir = resourceDir({ 'fxmanifest.lua': 'old\n' });
    const { env, publish } = environment(dir);
    publish('0.6.0');
    env.releases.latest = release('0.6.0');
    env.trustedKeys = [crypto.generateKeyPairSync('ed25519').publicKey.export({ type: 'spki', format: 'pem' })];
    await assert.rejects(updater.runUpdate(env), /signature/);
    assert.equal(read(dir, 'fxmanifest.lua'), 'old\n');
});

test('the shipped trust list holds exactly one Ed25519 public key', () => {
    assert.equal(updater.TRUSTED_KEYS.length, 1);
    const key = crypto.createPublicKey(updater.TRUSTED_KEYS[0]);
    assert.equal(key.asymmetricKeyType, 'ed25519');
    assert.equal(key.type, 'public');
});

test('installing never calls mkdir on the resource root (FXServer refuses it)', () => {
    const dir = resourceDir({ 'fxmanifest.lua': 'old\n' });
    const original = fs.mkdirSync;
    const roots = [];
    fs.mkdirSync = function patched(target, ...rest) {
        if (path.resolve(target) === path.resolve(dir)) roots.push(target);
        return original.call(this, target, ...rest);
    };
    try {
        const bytes = bundleFor('0.6.0', { 'fxmanifest.lua': 'new\n', 'server/new/deep.lua': 'x' });
        updater.installBundle(dir, updater.openBundle(bytes, signed(bytes), '0.6.0', trusted), '0.5.1');
    } finally {
        fs.mkdirSync = original;
    }
    assert.deepEqual(roots, []);
    assert.equal(read(dir, 'server/new/deep.lua'), 'x');
});

test('a failed update keeps the previous install record', () => {
    const dir = resourceDir({});
    const first = bundleFor('0.6.0', { 'fxmanifest.lua': '6', 'server/a.lua': 'a' });
    updater.installBundle(dir, updater.openBundle(first, signed(first), '0.6.0', trusted), '0.5.1');
    fs.mkdirSync(path.join(dir, 'server/b.lua'));
    const second = bundleFor('0.7.0', { 'fxmanifest.lua': '7', 'server/b.lua': 'b' });
    assert.throws(
        () => updater.installBundle(dir, updater.openBundle(second, signed(second), '0.7.0', trusted), '0.6.0'),
        /previous version restored/,
    );
    const record = JSON.parse(read(dir, '.humalike-update/installed.json'));
    assert.equal(record.version, '0.6.0');
    assert.deepEqual(record.files, ['fxmanifest.lua', 'server/a.lua']);
    assert.equal(fs.existsSync(path.join(dir, '.humalike-update/installed.json.tmp')), false);
});
