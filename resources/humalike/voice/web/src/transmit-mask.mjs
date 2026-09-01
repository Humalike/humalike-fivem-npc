export const TRANSMIT_PROXIMITY = 1;
export const TRANSMIT_CALL = 1 << 2;
export const TRANSMIT_SCRIPTED = 1 << 3;
export const TRANSMIT_CABIN = 1 << 4;

export function negotiatedTransmitMask(active, cabinAuthorized, cabinCapability) {
  if (!active) return 0;
  return TRANSMIT_PROXIMITY
    | (cabinAuthorized && cabinCapability ? TRANSMIT_CABIN : 0);
}

export function effectivePtt(nativeActive, testActive) {
  return nativeActive || testActive;
}
