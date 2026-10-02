const assert = require('node:assert/strict');
const http = require('node:http');
const { performRequest, handleRequest } = require('../../server/core/http_node.js');

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
    handleRequest('id-1', 'file:///etc/passwd', 'GET', '', {}, (...args) => resolve(args));
  });
  assert.equal(invalid[0], 0);
  assert.equal(invalid[3], 'invalid url');
  console.log('core_http_node.cjs: ok');
}

main().catch((error) => { console.error(error); process.exit(1); });
