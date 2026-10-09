import assert from "node:assert/strict";
import test from "node:test";
import { aimLabel, isLabelTuple, labelLayout, normalizeLanguage, presentationScale, settleDelayMs } from "../src/model.mjs";

test("normalizes configured and unknown locale families without badge variants", () => {
  assert.equal(normalizeLanguage("en-GB"), "en");
  assert.equal(normalizeLanguage("pl_PL"), "pl");
  assert.equal(normalizeLanguage("it-IT"), "IT");
  assert.equal(normalizeLanguage(""), null);
});

test("keeps badge size nearly fixed across resolutions", () => {
  assert.equal(presentationScale(720, 1), 0.9);
  assert.equal(presentationScale(1080, 1), 1);
  assert.equal(presentationScale(2160, 1), 1.1);
});

test("accepts only compact normalized label tuples", () => {
  assert.equal(isLabelTuple([0.5, 0.4, "en", 1]), true);
  assert.equal(isLabelTuple([0.5, 0.4, "en", 1, "npc-1"]), true);
  assert.equal(isLabelTuple([0.5, 0.4, "en", 1, 7]), false);
  assert.equal(isLabelTuple([1.2, 0.4, "en", 0]), false);
  assert.equal(isLabelTuple({ x: 0.5 }), false);
});

test("keeps a scaled gap between a language flag and mute icon", () => {
  const layout = labelLayout(true, true, 1);
  assert.equal(layout.muteOffset - (layout.flagOffset + layout.flagWidth), 7);
  assert.ok(layout.muteOffset + 14 <= layout.labelWidth - layout.labelPadding);
});

test("a moving label is aimed one glide ahead and comes back to the head when it stops", () => {
  const node = { x: 0, y: 0, at: 0 };
  assert.deepEqual(aimLabel(node, 100, 200, 1000, 50, 3000), [100, 200, false],
    "the first position is drawn where it was reported");
  const [x, y, ahead] = aimLabel(node, 110, 200, 1050, 50, 3000);
  assert.equal(ahead, true);
  assert.equal(x, 120, "ten pixels in fifty milliseconds: aimed ten pixels further");
  assert.equal(y, 200);
  assert.deepEqual([node.x, node.y], [110, 200]);
  assert.equal(settleDelayMs(50), 75, "after one and a half glides without a frame");
  assert.deepEqual(aimLabel(node, 110, 200, 2050, 50, 3000), [110, 200, false]);
});

test("the aim is capped and stale positions are not extrapolated", () => {
  const node = { x: 0, y: 0, at: 0 };
  aimLabel(node, 0, 0, 1000, 50, 3000);
  const [x, y] = aimLabel(node, 300, 400, 1050, 50, 3000);
  assert.ok(Math.abs(Math.hypot(x - 300, y - 400) - 40) < 1e-9, "at most forty pixels ahead");
  assert.deepEqual(aimLabel(node, 500, 400, 1050 + 3000, 50, 3000), [500, 400, false],
    "a label not heard of for three seconds starts afresh");
});
