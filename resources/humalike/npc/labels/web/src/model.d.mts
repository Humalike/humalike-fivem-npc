export function normalizeLanguage(value: unknown): string | null;
export function presentationScale(viewportHeight: number, configuredScale: number): number;
export function labelLayout(hasLanguage: boolean, muted: boolean, scale: number): {
  iconSize: number;
  gap: number;
  flagWidth: number;
  flagGap: number;
  textWidth: number;
  muteGap: number;
  muteWidth: number;
  labelPadding: number;
  flagOffset: number;
  muteOffset: number;
  labelWidth: number;
  totalWidth: number;
};
export function isLabelTuple(value: unknown): boolean;
export function aimLabel(node: { x: number; y: number; at: number }, x: number, y: number,
  now: number, transitionMs: number, staleMs: number): [number, number, boolean];
export function settleDelayMs(transitionMs: number): number;
