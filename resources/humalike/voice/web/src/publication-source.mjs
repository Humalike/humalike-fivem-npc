const VALID_SERVER_ID = /^[A-Za-z0-9._-]{1,64}$/;

export function readyServerId(serverId, room) {
  const explicit = typeof serverId === "string" && VALID_SERVER_ID.test(serverId)
    ? serverId : null;
  if (serverId !== undefined && explicit === null) return null;
  if (typeof room !== "string" || !room.startsWith("fivem:")) return null;
  const legacy = room.slice(6);
  if (!VALID_SERVER_ID.test(legacy)) return null;
  if (explicit !== null && explicit !== legacy) return null;
  return explicit ?? legacy;
}

export function publicationSourceId(participantIdentity, trackName, trackSource, expectedServerId) {
  if (trackSource !== "microphone") return null;
  const name = typeof trackName === "string" ? trackName.trim() : "";
  if (name.startsWith("npc:")) {
    if (!expectedServerId
      || !participantIdentity.startsWith(`edge-publisher:${expectedServerId}:`)) return null;
    return name.length > 4 ? name : null;
  }
  if (participantIdentity.startsWith("edge-publisher:")) return null;
  return participantIdentity;
}
