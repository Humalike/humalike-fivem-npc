import assert from "node:assert/strict";
import test from "node:test";
import {
  createAudioHubClient,
  DISCONNECT_GRACE_MS,
  HUB_WAIT_MS,
  HubUnavailableError,
  NEGOTIATION_BUDGET_MS,
  NEGOTIATION_TIMEOUT_MS,
  RELAY_RETRIES,
  RELAY_RETRY_MS,
} from "../src/audiohub-session.mjs";

const flush = () => new Promise((resolve) => setImmediate(resolve));

function createClock() {
  let time = 0;
  let seq = 0;
  const timers = new Map();
  return {
    now: () => time,
    setTimeout: (callback, ms) => { seq += 1; timers.set(seq, { due: time + ms, callback }); return seq; },
    clearTimeout: (id) => { timers.delete(id); },
    async advance(ms) {
      const target = time + ms;
      for (;;) {
        const next = [...timers.entries()].filter(([, t]) => t.due <= target).sort((a, b) => a[1].due - b[1].due)[0];
        if (!next) break;
        time = next[1].due;
        timers.delete(next[0]);
        next[1].callback();
        await flush();
      }
      time = target;
      await flush();
    },
  };
}

class FakeTrack extends EventTarget {
  kind = "audio";
  end() { this.dispatchEvent(new Event("ended")); }
}

class FakePeerConnection extends EventTarget {
  connectionState = "new";
  remoteDescription = null;
  localDescription = null;
  candidates = [];
  closed = false;
  async setRemoteDescription(description) { this.remoteDescription = description; }
  async createAnswer() { return { type: "answer", sdp: "v=0 answer" }; }
  async setLocalDescription(description) { this.localDescription = description; }
  async addIceCandidate(candidate) { this.candidates.push(candidate); }
  close() { this.closed = true; }
  emitTrack() {
    const track = new FakeTrack();
    this.dispatchEvent(Object.assign(new Event("track"), { track, streams: [{ id: "stream", track }] }));
    return track;
  }
  emitCandidate(candidate) {
    this.dispatchEvent(Object.assign(new Event("icecandidate"), { candidate: candidate ? { toJSON: () => candidate } : null }));
  }
  setState(state) { this.connectionState = state; this.dispatchEvent(new Event("connectionstatechange")); }
}

function harness(answers = {}) {
  const clock = createClock();
  const calls = [];
  const pcs = [];
  const sinks = [];
  let available = 0;
  const post = async (name, body) => {
    calls.push({ name, body });
    const answer = answers[name];
    if (typeof answer === "function") return answer(body, calls);
    return answer ?? { ok: true };
  };
  const client = createAudioHubClient({
    post,
    createPeerConnection: () => { const pc = new FakePeerConnection(); pcs.push(pc); return pc; },
    attachSink: () => { sinks.push("attached"); return () => sinks.push("detached"); },
    createStream: (track) => ({ track }),
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    now: clock.now,
    onAvailable: () => { available += 1; },
  });
  const ids = () => calls.filter((c) => c.name === "audiohubAttach").map((c) => c.body.id);
  const signals = (type) => calls.filter((c) => c.name === "audiohubSignal" && c.body.payload.type === type);
  const detaches = () => calls.filter((c) => c.name === "audiohubDetach").map((c) => c.body.id);
  const deliver = (id, payload) => client.handleMessage({ type: "audiohub:signal", id, payload });
  const state = (id, value) => client.handleMessage({ type: "audiohub:state", id, state: value });
  return { clock, client, calls, pcs, sinks, ids, signals, detaches, deliver, state, available: () => available };
}

const attached = { audiohubAttach: { ok: true, status: "attached" } };

// Tracks a promise without awaiting it; `pending` flips once it settles.
async function settle(promise) {
  const result = { pending: true };
  promise.then((value) => { result.pending = false; result.value = value; },
    (error) => { result.pending = false; result.error = error; });
  await flush();
  return result;
}

test("offer -> answer -> track resolves with a hub handle; the peer connection exists only after attach", async () => {
  let answerAttach;
  const h = harness({ audiohubAttach: () => new Promise((resolve) => { answerAttach = resolve; }) });
  const promise = h.client.acquire();
  await flush();
  assert.equal(h.pcs.length, 0);
  answerAttach({ ok: true, status: "attached" });
  await flush();
  assert.equal(h.pcs.length, 1);
  const [id] = h.ids();
  h.deliver(id, { type: "offer", sdp: "v=0 offer" });
  await flush();
  assert.equal(h.pcs[0].remoteDescription.sdp, "v=0 offer");
  assert.equal(h.signals("answer").length, 1);
  assert.equal(h.signals("answer")[0].body.id, id);
  const track = h.pcs[0].emitTrack();
  const handle = await promise;
  assert.equal(handle.kind, "hub");
  assert.equal(handle.track, track);
  assert.deepEqual(h.sinks, ["attached"]);
});

test("hub candidates before the offer are buffered; local candidates go out only after the answer was delivered", async () => {
  let deliverAnswer;
  const h = harness({
    ...attached,
    audiohubSignal: (body) => body.payload.type === "answer"
      ? new Promise((resolve) => { deliverAnswer = () => resolve({ ok: true }); })
      : { ok: true },
  });
  const promise = h.client.acquire();
  await flush();
  const [id] = h.ids();
  const pc = h.pcs[0];
  h.deliver(id, { type: "candidate", candidate: { candidate: "hub-1" } });
  h.deliver(id, { type: "candidate", candidate: null });
  await flush();
  assert.deepEqual(pc.candidates, []);
  pc.emitCandidate({ candidate: "local-1" });
  h.deliver(id, { type: "offer", sdp: "v=0" });
  await flush();
  assert.deepEqual(pc.candidates, [{ candidate: "hub-1" }]);
  pc.emitCandidate({ candidate: "local-2" });
  await flush();
  assert.equal(h.signals("candidate").length, 0, "candidate sent before the answer POST resolved");
  deliverAnswer();
  await flush();
  pc.emitCandidate(null);
  await flush();
  assert.deepEqual(h.signals("candidate").map((c) => c.body.payload.candidate),
    [{ candidate: "local-1" }, { candidate: "local-2" }, null]);
  h.deliver(id, { type: "candidate", candidate: { candidate: "hub-2" } });
  await flush();
  assert.deepEqual(pc.candidates, [{ candidate: "hub-1" }, { candidate: "hub-2" }]);
  pc.emitTrack();
  await promise;
});

test("a silent hub times out, each retry uses a fresh id and says goodbye to the old one, then errors", async () => {
  const h = harness(attached);
  const result = await settle(h.client.acquire());
  for (let attempt = 0; attempt <= RELAY_RETRIES; attempt += 1) {
    await h.clock.advance(NEGOTIATION_TIMEOUT_MS);
    assert.equal(h.signals("bye").length, attempt + 1);
    assert.equal(h.detaches().length, attempt + 1);
    if (attempt < RELAY_RETRIES) await h.clock.advance(RELAY_RETRY_MS);
  }
  const outcome = result;
  assert.ok(outcome.error instanceof HubUnavailableError, String(outcome.error));
  const ids = h.ids();
  assert.equal(ids.length, RELAY_RETRIES + 1);
  assert.equal(new Set(ids).size, ids.length, "a session id was reused");
  assert.deepEqual(h.detaches(), ids);
  assert.ok(h.pcs.every((pc) => pc.closed));
});

test("pending extends the negotiation deadline up to the budget", async () => {
  const h = harness(attached);
  const result = await settle(h.client.acquire());
  const [id] = h.ids();
  await h.clock.advance(NEGOTIATION_TIMEOUT_MS - 1000);
  h.state(id, { pending: true });
  await h.clock.advance(NEGOTIATION_TIMEOUT_MS - 1000);
  assert.equal(h.signals("bye").length, 0, "pending did not extend the deadline");
  let elapsed = 2 * (NEGOTIATION_TIMEOUT_MS - 1000);
  while (elapsed < NEGOTIATION_BUDGET_MS) {
    h.state(id, { pending: true });
    await h.clock.advance(1000);
    elapsed += 1000;
  }
  await h.clock.advance(1);
  assert.equal(h.signals("bye").length, 1, "budget did not cap pending");
  await h.clock.advance(HUB_WAIT_MS);
  assert.ok(result.error instanceof HubUnavailableError);
});

test("bye and a state error before the track fail the attempt and retry", async () => {
  const h = harness(attached);
  const promise = h.client.acquire();
  await flush();
  h.deliver(h.ids()[0], { type: "bye", reason: "hub restarting" });
  await flush();
  assert.equal(h.detaches().length, 1);
  await h.clock.advance(RELAY_RETRY_MS);
  h.state(h.ids()[1], { capturing: false, error: "device-busy" });
  await flush();
  assert.equal(h.detaches().length, 2);
  await h.clock.advance(RELAY_RETRY_MS);
  const id = h.ids()[2];
  h.state(id, { capturing: true });
  h.deliver(id, { type: "offer", sdp: "v=0" });
  await flush();
  h.pcs[2].emitTrack();
  assert.equal((await promise).kind, "hub");
});

test("a refused signal fails the attempt", async () => {
  const h = harness({ ...attached, audiohubSignal: { ok: false, reason: "signal_failed" } });
  const result = await settle(h.client.acquire());
  h.deliver(h.ids()[0], { type: "offer", sdp: "v=0" });
  await flush();
  assert.equal(h.detaches().length, 1);
  assert.equal(h.pcs[0].closed, true);
  await h.clock.advance(RELAY_RETRY_MS);
  assert.equal(h.ids().length, 2);
  assert.ok(result.pending);
});

async function delivered(h, onLost) {
  const promise = h.client.acquire({ onLost });
  await flush();
  const id = h.ids().at(-1);
  h.deliver(id, { type: "offer", sdp: "v=0" });
  await flush();
  const pc = h.pcs.at(-1);
  pc.setState("connected");
  const track = pc.emitTrack();
  return { handle: await promise, pc, track, id };
}

test("after delivery failed, disconnected, ended, bye and a state error report the loss exactly once", async () => {
  for (const kill of [
    (pc) => pc.setState("failed"),
    (pc, track) => track.end(),
    async (pc, track, h) => { pc.setState("disconnected"); await h.clock.advance(DISCONNECT_GRACE_MS); },
    (pc, track, h, id) => h.deliver(id, { type: "bye", reason: "hub restarting" }),
    (pc, track, h, id) => h.state(id, { capturing: false, error: "device-busy" }),
  ]) {
    const h = harness(attached);
    let lost = 0;
    const { pc, track, id } = await delivered(h, () => { lost += 1; });
    await kill(pc, track, h, id);
    await flush();
    assert.equal(lost, 1);
    pc.setState("failed");
    track.end();
    h.deliver(id, { type: "bye" });
    h.state(id, { capturing: false, error: "device-busy" });
    await h.clock.advance(DISCONNECT_GRACE_MS);
    assert.equal(lost, 1);
    assert.equal(h.ids().length, 1, "a lost delivered session was renegotiated");
  }
});

test("a disconnect that recovers within the grace period is not a loss", async () => {
  const h = harness(attached);
  let lost = 0;
  const { pc } = await delivered(h, () => { lost += 1; });
  pc.setState("disconnected");
  await h.clock.advance(DISCONNECT_GRACE_MS - 1);
  pc.setState("connected");
  await h.clock.advance(DISCONNECT_GRACE_MS);
  assert.equal(lost, 0);
});

test("release is idempotent: one bye, one detach, sink detached, no loss reported", async () => {
  const h = harness(attached);
  let lost = 0;
  const { handle, pc, track, id } = await delivered(h, () => { lost += 1; });
  handle.release();
  handle.release();
  await flush();
  assert.equal(h.signals("bye").length, 1);
  assert.deepEqual(h.detaches(), [id]);
  assert.deepEqual(h.sinks, ["attached", "detached"]);
  assert.equal(pc.closed, true);
  pc.setState("failed");
  track.end();
  await flush();
  assert.equal(lost, 0);
});

test("an unavailable hub is waited for with backoff, never replaced by a local capture", async () => {
  let answers = 0;
  const h = harness({ audiohubAttach: () => (answers += 1) <= 3
    ? { ok: true, status: "unavailable", reason: "unavailable" }
    : { ok: true, status: "attached" } });
  const promise = h.client.acquire();
  await flush();
  assert.equal(h.ids().length, 1);
  await h.clock.advance(500);
  assert.equal(h.ids().length, 2);
  await h.clock.advance(1000);
  assert.equal(h.ids().length, 3);
  await h.clock.advance(2000);
  assert.equal(h.ids().length, 4);
  assert.equal(h.pcs.length, 1, "peer connection allocated before the hub was attached");
  const id = h.ids()[3];
  h.deliver(id, { type: "offer", sdp: "v=0" });
  await flush();
  h.pcs[0].emitTrack();
  assert.equal((await promise).kind, "hub");
  assert.equal(h.detaches().length, 0);
});

test("hub-available wakes the wait early and is reported", async () => {
  let answers = 0;
  const h = harness({ audiohubAttach: () => (answers += 1) === 1
    ? { ok: true, status: "unavailable", reason: "unavailable" }
    : { ok: true, status: "attached" } });
  const promise = h.client.acquire();
  await flush();
  await h.clock.advance(100);
  h.client.handleMessage({ type: "audiohub:available" });
  await flush();
  assert.equal(h.ids().length, 2);
  assert.equal(h.available(), 1);
  h.deliver(h.ids()[1], { type: "offer", sdp: "v=0" });
  await flush();
  h.pcs[0].emitTrack();
  await promise;
});

test("a hub that stays unavailable errors after the wait budget", async () => {
  const h = harness({ audiohubAttach: { ok: true, status: "unavailable", reason: "ambiguous" } });
  const result = await settle(h.client.acquire());
  await h.clock.advance(HUB_WAIT_MS - 1);
  assert.ok(result.pending);
  await h.clock.advance(HUB_WAIT_MS);
  const outcome = result;
  assert.ok(outcome.error instanceof HubUnavailableError);
  assert.match(outcome.error.message, /ambiguous/);
  assert.equal(h.pcs.length, 0);
});

test("no hub registered resolves null so the caller opens the device", async () => {
  const h = harness({ audiohubAttach: { ok: true, status: "none" } });
  assert.equal(await h.client.acquire(), null);
  assert.equal(h.pcs.length, 0);
  assert.equal(h.detaches().length, 0);
});

test("no hub registered opens the local capture through openLocal", async () => {
  const h = harness({ audiohubAttach: { ok: true, status: "none" } });
  const local = { kind: "local", release: () => undefined };
  assert.equal(await h.client.acquire({ openLocal: async () => local }), local);
  assert.equal(h.ids().length, 1);
});

test("a hub registering while the local capture opens is swapped in once, the local capture released", async () => {
  let answers = 0;
  const h = harness({ audiohubAttach: () => (answers += 1) === 1
    ? { ok: true, status: "none" }
    : { ok: true, status: "attached" } });
  let resolveLocal;
  let released = 0;
  const local = { kind: "local", release: () => { released += 1; } };
  const promise = h.client.acquire({ openLocal: () => new Promise((resolve) => { resolveLocal = resolve; }) });
  await flush();
  assert.equal(h.ids().length, 1);
  h.client.handleMessage({ type: "audiohub:available" });
  await flush();
  assert.equal(h.ids().length, 1, "re-attached before the local capture settled");
  assert.equal(h.available(), 1);
  resolveLocal(local);
  await flush();
  assert.equal(released, 1);
  assert.equal(h.ids().length, 2);
  assert.equal(h.pcs.length, 1);
  h.deliver(h.ids()[1], { type: "offer", sdp: "v=0" });
  await flush();
  h.pcs[0].emitTrack();
  assert.equal((await promise).kind, "hub");
  assert.equal(h.detaches().length, 0);
});

test("an available before the attempt started does not swap out the local capture", async () => {
  const h = harness({ audiohubAttach: { ok: true, status: "none" } });
  h.client.handleMessage({ type: "audiohub:available" });
  const local = { kind: "local", release: () => assert.fail("released") };
  assert.equal(await h.client.acquire({ openLocal: async () => local }), local);
  assert.equal(h.ids().length, 1);
});

test("a bridge that never answers is an error, not a local capture", async () => {
  const h = harness({ audiohubAttach: () => { throw new Error("HTTP 500"); } });
  const result = await settle(h.client.acquire());
  await h.clock.advance(60_000);
  const outcome = result;
  assert.match(String(outcome.error), /bridge did not answer/);
});
