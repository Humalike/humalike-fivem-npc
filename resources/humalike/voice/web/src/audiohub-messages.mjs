// Message parsing for the shared-microphone (audio hub) client. Pure so it
// runs under node:test.

export function parseSignalPayload(payload) {
  if (!payload || typeof payload !== "object") return null;
  if (payload.type === "offer" || payload.type === "answer") {
    if (typeof payload.sdp !== "string" || payload.sdp === "") return null;
    return { type: payload.type, sdp: payload.sdp };
  }
  if (payload.type === "candidate") {
    if (payload.candidate === null || payload.candidate === undefined) {
      return { type: "candidate", candidate: null };
    }
    if (typeof payload.candidate !== "object") return null;
    return { type: "candidate", candidate: payload.candidate };
  }
  if (payload.type === "bye") {
    return {
      type: "bye",
      reason: typeof payload.reason === "string" ? payload.reason : undefined,
    };
  }
  return null;
}

export function parseAudioHubMessage(data) {
  if (!data || typeof data !== "object") return null;
  if (data.type === "audiohub:available") return { kind: "available" };
  if (typeof data.id !== "string" || data.id === "") return null;
  if (data.type === "audiohub:signal") {
    const payload = parseSignalPayload(data.payload);
    return payload ? { kind: "signal", id: data.id, payload } : null;
  }
  if (data.type === "audiohub:state") {
    if (!data.state || typeof data.state !== "object") return null;
    return { kind: "state", id: data.id, state: data.state };
  }
  return null;
}

const ATTACH_STATUSES = new Set(["none", "unavailable", "attached"]);

export function attachStatus(response) {
  if (!response || typeof response !== "object") {
    return { ok: false, status: "unavailable", reason: "no answer" };
  }
  const reason = typeof response.reason === "string" ? response.reason : undefined;
  if (response.ok !== true) return { ok: false, status: "unavailable", reason: reason ?? "refused" };
  if (!ATTACH_STATUSES.has(response.status)) {
    return { ok: false, status: "unavailable", reason: "malformed status" };
  }
  return { ok: true, status: response.status, reason };
}

// `pending` is not a failure: the hub is still working on its capture (most
// likely a permission prompt). Only an error without capture ends the session.
export function stateFailure(state) {
  if (!state || typeof state !== "object") return null;
  if (state.pending === true) return null;
  if (state.capturing !== true && typeof state.error === "string"
    && state.error !== "") {
    return `hub capture unavailable: ${state.error}`;
  }
  return null;
}
