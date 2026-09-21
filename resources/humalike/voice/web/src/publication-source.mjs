const VALID_SERVER_ID = /^[A-Za-z0-9._-]{1,64}$/;

export function readyServerId(serverId, room) {
  if (typeof serverId !== "string" || !VALID_SERVER_ID.test(serverId)) return null;
  if (typeof room !== "string") return null;
  const prefix = `fivem:${serverId}`;
  if (room !== prefix && !room.startsWith(`${prefix}:`)) return null;
  return serverId;
}

export function publicationSourceId(participantIdentity, trackName, trackSource, expectedServerId) {
  if (trackSource !== "microphone") return null;
  const name = typeof trackName === "string" ? trackName.trim() : "";
  if (name.startsWith("npc:")) {
    if (!expectedServerId
      || !participantIdentity.startsWith(`edge-publisher:${expectedServerId}:`)) return null;
    return name.length > 4 ? name : null;
  }
  return null;
}
