export const NEGOTIATION_TIMEOUT_MS: number;
export const NEGOTIATION_BUDGET_MS: number;
export const HUB_WAIT_MS: number;
export const HUB_WAIT_MIN_MS: number;
export const HUB_WAIT_MAX_MS: number;
export const RELAY_RETRIES: number;
export const RELAY_RETRY_MS: number;
export const BRIDGE_RETRIES: number;
export const BRIDGE_RETRY_MS: number;
export const DISCONNECT_GRACE_MS: number;

export class HubUnavailableError extends Error {
  constructor(message: string);
}

export interface HubSourceHandle {
  stream: MediaStream;
  track: MediaStreamTrack;
  kind: "hub";
  /** Detaches from the hub; idempotent. */
  release: () => void;
}

export interface AudioHubClientDeps {
  /** NUI callback POST; resolves with the parsed JSON answer. */
  post: (name: string, body: unknown) => Promise<unknown>;
  createPeerConnection: () => RTCPeerConnection;
  /** Keeps a relayed stream pulled; returns the detach function. */
  attachSink?: (stream: MediaStream) => () => void;
  createStream?: (track: MediaStreamTrack) => MediaStream;
  setTimeout: (callback: () => void, ms: number) => number;
  clearTimeout: (timer: number) => void;
  now?: () => number;
  /** Lua reported a hub (back) as available. */
  onAvailable?: () => void;
  log?: (message: string) => void;
}

export interface AudioHubClient {
  /** Resolves with a hub handle, or null when no hub adapter is registered. */
  acquire(options?: { onLost?: () => void }): Promise<HubSourceHandle | null>;
  handleMessage(data: unknown): void;
}

export function createAudioHubClient(deps: AudioHubClientDeps): AudioHubClient;
