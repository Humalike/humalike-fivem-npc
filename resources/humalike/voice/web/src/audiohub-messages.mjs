// Message parsing and state decisions for the shared-microphone (audio hub)
// client. Pure so they can be unit tested without a DOM or peer connection.

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

export function attachAvailable(response) {
  return !!response && typeof response === "object"
    && response.available === true;
}

// A pending capture (most likely an unanswered permission prompt) is not a
// failure: giving up mid-prompt would open a duplicate device request. Only a
// hub that reports it cannot capture at all means no offer is coming.
export function stateFailure(state) {
  if (!state || typeof state !== "object") return null;
  if (state.pending === true) return null;
  if (state.capturing !== true && typeof state.error === "string"
    && state.error !== "") {
    return `hub capture unavailable: ${state.error}`;
  }
  return null;
}
