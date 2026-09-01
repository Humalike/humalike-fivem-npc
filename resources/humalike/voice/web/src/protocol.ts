export const PROTOCOL_VERSION = 1 as const;
export { TRANSMIT_CABIN, TRANSMIT_CALL, TRANSMIT_PROXIMITY, TRANSMIT_SCRIPTED } from "./transmit-mask.mjs";
export const CAPABILITY_AUTHORITATIVE_VEHICLE_CABINS = "authoritative_vehicle_cabins_v1";
export const CAPABILITY_DIRECT_NPC_TARGETS = "direct_npc_targets_v1";

export interface Vec3 { x: number; y: number; z: number }
export interface VehicleState { networkId: number; seat: number }
export interface GameRealtimeState {
  clientTimeMs: number;
  position: Vec3;
  velocity: Vec3;
  heading: number;
  vehicle: VehicleState | null;
  voiceMode: number;
  effectiveVoiceDistance: number;
  flags: { paused: boolean };
}
export interface RealtimeState extends GameRealtimeState {
  v: typeof PROTOCOL_VERSION;
  type: "realtime_state";
  seq: number;
  transmitMask: number;
  transmitGeneration: number;
  targetNpcIds?: string[];
}
export interface Route {
  sourceId: string;
  sourceKind?: "player" | "lab" | "npc";
  sourcePlayerId?: string;
  kind: "proximity" | "vehicle_cabin" | "radio" | "call" | "global" | "megaphone" | "system" | "debug_direct";
  spatial: boolean;
  distance?: number;
  position?: Vec3;
  velocity?: Vec3;
  voiceMode?: number;
  voiceDistance?: number;
  transmitMask: number;
}
export type ServerMessage =
  | { v: 1; type: "ready"; identity: string; room: string; livekitUrl: string; livekitToken?: string; transmitLeaseMs: number; capabilities?: string[]; serverId?: string }
  | { v: 1; type: "route_snapshot"; routes: Route[] }
  | { v: 1; type: "error"; code: string; message: string };

export function isServerMessage(value: unknown): value is ServerMessage {
  if (!value || typeof value !== "object") return false;
  const candidate = value as { v?: unknown; type?: unknown };
  return candidate.v === 1 && ["ready", "route_snapshot", "error"].includes(String(candidate.type));
}
