export type AudioHubSignalPayload =
  | { type: "offer"; sdp: string }
  | { type: "answer"; sdp: string }
  | { type: "candidate"; candidate: RTCIceCandidateInit | null }
  | { type: "bye"; reason?: string };

export interface AudioHubState {
  pending?: boolean;
  capturing?: boolean;
  error?: string | null;
}

export type AudioHubMessage =
  | { kind: "signal"; id: string; payload: AudioHubSignalPayload }
  | { kind: "state"; id: string; state: AudioHubState }
  | { kind: "available" };

export type AttachStatus = "none" | "unavailable" | "attached";

export interface AttachResult {
  ok: boolean;
  status: AttachStatus;
  reason?: string;
}

export function parseSignalPayload(
  payload: unknown,
): AudioHubSignalPayload | null;
export function parseAudioHubMessage(data: unknown): AudioHubMessage | null;
export function attachStatus(response: unknown): AttachResult;
export function stateFailure(state: unknown): string | null;
