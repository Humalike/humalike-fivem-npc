import assert from "node:assert/strict";
import test from "node:test";
import {
  attachAvailable,
  parseAudioHubMessage,
  parseSignalPayload,
  stateFailure,
} from "../src/audiohub-messages.mjs";

test("signal messages carry a validated payload", () => {
  assert.deepEqual(
    parseAudioHubMessage({
      type: "audiohub:signal",
      id: "mic-1",
      payload: { type: "offer", sdp: "v=0" },
    }),
    { kind: "signal", id: "mic-1", payload: { type: "offer", sdp: "v=0" } },
  );
});

test("state messages require an id and a state object", () => {
  assert.deepEqual(
    parseAudioHubMessage({
      type: "audiohub:state",
      id: "mic-1",
      state: { capturing: true },
    }),
    { kind: "state", id: "mic-1", state: { capturing: true } },
  );
  assert.equal(
    parseAudioHubMessage({ type: "audiohub:state", state: {} }),
    null,
  );
  assert.equal(
    parseAudioHubMessage({ type: "audiohub:state", id: "mic-1" }),
    null,
  );
});

test("unrelated NUI messages are ignored", () => {
  assert.equal(parseAudioHubMessage({ type: "voice:ptt", id: "x" }), null);
  assert.equal(parseAudioHubMessage(null), null);
  assert.equal(parseAudioHubMessage("audiohub:signal"), null);
});

test("malformed signal payloads are rejected", () => {
  assert.equal(parseSignalPayload({ type: "offer" }), null);
  assert.equal(parseSignalPayload({ type: "offer", sdp: "" }), null);
  assert.equal(parseSignalPayload({ type: "candidate", candidate: 5 }), null);
  assert.equal(parseSignalPayload({ type: "unknown" }), null);
  assert.equal(parseSignalPayload(undefined), null);
});

test("end-of-candidates is preserved as an explicit null", () => {
  assert.deepEqual(parseSignalPayload({ type: "candidate", candidate: null }), {
    type: "candidate",
    candidate: null,
  });
  assert.deepEqual(parseSignalPayload({ type: "candidate" }), {
    type: "candidate",
    candidate: null,
  });
});

test("bye keeps an optional reason", () => {
  assert.deepEqual(parseSignalPayload({ type: "bye", reason: "stopping" }), {
    type: "bye",
    reason: "stopping",
  });
  assert.deepEqual(parseSignalPayload({ type: "bye", reason: 7 }), {
    type: "bye",
    reason: undefined,
  });
});

test("attach is only available on an explicit true", () => {
  assert.equal(attachAvailable({ ok: true, available: true }), true);
  assert.equal(attachAvailable({ ok: true, available: false }), false);
  assert.equal(attachAvailable({ ok: true }), false);
  assert.equal(attachAvailable("ok"), false);
  assert.equal(attachAvailable(undefined), false);
});

test("a pending capture keeps the negotiation waiting", () => {
  assert.equal(stateFailure({ pending: true, capturing: false, error: "x" }),
    null);
});

test("a failed capture aborts before the negotiation timeout", () => {
  assert.equal(
    stateFailure({ capturing: false, error: "NotAllowedError" }),
    "hub capture unavailable: NotAllowedError",
  );
});

test("a healthy or quiet hub is not a failure", () => {
  assert.equal(stateFailure({ capturing: true, error: null }), null);
  assert.equal(stateFailure({ capturing: false, error: null }), null);
  assert.equal(stateFailure({ capturing: false, error: "" }), null);
  assert.equal(stateFailure(undefined), null);
});
