import assert from "node:assert/strict";
import test from "node:test";
import { isLabelTuple, labelLayout, normalizeLanguage, presentationScale } from "../src/model.mjs";

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
