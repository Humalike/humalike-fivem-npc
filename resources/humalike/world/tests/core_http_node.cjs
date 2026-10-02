const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const vm = require('node:vm');
const { performRequest, handleRequest, requestTimeout } = require('../../server/core/http_node.js');

const scriptPath = path.join(__dirname, '../../server/core/http_node.js');

// Load the script the way FXServer does: a plain script with FiveM globals and
// no CommonJS module, so the export registration path runs.
function loadInFxServer(invoker, fetchImpl) {
  const registered = {};
  const fetchCalls = [];
  const context = {
    exports: (name, fn) => { registered[name] = fn; },
    fetch: async (url, options) => {
      fetchCalls.push({ url, options });
      return fetchImpl(url, options);
    },
    GetCurrentResourceName: () => 'humalike',
    GetInvokingResource: () => invoker.current,
    AbortController,
    setTimeout,
    clearTimeout,
    console,
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(scriptPath, 'utf8'), context, { filename: scriptPath });
  return { registered, fetchCalls };
}

async function exportGuard() {
  const invoker = { current: 'humalike' };
  const { registered, fetchCalls } = loadInFxServer(invoker, async () => new Response('{"ok":true}',
    { status: 200, headers: { 'Content-Type': 'application/json' } }));
  const request = registered.humalikeNodeHttpRequest;
  assert.equal(typeof request, 'function', 'the export must be registered under FXServer');

  const own = await new Promise((resolve) => {
    request('id-1', 'https://api.example/v1/npc/actions/a', 'POST', '{}',
      { Authorization: 'Bearer t' }, 120000, (...args) => resolve(args));
  });
  assert.equal(own[0], 200);
  assert.equal(own[1], '{"ok":true}');
  assert.equal(own[3], null);
  assert.equal(fetchCalls.length, 1);
  assert.equal(fetchCalls[0].options.headers.Authorization, 'Bearer t');

  invoker.current = 'other-resource';
  let called = false;
  assert.throws(() => request('id-2', 'https://api.example/x', 'POST', '{}',
    { Authorization: 'Bearer t' }, 30000, () => { called = true; }), /private to this resource/);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(called, false, 'a refused call must not run its callback');
  assert.equal(fetchCalls.length, 1, 'a refused call must not send a request');
}

async function main() {
  const seen = [];
  const server = http.createServer((request, response) => {
    let body = '';
    request.on('data', (chunk) => { body += chunk; });
    request.on('end', () => {
      seen.push({ method: request.method, url: request.url, headers: request.headers, body });
      if (request.url === '/slow') return;
      response.writeHead(request.url === '/missing' ? 409 : 200,
        { 'Content-Type': 'application/json', 'X-Test': 'yes' });
      response.end(request.url === '/missing' ? '{"error":{"code":"x"}}' : '{"ok":true}');
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;

  const ok = await performRequest(`${base}/v1/npc/actions/a`, 'POST', '{}',
    { Authorization: 'Bearer t', 'Content-Type': 'application/json' });
  assert.equal(ok.status, 200);
  assert.equal(ok.body, '{"ok":true}');
  assert.equal(ok.headers['x-test'], 'yes');
  assert.equal(ok.error, null);
  assert.equal(seen[0].method, 'POST');
  assert.equal(seen[0].body, '{}');
  assert.equal(seen[0].headers.authorization, 'Bearer t');

  const rejected = await performRequest(`${base}/missing`, 'POST', '{}', {});
  assert.equal(rejected.status, 409);
  assert.equal(rejected.body, '{"error":{"code":"x"}}', 'error bodies must reach Lua');

  const slow = await performRequest(`${base}/slow`, 'POST', '{}', {}, 100);
  assert.equal(slow.status, 0);
  assert.equal(slow.error, 'request timed out');

  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
  const refused = await performRequest(`${base}/gone`, 'POST', '{}', {});
  assert.equal(refused.status, 0);
  assert.ok(refused.error, 'network failures must report an error');

  const invalid = await new Promise((resolve) => {
    handleRequest('id-1', 'file:///etc/passwd', 'GET', '', {}, 30000, (...args) => resolve(args));
  });
  assert.equal(invalid[0], 0);
  assert.equal(invalid[3], 'invalid url');

  assert.equal(requestTimeout(undefined), 30000);
  assert.equal(requestTimeout(null), 30000);
  assert.equal(requestTimeout(-1), 30000);
  assert.equal(requestTimeout(120000), 120000);
  assert.equal(requestTimeout(10 ** 9), 600000);

  await exportGuard();
  console.log('core_http_node.cjs: ok');
}

main().catch((error) => { console.error(error); process.exit(1); });
