const $ = (id) => document.getElementById(id);
let rows = [], opened = false, generation = 0, deleting = null;
let selectedKind = 'external';
let refreshPending = false, queue = Promise.resolve(), lastSentAt = 0;
const busyNpcs = new Set(), renderedRows = new Map();
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'humalike-control-test';
async function post(route, data = {}) {
  const response = await fetch(`https://${resource}/${route}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data), signal: AbortSignal.timeout(10000) });
  return response.json();
}
function message(text, error = false) { $('message').textContent = text || ''; $('message').classList.toggle('error', error); }
function text(tag, value, className) { const node = document.createElement(tag); node.textContent = value; if (className) node.className = className; return node; }
function action(label, operation, row, disabled, style) {
  const button = text('button', label, style); button.disabled = busyNpcs.has(row.npcId) || disabled;
  button.addEventListener('click', () => {
    if (operation === 'delete') { deleting = row.npcId; $('confirm-name').textContent = row.name; $('confirm').showModal(); }
    else request(operation, row.npcId);
  });
  return button;
}
function render() {
  const tabRows = rows.filter(row => row.kind === selectedKind);
  for (const kind of ['external', 'static', 'dynamic']) $(`${kind}-tab`).setAttribute('aria-pressed', String(selectedKind === kind));
  $('total-label').textContent = `${selectedKind[0].toUpperCase()}${selectedKind.slice(1)} NPCs`;
  $('bound-label').textContent = selectedKind === 'external' ? 'Bound' : 'Active';
  $('bound-option').textContent = selectedKind === 'external' ? 'Bound' : 'Active';
  $('total').textContent = tabRows.length;
  $('bound').textContent = tabRows.filter(r => selectedKind !== 'external' ? r.active : r.bound).length;
  $('offline').textContent = tabRows.filter(r => !r.active).length;
  $('owned').textContent = tabRows.filter(r => r.testPed).length;
  const search = $('search').value.toLowerCase(), filter = $('filter').value;
  const shown = tabRows.filter(r => `${r.name} ${r.model} ${r.npcId}`.toLowerCase().includes(search) && (filter === 'all' || filter === 'bound' && (selectedKind !== 'external' ? r.active : r.bound) || filter === 'offline' && !r.active || filter === 'test' && r.testPed));
  const visibleIds = new Set(shown.map(row => row.npcId));
  for (const [id, cached] of renderedRows) {
    if (!visibleIds.has(id)) { cached.node.remove(); renderedRows.delete(id); }
  }
  $('empty').hidden = shown.length !== 0;
  $('empty').textContent = tabRows.length ? 'No NPCs match these filters.' : `No ${selectedKind} NPCs in the synced roster.`;
  for (const [index, row] of shown.entries()) {
    const signature = JSON.stringify([row, busyNpcs.has(row.npcId)]);
    const cached = renderedRows.get(row.npcId);
    if (cached?.signature === signature) {
      if ($('rows').children[index] !== cached.node) $('rows').insertBefore(cached.node, $('rows').children[index] || null);
      continue;
    }
    const tr = document.createElement('tr'), identity = document.createElement('td'), runtime = document.createElement('td'), body = document.createElement('td'), actions = document.createElement('td');
    identity.append(text('span', row.name, 'name'), text('span', row.model || 'No model', 'detail'), text('span', row.npcId, 'detail'));
    runtime.append(text('span', row.kind !== 'external' ? (row.active ? 'Active' : 'Offline') : row.bound ? 'Bound' : row.testPed ? 'Unbound ped' : 'Offline', `badge${row.active ? ' online' : ''}`), text('span', row.aiEnabled ? 'AI enabled' : 'AI inactive', 'detail'), text('span', (row.domains || []).join(', '), 'detail'));
    body.append(text('span', row.testPed ? 'Test resource' : row.owner || (row.active ? 'HumaLike runtime' : 'No body')), text('span', row.networkId ? `Net ${row.networkId} · bucket ${row.routingBucket ?? '?'}` : '—', 'detail'));
    const group = document.createElement('div'); group.className = 'actions';
    group.append(action('Teleport', 'teleport', row, !row.canTeleport));
    if (row.kind === 'external') group.append(action(row.testPed ? 'Respawn here' : 'Spawn & bind', 'bind', row, row.active && !row.testPed, 'primary'), action('Unbind', 'unbind', row, !row.canUnbind), action('Delete ped', 'delete', row, !row.testPed, 'danger'), action('Control 30s', 'control', row, !row.testPed || !row.active || row.canRelease), action('Release', 'release', row, !row.canRelease || !row.testPed));
    actions.append(group); tr.append(identity, runtime, body, actions);
    if (cached) cached.node.replaceWith(tr);
    else $('rows').insertBefore(tr, $('rows').children[index] || null);
    renderedRows.set(row.npcId, { signature, node: tr });
  }
}
function request(operation = 'refresh', npcId) {
  if (!opened) return;
  const refreshing = operation === 'refresh', epoch = generation;
  if (refreshing ? refreshPending : busyNpcs.has(npcId)) return;
  if (refreshing) refreshPending = true;
  else busyNpcs.add(npcId);
  render();
  // Serialize requests so a click during polling is queued, not discarded.
  queue = queue.then(async () => {
    try {
      const wait = Math.max(0, 300 - (Date.now() - lastSentAt));
      if (wait) await new Promise(resolve => setTimeout(resolve, wait));
      if (!opened || epoch !== generation) return;
      lastSentAt = Date.now();
      const response = await post('request', { operation, npcId });
      if (!opened || epoch !== generation) return;
      if (Array.isArray(response.rows)) { rows = response.rows; $('updated').textContent = `Updated ${new Date().toLocaleTimeString()}`; }
      if (!response.ok || !refreshing) message(response.message || 'Request failed', !response.ok);
      else if ($('message').classList.contains('error')) message('');
    } catch {
      if (opened && epoch === generation) message('Cannot reach the test resource. Check that it is running.', true);
    } finally {
      if (epoch === generation) {
        if (refreshing) refreshPending = false;
        else busyNpcs.delete(npcId);
        render();
      }
    }
  });
  return queue;
}
function close() { opened = false; generation++; refreshPending = false; busyNpcs.clear(); deleting = null; $('panel').hidden = true; $('confirm').close(); post('close').catch(() => {}); }
window.addEventListener('message', ({ data }) => {
  if (data.type === 'open') { opened = true; generation++; refreshPending = false; busyNpcs.clear(); $('panel').hidden = false; message(''); if (Array.isArray(data.rows)) { rows = data.rows; render(); } else request(); }
  if (data.type === 'close') { opened = false; generation++; refreshPending = false; busyNpcs.clear(); $('panel').hidden = true; $('confirm').close(); }
});
$('close').addEventListener('click', close);
document.addEventListener('keydown', event => { if (event.key === 'Escape' && !$('confirm').open) close(); });
$('refresh').addEventListener('click', () => request());
for (const kind of ['external', 'static', 'dynamic']) {
  $(`${kind}-tab`).addEventListener('click', () => { selectedKind = kind; $('filter').value = 'all'; render(); });
}
$('search').addEventListener('input', render); $('filter').addEventListener('change', render);
$('cancel-delete').addEventListener('click', () => { deleting = null; $('confirm').close(); });
$('confirm-delete').addEventListener('click', () => { const id = deleting; deleting = null; $('confirm').close(); if (id) request('delete', id); });
setInterval(() => { if (opened && !refreshPending && !busyNpcs.size && !$('confirm').open) request(); }, 2000);
