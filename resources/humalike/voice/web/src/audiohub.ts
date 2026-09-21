import { createAudioHubClient, HubUnavailableError } from "./audiohub-session.mjs";

declare const GetParentResourceName: undefined | (() => string);

export { HubUnavailableError };

export type MicrophoneSourceKind = "hub" | "local";

export interface MicrophoneSourceHandle {
  stream: MediaStream;
  track: MediaStreamTrack;
  kind: MicrophoneSourceKind;
  /** Detaches from the hub or stops the local capture; idempotent. */
  release: () => void;
}

export interface AudioHub {
  acquire(options: { deviceId: string; onLost: () => void }): Promise<MicrophoneSourceHandle>;
}

// Chromium renders a remote WebRTC track into Web Audio only while a media
// element also pulls it; the muted, hidden sink exists for that alone.
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

/**
 * Microphone source preferring a registered audio hub. With a hub registered
 * the device is never opened here; only a `none` answer from Lua opens it.
 */
export function createAudioHub(
  post: (name: string, body: unknown) => Promise<unknown>,
  onAvailable: () => void,
): AudioHub {
  const client = createAudioHubClient({
    post,
    createPeerConnection: () => new RTCPeerConnection({ iceServers: [] }),
    attachSink,
    setTimeout: (callback, ms) => window.setTimeout(callback, ms),
    clearTimeout: (timer) => window.clearTimeout(timer),
    onAvailable,
    log: (message) => console.debug(`[humalike:audiohub] ${message}`),
  });
  window.addEventListener("message", (event: MessageEvent<unknown>) => client.handleMessage(event.data));
  return {
    async acquire({ deviceId, onLost }) {
      if (typeof GetParentResourceName !== "function") return openLocal(deviceId);
      return (await client.acquire({ onLost })) ?? openLocal(deviceId);
    },
  };
}
