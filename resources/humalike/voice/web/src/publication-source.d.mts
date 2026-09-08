export function readyServerId(
  serverId: string,
  room: string,
): string | null;
export function publicationSourceId(
  participantIdentity: string,
  trackName: string | undefined,
  trackSource: string | undefined,
  expectedServerId: string,
): string | null;
