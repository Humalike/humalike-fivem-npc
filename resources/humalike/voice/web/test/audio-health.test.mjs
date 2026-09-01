import assert from "node:assert/strict";
import test from "node:test";
import { hasAudibleSamples } from "../src/audio-health.mjs";

test("rejects silence and sub-threshold noise", () => {
  assert.equal(hasAudibleSamples(new Float32Array(128)), false);
  assert.equal(hasAudibleSamples(Float32Array.from({ length: 128 }, () => 0.001)), false);
});

test("accepts decoded audio above the RMS threshold", () => {
  const samples = Float32Array.from({ length: 128 }, (_, index) => index % 2 ? 0.01 : -0.01);
  assert.equal(hasAudibleSamples(samples), true);
});
