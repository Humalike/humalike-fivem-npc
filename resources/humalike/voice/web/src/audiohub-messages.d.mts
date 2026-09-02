export type AudioHubSignalPayload =
  | { type: "offer"; sdp: string }
  | { type: "answer"; sdp: string }
  | { type: "candidate"; candidate: RTCIceCandidateInit | null }
  | { type: "bye"; reason?: string };

export interface AudioHubState {
  capturing?: boolean;
  error?: string | null;
  consumers?: number;
  pending?: boolean;
}

export type AudioHubMessage =
  | { kind: "signal"; id: string; payload: AudioHubSignalPayload }
  | { kind: "state"; id: string; state: AudioHubState };

export function parseSignalPayload(
  payload: unknown,
): AudioHubSignalPayload | null;
export function parseAudioHubMessage(data: unknown): AudioHubMessage | null;
export function attachAvailable(response: unknown): boolean;
export function stateFailure(state: unknown): string | null;
