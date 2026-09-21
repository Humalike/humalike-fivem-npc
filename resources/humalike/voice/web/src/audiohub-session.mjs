// Shared-microphone (audio hub) session state machine; the NUI is the
// answerer. Peer connections, timers, the NUI transport and the media sink
// are injected so it runs under node:test. Protocol: INTEGRATIONS.md.

import { attachStatus, parseAudioHubMessage, stateFailure } from "./audiohub-messages.mjs";

/** Silence from the hub after Attach before an attempt fails; `pending` resets it. */
export const NEGOTIATION_TIMEOUT_MS = 5_000;
/** Hard cap for one attempt, `pending` or not. */
export const NEGOTIATION_BUDGET_MS = 30_000;
/** How long an unavailable hub is waited for before the session errors. */
export const HUB_WAIT_MS = 30_000;
export const HUB_WAIT_MIN_MS = 500;
export const HUB_WAIT_MAX_MS = 4_000;
/** Further attempts after a failed negotiation, each with a fresh session id. */
export const RELAY_RETRIES = 2;
export const RELAY_RETRY_MS = 1_000;
/** NUI callback POSTs may fail while the resource is still starting. */
export const BRIDGE_RETRIES = 8;
export const BRIDGE_RETRY_MS = 250;
/** `disconnected` this long counts as a lost hub. */
export const DISCONNECT_GRACE_MS = 3_000;

/** A hub is registered but did not supply a track within the budget. */
export class HubUnavailableError extends Error {
  constructor(message) {
    super(message);
    this.name = "HubUnavailableError";
  }
}

export function createAudioHubClient(deps) {
  const {
    post,
    createPeerConnection,
    attachSink = () => () => undefined,
    createStream = (track) => new MediaStream([track]),
    setTimeout,
    clearTimeout,
    now = Date.now,
    onAvailable = () => undefined,
    log = () => undefined,
  } = deps;

  const sessions = new Map();
  let wake = null;
  let nextId = 0;
  const newId = () => `mic-${now().toString(36)}-${(nextId += 1)}`;

  const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  // A wait for an unavailable hub ends early when Lua reports it back.
  function waitForHub(ms) {
    return new Promise((resolve) => {
      const timer = setTimeout(() => { wake = null; resolve(); }, ms);
      wake = () => { clearTimeout(timer); wake = null; resolve(); };
    });
  }

  async function callBridge(name, body) {
    for (let attempt = 0; ; attempt += 1) {
      try {
        return await post(name, body);
      } catch (error) {
        if (attempt >= BRIDGE_RETRIES) throw error;
        await delay(BRIDGE_RETRY_MS);
      }
    }
  }

  async function goodbye(id, reason) {
    sessions.delete(id);
    await post("audiohubSignal", { id, payload: { type: "bye", reason } }).catch(() => undefined);
    await post("audiohubDetach", { id }).catch(() => undefined);
  }

  // Signals may arrive before the peer connection exists: keep them until
  // negotiate() binds a handler.
  function createSession(id) {
    const queue = [];
    let handler = (message) => { queue.push(message); };
    const session = {
      deliver: (message) => handler(message),
      bind: (next) => {
        handler = next;
        for (const message of queue.splice(0)) next(message);
      },
    };
    sessions.set(id, session);
    return session;
  }

  function negotiate(id, session, onLost) {
    return new Promise((resolve, reject) => {
      const pc = createPeerConnection();
      const deadline = now() + NEGOTIATION_BUDGET_MS;
      const hubCandidates = [];
      const localCandidates = [];
      let outbound = Promise.resolve();
      let offerApplied = false;
      let answered = false;
      let settled = false;
      let closed = false;
      let released = false;
      let lostReported = false;
      let timer = 0;
      let graceTimer = 0;

      function arm() {
        clearTimeout(timer);
        const ms = Math.max(0, Math.min(NEGOTIATION_TIMEOUT_MS, deadline - now()));
        timer = setTimeout(() => fail("hub negotiation timed out"), ms);
      }

      function teardown() {
        if (closed) return;
        closed = true;
        clearTimeout(timer);
        clearTimeout(graceTimer);
        sessions.delete(id);
        try { pc.close(); } catch { /* already closed */ }
      }

      function fail(reason) {
        if (settled || closed) return;
        settled = true;
        teardown();
        reject(new Error(reason));
      }

      function lost() {
        if (!settled || closed || released || lostReported) return;
        lostReported = true;
        onLost?.();
      }

      const broke = (reason) => (settled ? lost() : fail(reason));

      function send(payload) {
        outbound = outbound.then(async () => {
          if (closed) return;
          const response = await post("audiohubSignal", { id, payload });
          if (!response || response.ok !== true) {
            throw new Error(`hub signal refused: ${response?.reason ?? "no answer"}`);
          }
        }).catch((error) => broke(error instanceof Error ? error.message : String(error)));
        return outbound;
      }

      pc.addEventListener("icecandidate", (event) => {
        const candidate = event.candidate ? event.candidate.toJSON() : null;
        if (!answered) localCandidates.push(candidate);
        else void send({ type: "candidate", candidate });
      });

      pc.addEventListener("connectionstatechange", () => {
        const state = pc.connectionState;
        if (state === "failed" || state === "closed") {
          clearTimeout(graceTimer);
          broke(`hub connection ${state}`);
        } else if (state === "disconnected") {
          if (graceTimer) return;
          graceTimer = setTimeout(() => { graceTimer = 0; broke("hub connection lost"); }, DISCONNECT_GRACE_MS);
        } else if (state === "connected") {
          clearTimeout(graceTimer);
          graceTimer = 0;
        }
      });

      pc.addEventListener("track", (event) => {
        if (settled || closed || event.track.kind !== "audio") return;
        settled = true;
        clearTimeout(timer);
        const stream = event.streams?.[0] ?? createStream(event.track);
        const detachSink = attachSink(stream);
        event.track.addEventListener("ended", () => lost());
        resolve({
          stream,
          track: event.track,
          kind: "hub",
          release: () => {
            if (released) return;
            released = true;
            detachSink();
            teardown();
            void goodbye(id, "released");
          },
        });
      });

      session.bind((message) => {
        if (message.kind === "state") {
          if (message.state.pending === true && !settled) arm();
          const failure = stateFailure(message.state);
          if (failure) broke(failure);
          return;
        }
        const payload = message.payload;
        void (async () => {
          try {
            if (payload.type === "offer") {
              if (offerApplied) return;
              await pc.setRemoteDescription({ type: "offer", sdp: payload.sdp });
              offerApplied = true;
              for (const candidate of hubCandidates.splice(0)) {
                await pc.addIceCandidate(candidate).catch(() => undefined);
              }
              const answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              await send({ type: "answer", sdp: answer.sdp ?? "" });
              if (closed) return;
              answered = true;
              for (const candidate of localCandidates.splice(0)) void send({ type: "candidate", candidate });
            } else if (payload.type === "candidate") {
              if (!payload.candidate) return;
              if (!offerApplied) hubCandidates.push(payload.candidate);
              else await pc.addIceCandidate(payload.candidate).catch(() => undefined);
            } else if (payload.type === "bye") {
              broke(payload.reason ?? "hub closed the session");
            }
          } catch (error) {
            broke(error instanceof Error ? error.message : String(error));
          }
        })();
      });

      arm();
    });
  }

  /** Resolves with a hub handle, or null when no hub is registered. */
  async function acquire(options = {}) {
    const waitUntil = now() + HUB_WAIT_MS;
    let backoff = HUB_WAIT_MIN_MS;
    let relayFailures = 0;
    for (;;) {
      const id = newId();
      const session = createSession(id);
      let response;
      try {
        response = await callBridge("audiohubAttach", { id });
      } catch {
        sessions.delete(id);
        throw new Error("audio hub bridge did not answer");
      }
      const attach = attachStatus(response);
      if (!attach.ok) {
        sessions.delete(id);
        throw new Error(`audio hub attach refused: ${attach.reason}`);
      }
      if (attach.status === "none") {
        sessions.delete(id);
        return null;
      }
      if (attach.status !== "attached") {
        sessions.delete(id);
        const remaining = waitUntil - now();
        if (remaining <= 0) throw new HubUnavailableError(`hub unavailable (${attach.reason})`);
        log(`hub unavailable (${attach.reason}), waiting`);
        await waitForHub(Math.min(backoff, remaining));
        backoff = Math.min(backoff * 2, HUB_WAIT_MAX_MS);
        continue;
      }
      try {
        return await negotiate(id, session, options.onLost);
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        await goodbye(id, reason);
        if (relayFailures >= RELAY_RETRIES) throw new HubUnavailableError(reason);
        relayFailures += 1;
        log(`relay attempt failed (${reason}), retrying`);
        await delay(RELAY_RETRY_MS);
      }
    }
  }

  /** Feed a raw NUI window message; unrelated messages are ignored. */
  function handleMessage(data) {
    const message = parseAudioHubMessage(data);
    if (!message) return;
    if (message.kind === "available") {
      wake?.();
      onAvailable();
      return;
    }
    sessions.get(message.id)?.deliver(message);
  }

  return { acquire, handleMessage };
}
