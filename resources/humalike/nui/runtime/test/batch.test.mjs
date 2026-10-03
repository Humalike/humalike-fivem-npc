import assert from "node:assert/strict";
import test from "node:test";
import { batchParts, installBatchDispatcher } from "../src/batch.mjs";

test("a batch yields its parts in order", () => {
  const listener = { type: "game:listener" };
  const frame = { type: "labels:frame", labels: [] };
  assert.deepEqual(batchParts({ type: "batch", messages: [listener, frame] }), [listener, frame]);
  assert.deepEqual(batchParts({ type: "batch", messages: [] }), []);
});

test("anything else is not a batch", () => {
  assert.equal(batchParts({ type: "labels:frame", labels: [] }), null);
  assert.equal(batchParts({ type: "batch" }), null);
  assert.equal(batchParts({ type: "batch", messages: "x" }), null);
  assert.equal(batchParts(null), null);
  assert.equal(batchParts("batch"), null);
});

test("every listener hears each part as a message of its own, in order", () => {
  const target = new EventTarget();
  const early = [];
  const late = [];
  target.addEventListener("message", (event) => early.push(event.data.type));
  installBatchDispatcher(target);
  target.addEventListener("message", (event) => late.push(event.data.type));

  target.dispatchEvent(new MessageEvent("message", { data: { type: "voice:ptt", active: true } }));
  target.dispatchEvent(new MessageEvent("message", { data: {
    type: "batch",
    messages: [{ type: "game:listener" }, { type: "game:realtime" }, { type: "labels:frame", labels: [] }],
  } }));

  assert.deepEqual(early, ["voice:ptt", "batch", "game:listener", "game:realtime", "labels:frame"]);
  assert.deepEqual(late, ["voice:ptt", "game:listener", "game:realtime", "labels:frame", "batch"]);
});
