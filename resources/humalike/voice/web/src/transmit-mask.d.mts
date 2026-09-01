export const TRANSMIT_PROXIMITY: 1;
export const TRANSMIT_CALL: 4;
export const TRANSMIT_SCRIPTED: 8;
export const TRANSMIT_CABIN: 16;
export function negotiatedTransmitMask(
  active: boolean,
  cabinAuthorized: boolean,
  cabinCapability: boolean,
): number;
export function effectivePtt(nativeActive: boolean, testActive: boolean): boolean;
