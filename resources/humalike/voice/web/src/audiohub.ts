import {
  attachAvailable,
  parseAudioHubMessage,
  stateFailure,
  type AudioHubSignalPayload,
  type AudioHubState,
} from "./audiohub-messages.mjs";

declare const GetParentResourceName: undefined | (() => string);

/**
 * Shared-microphone client.
 *
 * Every NUI resource on a FiveM client runs in its own CEF frame with its own
 * origin, so each resource that wants microphone audio normally calls
 * `getUserMedia` itself. Some servers run an "audio hub" resource that opens
 * the capture once and relays the live track to any frame that asks over a
 * loopback `RTCPeerConnection` (only the SDP/ICE blobs travel through Lua;
 * the audio does not).
 *
 * This module is the voice NUI's client for such a hub, speaking through the
 * adapter bridge in `voice/client/audiohub.lua`. It is entirely optional: when
 * no adapter is registered — the default for a standalone install — the bridge
 * answers `available: false` and {@link acquireMicrophoneSource} opens the
 * device directly, which is exactly what the voice NUI did before.
 *
 * When a hub *is* available it owns the device, and a relay that fails is
 * retried against it rather than worked around locally. A second capture
 * alongside the hub's is not a fallback but a conflict: on hardware that will
 * not share an input it silences both. {@link acquireMicrophoneSource} throws
 * {@link HubUnavailableError} instead.
 */

export type MicrophoneSourceKind = "hub" | "local";

export interface MicrophoneSourceHandle {
  stream: MediaStream;
  track: MediaStreamTrack;
  /** Where the audio came from. Useful for diagnostics, not for behaviour. */
  kind: MicrophoneSourceKind;
  /**
   * Detach from the hub, or stop the local capture. Always call this instead
   * of stopping tracks by hand — stopping a relayed track does not release the
   * hub session.
   */
  release: () => void;
}

/** The hub is running but could not supply a track. */
export class HubUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "HubUnavailableError";
  }
}

/** How long to wait for a relayed track before giving up on one attempt. */
const NEGOTIATION_TIMEOUT_MS = 5_000;

/**
 * Retry budget for the attach handshake. A failed POST during resource
 * startup is not the same answer as "no hub adapter": the Lua bridge answers
 * `available: false` explicitly when no adapter is registered, and that
 * answer is taken at face value.
 */
const ATTACH_RETRIES = 8;
const ATTACH_RETRY_MS = 250;

/** Relay retries before giving up on a hub that is running but not serving. */
const RELAY_RETRIES = 2;
const RELAY_RETRY_MS = 1_000;

type SessionHandlers = {
  onSignal: (payload: AudioHubSignalPayload) => void;
  onState: (state: AudioHubState) => void;
};

let nextId = 0;
const newId = () => `mic-${Date.now().toString(36)}-${(nextId += 1)}`;

const sessions = new Map<string, SessionHandlers>();
let listenerAttached = false;

function attachListener(): void {
  if (listenerAttached) return;
  listenerAttached = true;
  window.addEventListener("message", (event: MessageEvent<unknown>) => {
    const message = parseAudioHubMessage(event.data);
    if (!message) return;
    const handlers = sessions.get(message.id);
    if (!handlers) return;
    if (message.kind === "signal") handlers.onSignal(message.payload);
    else handlers.onState(message.state);
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => {
    window.setTimeout(resolve, ms);
  });
}

async function nuiPost<T>(name: string, body: unknown): Promise<T> {
  if (typeof GetParentResourceName !== "function") {
    throw new Error("NUI unavailable");
  }
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 2_000);
  try {
    const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`NUI callback ${name} failed with HTTP ${response.status}`);
    }
    return await response.json() as T;
  } finally {
    window.clearTimeout(timeout);
  }
}

function sendSignal(id: string, payload: AudioHubSignalPayload): void {
  void nuiPost("audiohubSignal", { id, payload }).catch(() => undefined);
}

async function attachSession(id: string): Promise<boolean> {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return attachAvailable(
        await nuiPost<unknown>("audiohubAttach", { id, track: true, level: false }),
      );
    } catch (error) {
      if (attempt >= ATTACH_RETRIES) {
        console.debug("[humalike:audiohub] bridge never answered attach", error);
        return false;
      }
      await delay(ATTACH_RETRY_MS);
    }
  }
}

function detachSession(id: string): void {
  sessions.delete(id);
  void nuiPost("audiohubDetach", { id }).catch(() => undefined);
}

/**
 * Keep a relayed stream flowing into Web Audio.
 *
 * Chromium does not render a remote WebRTC track into a Web Audio graph unless
 * the stream is also attached to a media element — `createMediaStreamSource`
 * on it yields digital silence otherwise. The voice pipeline feeds the
 * microphone through Web Audio, so without this the shared track would arrive
 * and carry nothing. The element is muted and hidden; it exists only to make
 * the track be pulled.
 */
function attachSink(stream: MediaStream): () => void {
  const sink = document.createElement("audio");
  sink.srcObject = stream;
  sink.muted = true;
  sink.autoplay = true;
  sink.hidden = true;
  document.body.appendChild(sink);
  void sink.play().catch(() => undefined);
  return () => {
    sink.pause();
    sink.srcObject = null;
    sink.remove();
  };
}

async function openLocal(deviceId: string): Promise<MicrophoneSourceHandle> {
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      deviceId: deviceId ? { exact: deviceId } : undefined,
      echoCancellation: false, noiseSuppression: false, autoGainControl: false,
      channelCount: 1,
    },
    video: false,
  });
  const track = stream.getAudioTracks()[0];
  if (!track) {
    stream.getTracks().forEach((item) => item.stop());
    throw new Error("getUserMedia returned no audio track");
  }
  let released = false;
  return {
    stream,
    track,
    kind: "local",
    release: () => {
      if (released) return;
      released = true;
      stream.getTracks().forEach((item) => item.stop());
    },
  };
}

type HubNegotiation = {
  promise: Promise<MicrophoneSourceHandle>;
  abort: (reason: string) => void;
};

/**
 * Negotiate the loopback connection and resolve with the relayed track.
 *
 * The hub is always the offerer, so this side is purely reactive: wait for the
 * offer, answer it, resolve when the track arrives. After the track has been
 * delivered a dying hub is reported through `onLost` exactly once, so the
 * caller can rebuild the pipeline instead of transmitting silence.
 */
function openFromHub(
  id: string,
  timeoutMs: number,
  onLost?: () => void,
): HubNegotiation {
  let abort: (reason: string) => void = () => undefined;
  const promise = new Promise<MicrophoneSourceHandle>((resolve, reject) => {
    const pc = new RTCPeerConnection({ iceServers: [] });
    const pendingCandidates: RTCIceCandidateInit[] = [];
    let settled = false;
    let closed = false;
    let lostReported = false;

    const timer = window.setTimeout(
      () => fail("hub negotiation timed out"),
      timeoutMs,
    );

    function close(): void {
      if (closed) return;
      closed = true;
      try {
        pc.close();
      } catch {
        // Already closed.
      }
    }

    function fail(reason: string): void {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      sessions.delete(id);
      close();
      reject(new Error(reason));
    }

    function reportLost(): void {
      if (!settled || closed || lostReported) return;
      lostReported = true;
      onLost?.();
    }

    abort = fail;

    pc.addEventListener("icecandidate", (event) => {
      sendSignal(id, {
        type: "candidate",
        candidate: event.candidate ? event.candidate.toJSON() : null,
      });
    });

    pc.addEventListener("connectionstatechange", () => {
      if (pc.connectionState !== "failed") return;
      if (settled) reportLost();
      else fail("hub connection failed");
    });

    pc.addEventListener("track", (event) => {
      if (settled || event.track.kind !== "audio") return;
      settled = true;
      window.clearTimeout(timer);

      const stream = event.streams[0] ?? new MediaStream([event.track]);
      const detachSink = attachSink(stream);
      event.track.addEventListener("ended", reportLost);

      let released = false;
      resolve({
        stream,
        track: event.track,
        kind: "hub",
        release: () => {
          if (released) return;
          released = true;
          detachSink();
          detachSession(id);
          close();
        },
      });
    });

    sessions.set(id, {
      onSignal: (payload) => {
        void (async () => {
          try {
            if (payload.type === "offer") {
              await pc.setRemoteDescription({ type: "offer", sdp: payload.sdp });
              for (const candidate of pendingCandidates) {
                await pc.addIceCandidate(candidate).catch(() => undefined);
              }
              pendingCandidates.length = 0;
              const answer = await pc.createAnswer();
              await pc.setLocalDescription(answer);
              sendSignal(id, { type: "answer", sdp: answer.sdp ?? "" });
              return;
            }
            if (payload.type === "candidate") {
              if (!payload.candidate) return;
              // Candidates can beat the offer; hold them until there is a
              // remote description to attach them to.
              if (!pc.remoteDescription) {
                pendingCandidates.push(payload.candidate);
                return;
              }
              await pc.addIceCandidate(payload.candidate).catch(() => undefined);
              return;
            }
            if (payload.type === "bye") {
              if (settled) reportLost();
              else fail(payload.reason ?? "hub closed the session");
            }
          } catch (error) {
            fail(error instanceof Error ? error.message : String(error));
          }
        })();
      },
      onState: (state) => {
        const failure = stateFailure(state);
        if (!failure) return;
        if (settled) reportLost();
        else fail(failure);
      },
    });
  });

  return { promise, abort };
}

/**
 * Get a live microphone stream, preferring the shared hub capture.
 *
 * Drop-in replacement for opening the device with `getUserMedia`: use
 * `handle.stream` and call `handle.release()` when done instead of stopping
 * the tracks yourself. `deviceId` and the raw capture constraints apply only
 * to the local fallback — a hub owns its own capture and constraints.
 */
export async function acquireMicrophoneSource(options?: {
  deviceId?: string;
  timeoutMs?: number;
  /** A hub track that died after delivery. Release the handle and reacquire. */
  onLost?: () => void;
}): Promise<MicrophoneSourceHandle> {
  const deviceId = options?.deviceId ?? "";
  if (typeof GetParentResourceName !== "function") return openLocal(deviceId);

  attachListener();
  const id = newId();
  const timeout = options?.timeoutMs ?? NEGOTIATION_TIMEOUT_MS;

  for (let attempt = 0; ; attempt += 1) {
    // Register the signal handler before attaching: the hub may emit its
    // offer while the NUI callback is still answering.
    const negotiation = openFromHub(id, timeout, options?.onLost);
    const available = await attachSession(id);
    if (!available) {
      negotiation.abort("hub unavailable");
      await negotiation.promise.catch(() => undefined);
      detachSession(id);
      return openLocal(deviceId);
    }
    try {
      return await negotiation.promise;
    } catch (error) {
      if (attempt >= RELAY_RETRIES) {
        detachSession(id);
        throw new HubUnavailableError(
          error instanceof Error ? error.message : String(error),
        );
      }
      console.debug("[humalike:audiohub] relay attempt failed, retrying", error);
      await delay(RELAY_RETRY_MS);
    }
  }
}
