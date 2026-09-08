const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
class Element {
  constructor() { this.children = []; this.value = ''; this.classList = { toggle() {}, contains() { return false; } }; }
  append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } }
  insertBefore(node, before) { node.remove(); const index = before ? this.children.indexOf(before) : this.children.length; this.children.splice(index, 0, node); node.parent = this; }
  remove() { if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1); this.parent = null; }
  replaceWith(node) { const parent = this.parent, index = parent.children.indexOf(this); parent.children[index] = node; node.parent = parent; this.parent = null; }
  addEventListener(name, callback) { this[name] = callback; }
  setAttribute(name, value) { this[name] = value; }
  close() { this.open = false; }
}
const elements = new Map();
const get = id => { if (!elements.has(id)) elements.set(id, new Element()); return elements.get(id); };
get('filter').value = 'all';
let onMessage, resolveRefresh;
const requests = [];
const roster = ['a', 'b'].map(npcId => ({ npcId, kind: 'external', canTeleport: true, name: npcId, model: 'ped', active: true, bound: true, testPed: true, domains: [] }));
const context = vm.createContext({
  document: { getElementById: get, createElement: () => new Element(), addEventListener() {} },
  window: { addEventListener: (_, callback) => { onMessage = callback; } },
  AbortSignal, setInterval() {}, setTimeout: callback => { callback(); },
  fetch: async (_, options) => {
    const data = JSON.parse(options.body); requests.push(data);
    if (data.operation === 'refresh') await new Promise(resolve => { resolveRefresh = resolve; });
    return { json: async () => ({ ok: true, rows: roster, message: 'ok' }) };
  },
});
vm.runInContext(fs.readFileSync('examples/humalike-control-test/web/app.js', 'utf8'), context);
(async () => {
  onMessage({ data: { type: 'open', rows: roster } });
  const [first, second] = get('rows').children;
  const polling = vm.runInContext('request()', context);
  await Promise.resolve();
  assert.equal(get('rows').children[0], first, 'Polling must preserve the existing row and buttons');
  const action = vm.runInContext("request('control', 'a')", context);
  assert.equal(get('rows').children[1], second, 'An action must not replace another NPC row');
  assert.equal(requests.length, 1, 'Action waits for the active refresh');
  resolveRefresh();
  await polling; await action;
  assert.deepEqual(requests.map(r => r.operation), ['refresh', 'control'], 'A click during refresh must execute');
  assert.equal(get('rows').children[1], second, 'Unchanged rows survive both responses');
  const stable = get('rows').children[0];
  const next = vm.runInContext('request()', context);
  await Promise.resolve(); await Promise.resolve();
  resolveRefresh(); await next;
  assert.equal(get('rows').children[0], stable, 'Identical refresh must not rebuild controls');
  roster.push({ npcId: 'static', kind: 'static', active: true, canTeleport: true, name: 'Static guard', domains: [] });
  get('static-tab').click();
  assert.equal(get('rows').children.length, 1);
  const staticButtons = get('rows').children[0].children[3].children[0].children;
  assert.equal(staticButtons.length, 1, 'Static NPCs only expose teleport');
  assert.equal(staticButtons[0].textContent, 'Teleport');
  assert.equal(staticButtons[0].disabled, false);
  assert.equal(get('bound-label').textContent, 'Active');
  get('external-tab').click();
  assert.equal(get('rows').children.length, 2);
  roster.push({ npcId: 'dynamic', kind: 'dynamic', active: true, canTeleport: true, name: 'Dynamic NPC', domains: [] });
  get('dynamic-tab').click();
  assert.equal(get('rows').children.length, 1);
  assert.equal(get('total-label').textContent, 'Dynamic NPCs');
  assert.equal(get('rows').children[0].children[3].children[0].children.length, 1);
  console.log('control panel web: ok');
})().catch(error => { console.error(error); process.exitCode = 1; });
