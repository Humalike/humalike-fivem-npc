(() => {
  let socket = null;
  const pending = new Map();
  let bootId = null;
  let coalescedFrames = 0;
  const MAX_BUFFERED_BYTES = 64 * 1024;

  const nui = (name, body = {}) => fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });

  const connect = ({ stream_url: url, ticket, client_boot_id: id }) => {
    if (socket) socket.close(1000, 'replaced');
    pending.clear();
    bootId = id;
    const current = new WebSocket(url);
    socket = current;
    current.onopen = () => current.send(JSON.stringify({
      type: 'authenticate', ticket, client_boot_id: bootId,
    }));
    current.onmessage = ({ data }) => {
      if (socket !== current) return;
      try {
        if (JSON.parse(data).type === 'ready') void nui('npcEdgeReady');
      } catch (_) { /* malformed server messages do not break the transport */ }
    };
    current.onerror = () => { /* onclose owns reconnect state */ };
    current.onclose = ({ code, reason }) => {
      if (socket !== current) return;
      socket = null;
      pending.clear();
      void nui('npcEdgeClosed', { reason: `${code}:${reason}` });
    };
  };

  window.addEventListener('message', ({ data }) => {
    if (data.type === 'npc_edge_connect') connect(data);
    else if (data.type === 'npc_edge_frame') {
      data.frame.observed_at_ms = Date.now();
      if (pending.has(data.frame.type)) coalescedFrames += 1;
      pending.set(data.frame.type, data.frame);
    } else if (data.type === 'shutdown') {
      if (socket) socket.close(1000, 'resource stopping');
      socket = null;
      pending.clear();
    }
  });

  setInterval(() => {
    if (pending.size === 0 || !socket || socket.readyState !== WebSocket.OPEN
      || socket.bufferedAmount >= MAX_BUFFERED_BYTES) return;
    for (const [key, frame] of pending) {
      if (socket.bufferedAmount >= MAX_BUFFERED_BYTES) break;
      pending.delete(key);
      socket.send(JSON.stringify(frame));
    }
  }, 20);

  setInterval(() => {
    if (socket && socket.readyState === WebSocket.OPEN
      && socket.bufferedAmount < MAX_BUFFERED_BYTES) {
      socket.send(JSON.stringify({ type: 'heartbeat' }));
    }
  }, 25000);

  setInterval(() => void nui('npcEdgeStats', { coalescedFrames }), 5000);
})();
