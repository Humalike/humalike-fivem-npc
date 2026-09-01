import { isServerMessage, PROTOCOL_VERSION, type RealtimeState, type ServerMessage } from "./protocol";

export type ControlStatus = "idle" | "connecting" | "connected" | "closed" | "error";

export class ControlClient {
  #socket: WebSocket | null = null;
  #pending: RealtimeState | null = null;
  #flushTimer = 0;
  #readyTimer = 0;
  #authenticated = false;

  constructor(
    private readonly url: string,
    private readonly ticket: string,
    private readonly onMessage: (message: ServerMessage) => void,
    private readonly onStatus: (status: ControlStatus) => void,
  ) {}

  connect(): void {
    this.onStatus("connecting");
    this.#readyTimer = window.setTimeout(() => {
      const socket = this.#socket;
      if (!socket || this.#authenticated) return;
      this.onStatus("error");
      try { socket.close(4000, "control ready timeout"); } catch { /* already failed */ }
    }, 5000);
    let socket: WebSocket;
    try {
      socket = new WebSocket(this.url);
    } catch {
      this.#cleanup();
      this.onStatus("error");
      return;
    }
    this.#socket = socket;
    socket.addEventListener("open", () => {
      try {
        socket.send(JSON.stringify({ v: PROTOCOL_VERSION, type: "authenticate", ticket: this.ticket }));
      } catch {
        this.onStatus("error");
        socket.close(4000, "control authenticate failed");
      }
    });
    socket.addEventListener("message", (event) => {
      if (typeof event.data !== "string") return;
      try {
        const message: unknown = JSON.parse(event.data);
        if (!isServerMessage(message)) return;
        if (message.type === "ready" && !this.#authenticated) {
          this.#authenticated = true;
          window.clearTimeout(this.#readyTimer); this.#readyTimer = 0;
          this.onStatus("connected");
          this.#scheduleFlush();
        }
        this.onMessage(message);
      } catch { /* bounded invalid server frame */ }
    });
    socket.addEventListener("error", () => this.onStatus("error"));
    socket.addEventListener("close", () => { this.#cleanup(); this.onStatus("closed"); });
  }

  realtime(state: RealtimeState): void { this.#pending = state; this.#scheduleFlush(); }

  transmit(generation: number, mask: number, targetNpcIds?: string[]): boolean {
    const socket = this.#socket;
    if (!socket || !this.#authenticated || socket.readyState !== WebSocket.OPEN) return false;
    if (socket.bufferedAmount > 64 * 1024) { socket.close(1013, "control backpressure"); return false; }
    socket.send(JSON.stringify({ v: PROTOCOL_VERSION, type: "tx_state", generation, mask,
      ...(targetNpcIds ? { targetNpcIds } : {}) }));
    return true;
  }

  close(): void { this.#socket?.close(1000, "client shutdown"); this.#socket = null; this.#cleanup(); }

  #flush(): void {
    this.#flushTimer = 0;
    const state = this.#pending;
    const socket = this.#socket;
    if (!state || !socket || !this.#authenticated || socket.readyState !== WebSocket.OPEN
      || socket.bufferedAmount > 64 * 1024) {
      if (state && socket && this.#authenticated) this.#scheduleFlush();
      return;
    }
    this.#pending = null;
    socket.send(JSON.stringify(state));
  }

  #scheduleFlush(): void {
    if (this.#flushTimer !== 0 || !this.#pending || !this.#authenticated) return;
    this.#flushTimer = window.setTimeout(() => this.#flush(), 50);
  }

  #cleanup(): void {
    window.clearTimeout(this.#flushTimer); this.#flushTimer = 0;
    window.clearTimeout(this.#readyTimer); this.#readyTimer = 0;
    this.#authenticated = false;
  }
}
