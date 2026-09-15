import assert from "node:assert/strict";
import test from "node:test";
import { publicationSourceId, readyServerId } from "../src/publication-source.mjs";

test("accepts NPC microphone only from the expected server edge publisher", () => {
  assert.equal(publicationSourceId("edge-publisher:server-1:boot", "npc:npc-1", "microphone", "server-1"), "npc:npc-1");
  assert.equal(publicationSourceId("edge-publisher:other:boot", "npc:npc-1", "microphone", "server-1"), null);
  assert.equal(publicationSourceId("player:7:session", "npc:npc-1", "microphone", "server-1"), null);
});

test("rejects non-microphone and non-NPC edge publications", () => {
  assert.equal(publicationSourceId("edge-publisher:server-1:boot", "npc:npc-1", "unknown", "server-1"), null);
  assert.equal(publicationSourceId("edge-publisher:server-1:boot", "extra", "microphone", "server-1"), null);
});

test("rejects player microphone publications", () => {
  assert.equal(publicationSourceId("player:7:session", "arbitrary", "microphone", "server-1"), null);
});

test("Ready server ID must be present, valid, and consistent with room", () => {
  assert.equal(readyServerId("server-1", "fivem:server-1"), "server-1");
  assert.equal(readyServerId("server-1", "fivem:server-1:boot-1:3:abcd"), "server-1");
  assert.equal(readyServerId("server-1", "fivem:server-10"), null);
  assert.equal(readyServerId(undefined, "fivem:server-1"), null);
  assert.equal(readyServerId("server-2", "fivem:server-1"), null);
  assert.equal(readyServerId("bad:server", "fivem:bad-server"), null);
});
