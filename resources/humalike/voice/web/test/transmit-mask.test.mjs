import assert from "node:assert/strict";
import test from "node:test";
import { effectivePtt, negotiatedTransmitMask } from "../src/transmit-mask.mjs";

test("old routers remain proximity-only", () => {
  assert.equal(negotiatedTransmitMask(true, true, false), 1);
});

test("negotiated authoritative cabins add the cabin bit", () => {
  assert.equal(negotiatedTransmitMask(true, true, true), 17);
});

test("no membership or released PTT never adds the cabin bit", () => {
  assert.equal(negotiatedTransmitMask(true, false, true), 1);
  assert.equal(negotiatedTransmitMask(false, true, true), 0);
});

test("held native PTT survives reconnect cleanup of panel state", () => {
  assert.equal(effectivePtt(true, false), true);
});
