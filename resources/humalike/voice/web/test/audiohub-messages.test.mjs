import assert from "node:assert/strict";
import test from "node:test";
import {
  attachStatus,
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

test("hub-available carries no id", () => {
  assert.deepEqual(parseAudioHubMessage({ type: "audiohub:available" }), { kind: "available" });
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

test("attach answers are normalised to a three-way status", () => {
  assert.deepEqual(attachStatus({ ok: true, status: "attached" }),
    { ok: true, status: "attached", reason: undefined });
  assert.deepEqual(attachStatus({ ok: true, status: "unavailable", reason: "ambiguous" }),
    { ok: true, status: "unavailable", reason: "ambiguous" });
  assert.deepEqual(attachStatus({ ok: true, status: "none" }),
    { ok: true, status: "none", reason: undefined });
  assert.deepEqual(attachStatus({ ok: false, reason: "already_attached" }),
    { ok: false, status: "unavailable", reason: "already_attached" });
  assert.equal(attachStatus({ ok: true, status: "available" }).ok, false);
  assert.equal(attachStatus({ ok: true }).ok, false);
  assert.equal(attachStatus("ok").ok, false);
  assert.equal(attachStatus(undefined).ok, false);
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
