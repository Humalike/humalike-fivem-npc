#!/usr/bin/env node
// Signs a release's update bundle with the Ed25519 release key and refuses to
// produce a signature the shipped updater would not accept.
//
//   HUMALIKE_RELEASE_SIGNING_KEY="$(cat key.pem)" node scripts/sign_update.mjs artifacts/humalike.update.json
//
// Writes <bundle>.sig (base64). The private key is only ever read from the
// environment; it is never written to disk by this script.
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const updater = require(path.join(root, 'resources/humalike/server/updater/updater.js'));

const bundlePath = process.argv[2];
const keyPem = process.env.HUMALIKE_RELEASE_SIGNING_KEY;
if (!bundlePath) {
    console.error('usage: node scripts/sign_update.mjs <humalike.update.json>');
    process.exit(2);
}
if (!keyPem || !keyPem.includes('PRIVATE KEY')) {
    console.error('HUMALIKE_RELEASE_SIGNING_KEY is not set to a PEM private key');
    process.exit(1);
}

const bundle = readFileSync(bundlePath);
const signature = sign(null, bundle, createPrivateKey(keyPem)).toString('base64');
if (!updater.verifySignature(bundle, signature)) {
    console.error('the signing key is not one of the keys the updater trusts (TRUSTED_KEYS in updater.js)');
    process.exit(1);
}
const version = JSON.parse(bundle.toString('utf8')).version;
updater.openBundle(bundle, signature, version);
writeFileSync(`${bundlePath}.sig`, `${signature}\n`);
console.log(`signed ${path.basename(bundlePath)} ${version}`);
