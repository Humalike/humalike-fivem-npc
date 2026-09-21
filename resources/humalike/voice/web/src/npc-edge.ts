declare const GetParentResourceName: undefined | (() => string);

interface ConnectMessage {
  type: "npc_edge_connect";
  stream_url: string;
  ticket: string;
  client_boot_id: string;
}

interface FrameMessage {
  type: "npc_edge_frame";
  frame: Record<string, unknown> & { type: string };
}

const MAX_BUFFERED_BYTES = 64 * 1024;

export function installNpcEdgeTransport(): void {
  let socket: WebSocket | null = null;
  const pending = new Map<string, Record<string, unknown>>();
  let coalescedFrames = 0;
  let flushTimer = 0;
  let heartbeatTimer = 0;
  let statsTimer = 0;

  const clearConnectionTimers = () => {
    window.clearTimeout(flushTimer); flushTimer = 0;
    window.clearInterval(heartbeatTimer); heartbeatTimer = 0;
  };

  const reportStatsLater = () => {
    if (statsTimer !== 0) return;
    statsTimer = window.setTimeout(() => {
      statsTimer = 0; void nui("npcEdgeStats", { coalescedFrames });
    }, 5_000);
  };

  const flush = () => {
    flushTimer = 0;
    if (!socket || socket.readyState !== WebSocket.OPEN
      || socket.bufferedAmount >= MAX_BUFFERED_BYTES) {
      if (pending.size > 0 && socket) flushTimer = window.setTimeout(flush, 20);
      return;
    }
    for (const [key, frame] of pending) {
      if (!socket || socket.bufferedAmount >= MAX_BUFFERED_BYTES) break;
      pending.delete(key); socket.send(JSON.stringify(frame));
    }
    if (pending.size > 0) flushTimer = window.setTimeout(flush, 20);
  };

  const scheduleFlush = () => {
    if (flushTimer === 0) flushTimer = window.setTimeout(flush, 0);
  };

  const nui = (name: string, body: object = {}) => {
    if (typeof GetParentResourceName !== "function") return Promise.resolve();
    return fetch(`https://${GetParentResourceName()}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }).then(() => undefined);
  };

  const connect = (message: ConnectMessage) => {
    socket?.close(1000, "replaced");
    clearConnectionTimers();
    pending.clear();
    const current = new WebSocket(message.stream_url);
    socket = current;
    current.onopen = () => {
      current.send(JSON.stringify({ type: "authenticate", ticket: message.ticket,
        client_boot_id: message.client_boot_id }));
      heartbeatTimer = window.setInterval(() => {
        if (socket === current && current.readyState === WebSocket.OPEN
          && current.bufferedAmount < MAX_BUFFERED_BYTES) {
          current.send(JSON.stringify({ type: "heartbeat" }));
        }
      }, 25_000);
      scheduleFlush();
    };
    current.onmessage = ({ data }) => {
      if (socket !== current) return;
      try {
        if (JSON.parse(String(data)).type === "ready") void nui("npcEdgeReady");
      } catch { /* malformed edge messages do not break the transport */ }
    };
    current.onclose = ({ code, reason }) => {
      if (socket !== current) return;
      clearConnectionTimers();
      socket = null;
      pending.clear();
      void nui("npcEdgeClosed", { reason: `${code}:${reason}` });
    };
  };

  window.addEventListener("message", ({ data }: MessageEvent<unknown>) => {
    if (!data || typeof data !== "object") return;
    const message = data as ConnectMessage | FrameMessage | { type?: string };
    if (message.type === "npc_edge_connect") connect(message as ConnectMessage);
    else if (message.type === "npc_edge_disconnect") {
      const current = socket;
      socket = null;
      current?.close(1000, "assignment changed");
      pending.clear();
      clearConnectionTimers();
    }
    else if (message.type === "npc_edge_frame") {
      const frame = (message as FrameMessage).frame;
      frame.observed_at_ms = Date.now();
      if (pending.has(frame.type)) { coalescedFrames += 1; reportStatsLater(); }
      pending.set(frame.type, frame);
      scheduleFlush();
    } else if (message.type === "shutdown" || message.type === "voice:shutdown") {
      socket?.close(1000, "resource stopping");
      socket = null;
      pending.clear();
      clearConnectionTimers();
      window.clearTimeout(statsTimer); statsTimer = 0;
    }
  });

}
