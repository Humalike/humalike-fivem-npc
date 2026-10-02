import { TRANSMIT_SCRIPTED, type Route, type Vec3 } from "./protocol";
import { t } from "./locale.mjs";

interface RemoteSource {
  source: MediaStreamAudioSourceNode;
  audible: GainNode;
  distance: GainNode;
  panner: PannerNode | null;
  position: Vec3;
  target: Vec3;
  velocity: Vec3;
  receivedAt: number;
  route: Route;
  transmitting: boolean;
  releaseTimer: number;
}

const SPATIAL_UPDATE_MS = 33;

export interface MicrophonePipeline {
  track: MediaStreamTrack;
  stream: MediaStream;
  gain: GainNode;
  close(): void;
}

export class AudioEngine {
  readonly context = new AudioContext({ latencyHint: "interactive" });
  readonly master = new GainNode(this.context, { gain: 1 });
  readonly npc = new GainNode(this.context, { gain: 1 });
  #listener: Vec3 = { x: 0, y: 0, z: 0 };
  #remotes = new Map<string, RemoteSource>();
  #activeRemotes = new Set<string>();
  #renderTimer = 0;
  readonly #onNPCSpeaking: (id: string, active: boolean) => void;
  readonly #onSpatialDemand: (active: boolean) => void;

  constructor(
    onNPCSpeaking: (id: string, active: boolean) => void = () => undefined,
    onSpatialDemand: (active: boolean) => void = () => undefined,
  ) {
    this.#onNPCSpeaking = onNPCSpeaking;
    this.#onSpatialDemand = onSpatialDemand;
    this.npc.connect(this.master); this.master.connect(this.context.destination);
    this.context.addEventListener("statechange", () => {
      for (const remote of this.#remotes.values()) this.updateRoute(remote.route);
    });
  }

  async resume(): Promise<void> { await this.context.resume(); }
  setNPCVolume(value: number): void { setGain(this.npc, value); }
  setMasterVolume(value: number): void { setGain(this.master, value); }

  async setOutputDevice(deviceId: string): Promise<boolean> {
    const context = this.context as AudioContext & { setSinkId?: (id: string) => Promise<void> };
    if (!context.setSinkId) return false;
    await context.setSinkId(deviceId);
    return true;
  }

  async playHeadphoneTest(url: string): Promise<void> {
    await this.resume();
    const response = await fetch(url);
    if (!response.ok) throw new Error(t("error.sampleLoad"));
    const buffer = await this.context.decodeAudioData(await response.arrayBuffer());
    const source = new AudioBufferSourceNode(this.context, { buffer });
    source.connect(this.npc); source.start();
    await new Promise<void>((resolve) => { source.addEventListener("ended", () => { source.disconnect(); resolve(); }, { once: true }); });
  }

  async recordAndPlayMicrophone(stream: MediaStream, gainValue: number, durationMs = 2500): Promise<void> {
    if (typeof MediaRecorder === "undefined") throw new Error(t("error.noRecorder"));
    const recorder = new MediaRecorder(stream);
    const chunks: BlobPart[] = [];
    recorder.addEventListener("dataavailable", (event) => { if (event.data.size) chunks.push(event.data); });
    const stopped = new Promise<void>((resolve, reject) => {
      recorder.addEventListener("stop", () => resolve(), { once: true });
      recorder.addEventListener("error", () => reject(new Error(t("error.recordFailed"))), { once: true });
    });
    recorder.start();
    await new Promise((resolve) => window.setTimeout(resolve, durationMs));
    recorder.stop(); await stopped;
    const blob = new Blob(chunks, { type: recorder.mimeType });
    const buffer = await this.context.decodeAudioData(await blob.arrayBuffer());
    const source = new AudioBufferSourceNode(this.context, { buffer });
    const gain = new GainNode(this.context, { gain: clamp(gainValue, 0, 2) });
    source.connect(gain).connect(this.master); source.start();
    await new Promise<void>((resolve) => { source.addEventListener("ended", () => { source.disconnect(); gain.disconnect(); resolve(); }, { once: true }); });
  }

  setListener(position: Vec3, forward: Vec3): void {
    this.#listener = position;
    const listener = this.context.listener;
    const now = this.context.currentTime;
    // Map GTA's X/Y/Z axes to Web Audio without mirroring left and right.
    param(listener.positionX, position.x, now); param(listener.positionY, position.z, now); param(listener.positionZ, -position.y, now);
    param(listener.forwardX, forward.x, now); param(listener.forwardY, forward.z, now); param(listener.forwardZ, -forward.y, now);
    param(listener.upX, 0, now); param(listener.upY, 1, now); param(listener.upZ, 0, now);
  }

  attach(identity: string, stream: MediaStream, route: Route): void {
    this.detach(identity);
    const source = new MediaStreamAudioSourceNode(this.context, { mediaStream: stream });
    const audible = new GainNode(this.context, { gain: 0 });
    const distance = new GainNode(this.context, { gain: 1 });
    const panner = route.spatial ? createPanner(this.context) : null;
    const position = route.position ?? { x: 0, y: 0, z: 0 };
    source.connect(audible).connect(distance);
    if (panner) { setPosition(panner, position, 0); distance.connect(panner).connect(this.npc); }
    else distance.connect(this.npc);
    this.#remotes.set(identity, {
      source, audible, distance, panner, position, target: position,
      velocity: route.velocity ?? { x: 0, y: 0, z: 0 }, receivedAt: performance.now(),
      route, transmitting: false, releaseTimer: 0,
    });
    if (this.#remotes.size === 1) this.#onSpatialDemand(true);
    this.updateRoute(route);
  }

  updateRoute(route: Route): void {
    const remote = this.#remotes.get(route.sourceId); if (!remote) return;
    remote.route = route; remote.target = route.position ?? remote.target; remote.velocity = route.velocity ?? remote.velocity; remote.receivedAt = performance.now();
    if (remote.panner) {
      const gain = route.kind !== "vehicle_cabin"
        ? proximityGain(distance(this.#listener, remote.target), route.voiceMode ?? 2, route.voiceDistance)
        : 1;
      remote.distance.gain.setTargetAtTime(gain, this.context.currentTime, 0.04);
    }
    const routed = (route.transmitMask & TRANSMIT_SCRIPTED) !== 0;
    const transmitting = routed && this.context.state === "running";
    if (transmitting) {
      window.clearTimeout(remote.releaseTimer); remote.releaseTimer = 0;
      this.#setRemoteTransmitting(route.sourceId, remote, true);
    } else if (remote.transmitting && remote.releaseTimer === 0) {
      // Keep the queued tail to avoid clipping the final phoneme.
      remote.releaseTimer = window.setTimeout(() => {
        remote.releaseTimer = 0; this.#setRemoteTransmitting(route.sourceId, remote, false);
      }, 200);
    }
    this.#reconcileActive(route.sourceId, remote);
  }

  render(now = performance.now()): void {
    for (const identity of [...this.#activeRemotes]) {
      const remote = this.#remotes.get(identity);
      if (!remote) { this.#activeRemotes.delete(identity); continue; }
      if (remote.panner && this.#needsSpatialUpdate(remote)) {
        const prediction = clamp((now - remote.receivedAt) / 1000, 0, 0.2);
        const target = { x: remote.target.x + remote.velocity.x * prediction, y: remote.target.y + remote.velocity.y * prediction, z: remote.target.z + remote.velocity.z * prediction };
        remote.position = lerp(remote.position, target, 0.55);
        setPosition(remote.panner, remote.position, 0.04);
        // Cabin audio is never distance-attenuated.
        const gain = remote.route.kind !== "vehicle_cabin"
          ? proximityGain(distance(this.#listener, remote.position), remote.route.voiceMode ?? 2, remote.route.voiceDistance)
          : 1;
        remote.distance.gain.setTargetAtTime(gain, this.context.currentTime, 0.04);
      }
      this.#reconcileActive(identity, remote);
    }
  }

  detach(identity: string): void {
    const remote = this.#remotes.get(identity); if (!remote) return;
    window.clearTimeout(remote.releaseTimer);
    if (remote.transmitting) this.#onNPCSpeaking(identity.slice(4), false);
    remote.source.disconnect(); remote.audible.disconnect();
    remote.distance.disconnect(); remote.panner?.disconnect(); this.#remotes.delete(identity);
    this.#activeRemotes.delete(identity); this.#stopRenderLoopIfIdle();
    if (this.#remotes.size === 0) this.#onSpatialDemand(false);
  }

  #ensureRenderLoop(): void {
    if (this.#renderTimer !== 0 || this.#activeRemotes.size === 0) return;
    this.#renderTimer = window.setInterval(() => this.render(), SPATIAL_UPDATE_MS);
  }

  #stopRenderLoopIfIdle(): void {
    if (this.#activeRemotes.size !== 0 || this.#renderTimer === 0) return;
    window.clearInterval(this.#renderTimer); this.#renderTimer = 0;
  }

  #reconcileActive(identity: string, remote: RemoteSource): void {
    const active = remote.panner !== null && this.#needsSpatialUpdate(remote);
    if (active) {
      this.#activeRemotes.add(identity); this.#ensureRenderLoop();
    } else {
      this.#activeRemotes.delete(identity); this.#stopRenderLoopIfIdle();
    }
  }

  #needsSpatialUpdate(remote: RemoteSource): boolean {
    if (remote.transmitting || remote.route.kind === "vehicle_cabin") return true;
    const moving = Math.abs(remote.velocity.x) + Math.abs(remote.velocity.y)
      + Math.abs(remote.velocity.z) > 0.01;
    return moving || distance(remote.position, remote.target) > 0.01;
  }


  #setRemoteTransmitting(identity: string, remote: RemoteSource, active: boolean): void {
    if (remote.transmitting === active) return;
    remote.transmitting = active;
    remote.audible.gain.setTargetAtTime(active ? 1 : 0, this.context.currentTime, active ? 0.015 : 0.025);
    this.#onNPCSpeaking(identity.slice(4), active);
    this.#reconcileActive(identity, remote);
  }

  async microphone(deviceId: string, gainValue: number): Promise<MicrophonePipeline> {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: {
      deviceId: deviceId ? { exact: deviceId } : undefined,
      echoCancellation: false, noiseSuppression: false, autoGainControl: false,
      channelCount: 1,
    }, video: false });
    const source = new MediaStreamAudioSourceNode(this.context, { mediaStream: stream });
    const gain = new GainNode(this.context, { gain: gainValue });
    const destination = new MediaStreamAudioDestinationNode(this.context);
    source.connect(gain).connect(destination);
    const track = destination.stream.getAudioTracks()[0];
    if (!track) { stream.getTracks().forEach((item) => item.stop()); throw new Error("microphone pipeline did not produce an audio track"); }
    return { track, stream, gain, close: () => { source.disconnect(); gain.disconnect(); destination.disconnect(); stream.getTracks().forEach((item) => item.stop()); track.stop(); } };
  }
}

export function proximityGain(meters: number, mode: number, exactDistance?: number): number {
  const profile = exactDistance && exactDistance > 0
    ? { full: Math.max(1, exactDistance * 0.2), max: exactDistance, exponent: 1.2 }
    : mode === 1 ? { full: 1.25, max: 6, exponent: 1.35 } : mode === 3 ? { full: 5, max: 32, exponent: 1.1 } : { full: 3, max: 18, exponent: 1.2 };
  if (meters <= profile.full) return 1; if (meters >= profile.max) return 0;
  return Math.pow(1 - (meters - profile.full) / (profile.max - profile.full), profile.exponent);
}

function createPanner(context: AudioContext): PannerNode { return new PannerNode(context, { panningModel: "HRTF", distanceModel: "inverse", refDistance: 1, maxDistance: 10000, rolloffFactor: 0 }); }
function setPosition(node: PannerNode, value: Vec3, smoothing: number): void {
  const set = (parameter: AudioParam, next: number) => smoothing ? parameter.setTargetAtTime(next, node.context.currentTime, smoothing) : parameter.setValueAtTime(next, node.context.currentTime);
  set(node.positionX, value.x); set(node.positionY, value.z); set(node.positionZ, -value.y);
}
function param(parameter: AudioParam, value: number, now: number): void { parameter.setTargetAtTime(value, now, 0.01); }
function setGain(node: GainNode, value: number): void { node.gain.setTargetAtTime(clamp(value, 0, 2), node.context.currentTime, 0.01); }
function distance(a: Vec3, b: Vec3): number { return Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z); }
function lerp(a: Vec3, b: Vec3, amount: number): Vec3 { return { x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount, z: a.z + (b.z - a.z) * amount }; }
function clamp(value: number, min: number, max: number): number { return Math.max(min, Math.min(max, value)); }
