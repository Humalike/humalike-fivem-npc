import "./style.css";
import { AudioEngine, type MicrophonePipeline } from "./audio";
import { acquireMicrophoneSource, HubUnavailableError, type MicrophoneSourceHandle } from "./audiohub";
import { ControlClient, type ControlStatus } from "./control";
import { MediaClient, type MediaStatus } from "./media";
import { CAPABILITY_AUTHORITATIVE_VEHICLE_CABINS, CAPABILITY_DIRECT_NPC_TARGETS, PROTOCOL_VERSION, type GameRealtimeState, type Route, type ServerMessage, type Vec3 } from "./protocol";
import { effectivePtt, negotiatedTransmitMask } from "./transmit-mask.mjs";
import { readyServerId } from "./publication-source.mjs";
import { installNpcEdgeTransport } from "./npc-edge";

declare const GetParentResourceName: undefined | (() => string);

interface Session { ticket: string; controlUrl: string; expiresAt: string }
interface Settings { inputDevice: string; outputDevice: string; microphoneGain: number; npcVolume: number }

const defaults: Settings = { inputDevice: "", outputDevice: "", microphoneGain: 1, npcVolume: 1 };
let settings = loadSettings();
let control: ControlClient | null = null;
let media: MediaClient | null = null;
let audio: AudioEngine | null = null;
let microphone: MicrophonePipeline | null = null;
let realtime: GameRealtimeState | null = null;
let sequence = 0;
let txGeneration = 0;
let txActive = false;
let nativePttActive = false;
let testPttActive = false;
let cabinAuthorized = false;
let cabinCapability = false;
let directTargetCapability = false;
let targetNpcIds: string[] = [];
let mediaTransmitting = false;
let mediaTransmitOperation = 0;
let routes = new Map<string, Route>();
let controlStatus: ControlStatus = "idle";
let mediaStatus: MediaStatus = "idle";
let reconnectTimer = 0;
let readyRequest: Promise<void> | null = null;
let shuttingDown = false;
let proximityBinding = "—";
let deviceTestRunning = false;
const nuiBootId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
installNpcEdgeTransport();

const app = document.querySelector<HTMLElement>("#app");
if (!app) throw new Error("app root missing");
app.innerHTML = `
  <main class="panel" role="dialog" aria-modal="true" aria-label="Ustawienia głosu">
    <header><div><span class="eyebrow">HUMALIKE</span><h1>Ustawienia głosu</h1></div><button id="close" class="icon" aria-label="Zamknij">×</button></header>
    <section class="status"><span id="control-status">CONTROL IDLE</span><span id="media-status">MEDIA IDLE</span><span id="ptt-status">MIKROFON WYCISZONY</span></section>
    <section class="grid">
      <article>
        <h2>Urządzenia</h2>
        <label>Mikrofon<select id="input"><option value="">Domyślne urządzenie</option></select></label>
        <label>Słuchawki<select id="output"><option value="">Domyślne urządzenie</option></select></label>
        <div class="actions"><button id="refresh">Odśwież urządzenia</button><button id="reconnect">Połącz ponownie</button></div>
        <div class="actions"><button id="test-output">Test słuchawek</button><button id="test-input">Test mikrofonu (2,5 s)</button></div>
        <p id="output-hint" class="hint"></p>
      </article>
      <article>
        <h2>Głośność</h2>
        <label class="range">Głośność mówienia <output id="mic-gain-value"></output><input id="mic-gain" type="range" min="0" max="2" step="0.05"></label>
        <label class="range">Głośność NPC <output id="npc-volume-value"></output><input id="npc-volume" type="range" min="0" max="2" step="0.05"></label>
        <label class="range unavailable">Głośność całego voice <output>Wkrótce</output><input type="range" value="1" disabled></label>
        <label class="range unavailable">Głośność radia <output>Wkrótce</output><input type="range" value="1" disabled></label>
        <label class="range unavailable">Głośność rozmów telefonicznych <output>Wkrótce</output><input type="range" value="1" disabled></label>
      </article>
      <article class="ptt-card">
        <h2>Przycisk mówienia</h2>
        <div class="binding"><kbd id="ptt-binding">—</kbd><div><strong>Natywny Push to Talk</strong><span>Ten sam przycisk co wbudowany voice FiveM</span></div></div>
        <button id="test-ptt" class="primary">Przytrzymaj, aby przetestować</button>
        <p>Voice jest fail-muted: poza przytrzymaniem PTT track pozostaje wyciszony.</p>
      </article>
      <article>
        <h2>Diagnostyka</h2>
        <dl><dt>Control plane</dt><dd id="diag-control">—</dd><dt>Media</dt><dd id="diag-media">—</dd><dt>Routing</dt><dd id="diag-routes">0 źródeł</dd><dt>AudioContext</dt><dd id="diag-audio">—</dd></dl>
      </article>
    </section>
    <footer><span>Komenda <code>/voice</code></span><span id="error" class="error"></span></footer>
  </main>`;
if (typeof GetParentResourceName === "function") app.classList.add("hidden");

const input = byId<HTMLSelectElement>("input");
const output = byId<HTMLSelectElement>("output");
const micGain = byId<HTMLInputElement>("mic-gain");
const npcVolume = byId<HTMLInputElement>("npc-volume");
micGain.value = String(settings.microphoneGain); npcVolume.value = String(settings.npcVolume);
renderSettings(); renderStatus();

byId("close").addEventListener("click", () => nuiBestEffort("close"));
window.addEventListener("keydown", (event) => {
  if (event.key !== "Escape" || app.classList.contains("hidden")) return;
  event.preventDefault(); nuiBestEffort("close");
});
byId("refresh").addEventListener("click", () => void refreshDevices());
byId("reconnect").addEventListener("click", requestSession);
byId("test-output").addEventListener("click", () => void testOutput());
byId("test-input").addEventListener("click", () => void testInput());
input.addEventListener("change", () => { settings.inputDevice = input.value; saveSettings(); requestSession(); });
output.addEventListener("change", () => { settings.outputDevice = output.value; saveSettings(); void applyOutput(); });
micGain.addEventListener("input", () => { settings.microphoneGain = Number(micGain.value); microphone?.gain.gain.setTargetAtTime(settings.microphoneGain, audio?.context.currentTime ?? 0, 0.01); saveSettings(); renderSettings(); });
npcVolume.addEventListener("input", () => { settings.npcVolume = Number(npcVolume.value); audio?.setNPCVolume(settings.npcVolume); saveSettings(); renderSettings(); });
bindHold(byId("test-ptt"));

window.addEventListener("message", (event: MessageEvent<unknown>) => {
  if (!event.data || typeof event.data !== "object") return;
  const message = event.data as Record<string, unknown>;
  if (message.type === "ui:setOpen") {
    const open = message.open === true;
    app.classList.toggle("hidden", !open);
  }
  else if (message.type === "voice:keybind") { proximityBinding = normalizeBinding(String(message.binding ?? "")); renderStatus(); }
  else if (message.type === "voice:bootstrap") signalReady();
  else if (message.type === "voice:reconnect") requestSession();
  else if (message.type === "voice:session") {
    if (isSession(message.session)) void startSession(message.session);
    else { fail("Nieprawidłowa sesja voice"); scheduleReconnect(); }
  } else if (message.type === "voice:sessionFailed") fail(`Nie udało się utworzyć sesji (HTTP ${String(message.status)})`);
  else if (message.type === "voice:ptt") setNativePTT(message.active === true);
  else if (message.type === "voice:targets") {
    const next = normalizeTargetNpcIds(message.targetNpcIds);
    if (!sameStrings(targetNpcIds, next)) { targetNpcIds = next; publishRealtime(); }
  }
  else if (message.type === "voice:cabin") setCabinAuthorized(message.active === true);
  else if (message.type === "game:listener") {
    const position = message.position as Vec3; const forward = message.forward as Vec3;
    audio?.setListener(position, forward);
  } else if (message.type === "game:realtime") {
    realtime = message.state as GameRealtimeState; publishRealtime();
  } else if (message.type === "voice:shutdown") shutdown();
});

window.addEventListener("blur", () => setTestPTT(false));
signalReady();
window.setInterval(() => {
  if (txActive) sendTX();
}, 500);

async function startSession(session: Session): Promise<void> {
  shuttingDown = false; window.clearTimeout(reconnectTimer); disconnect(); clearError();
  let client: ControlClient;
  client = new ControlClient(session.controlUrl, session.ticket, handleControlMessage, (status) => {
    if (control !== client) return;
    controlStatus = status;
    if (status === "connected") window.clearTimeout(reconnectTimer);
    if (status === "closed" || status === "error") {
      setCabinCapability(false);
      setDirectTargetCapability(false);
      setActualTransmitting(false);
      disconnectMedia();
      scheduleReconnect();
    }
    renderStatus();
  });
  control = client; client.connect();
}

function handleControlMessage(message: ServerMessage): void {
  if (message.type === "error") {
    retrySession(`${message.code}: ${message.message}`);
    return;
  }
  if (message.type === "route_snapshot") {
    const audibleRoutes = message.routes.filter((route) =>
      route.sourceKind === "npc" || route.sourceId.startsWith("npc:"));
    routes = new Map(audibleRoutes.map((route) => [route.sourceId, route]));
    media?.setRoutes(audibleRoutes); for (const route of audibleRoutes) audio?.updateRoute(route);
    renderStatus(); return;
  }
  setCabinCapability(message.capabilities?.includes(
    CAPABILITY_AUTHORITATIVE_VEHICLE_CABINS) === true);
  setDirectTargetCapability(message.capabilities?.includes(
    CAPABILITY_DIRECT_NPC_TARGETS) === true);
  if (!message.livekitToken) {
    retrySession("Router nie wydał tokenu LiveKit");
    return;
  }
  const expectedServerId = readyServerId(message.serverId, message.room);
  void connectMedia(message.livekitUrl, message.livekitToken, expectedServerId ?? "");
}

async function connectMedia(url: string, token: string, expectedServerId: string): Promise<void> {
  let client: MediaClient | null = null;
  try {
    audio ??= new AudioEngine(reportNPCSpeech);
    audio.setNPCVolume(settings.npcVolume); audio.setMasterVolume(1);
    await audio.resume(); await applyOutput();
    client = new MediaClient(expectedServerId, (identity, stream) => {
      const route = routes.get(identity); if (route) audio?.attach(identity, stream, route);
    }, (identity) => { audio?.detach(identity); }, (status) => {
      if (media !== client) return;
      mediaStatus = status;
      if (status === "closed" || status === "error") {
        retrySession(`LiveKit ${status}`);
        return;
      }
      renderStatus();
    });
    media = client;
    await client.connect(url, token);
    if (media !== client) { client.disconnect(); return; }
    client.setRoutes([...routes.values()]);
    byId("output-hint").textContent = "Odbiór WebRTC jest aktywny. Jeśli FiveM prosi o mikrofon, otwórz F8 i wybierz Allow.";
    void connectMicrophone(client, audio);
  } catch (error) {
    if (client && media === client) {
      retrySession(error instanceof Error ? error.message : "Nie udało się połączyć z WebRTC");
    } else {
      client?.disconnect();
    }
  }
}

async function connectMicrophone(client: MediaClient, engine: AudioEngine): Promise<void> {
  let source: MicrophoneSourceHandle | null = null;
  let pipeline: MicrophonePipeline | null = null;
  try {
    source = await acquireMicrophoneSource({
      deviceId: settings.inputDevice,
      onLost: () => { if (media === client) retrySession("Utracono współdzielony mikrofon (audio hub)"); },
    });
    if (media !== client) { source.release(); return; }
    const kind = source.kind;
    pipeline = engine.microphone(source, settings.microphoneGain);
    source = null;
    if (media !== client) { pipeline.close(); return; }
    microphone?.close(); microphone = pipeline;
    await client.publish(pipeline.track);
    await syncMediaTransmitting(txActive);
    await refreshDevices();
    clearError();
    byId("output-hint").textContent = kind === "hub"
      ? "Mikrofon WebRTC jest aktywny (współdzielone przechwytywanie audio hub)."
      : "Mikrofon WebRTC jest aktywny.";
  } catch (error) {
    source?.release();
    pipeline?.close();
    if (media !== client) return;
    fail(microphoneError(error));
  }
}

function transmitMask(): number {
  return negotiatedTransmitMask(txActive, cabinAuthorized, cabinCapability);
}
function publishRealtime(): void {
  if (!realtime || !control) return;
  control.realtime({ ...realtime, v: PROTOCOL_VERSION, type: "realtime_state", seq: ++sequence,
    transmitMask: transmitMask(), transmitGeneration: txGeneration,
    ...(directTargetCapability ? { targetNpcIds } : {}) });
}

function syncPTT(): void {
  const active = effectivePtt(nativePttActive, testPttActive);
  if (txActive === active) return;
  txActive = active; txGeneration++; sendTX(); publishRealtime(); void syncMediaTransmitting(active); renderStatus();
}
function setNativePTT(active: boolean): void {
  if (nativePttActive === active) return;
  nativePttActive = active; syncPTT();
}
function setTestPTT(active: boolean): void {
  if (testPttActive === active) return;
  testPttActive = active; syncPTT();
}
function setCabinAuthorized(active: boolean): void {
  if (cabinAuthorized === active) return;
  cabinAuthorized = active;
  if (txActive) { txGeneration++; sendTX(); publishRealtime(); }
  renderStatus();
}
function setCabinCapability(active: boolean): void {
  if (cabinCapability === active) return;
  cabinCapability = active;
  if (txActive) { txGeneration++; sendTX(); publishRealtime(); }
  renderStatus();
}
function setDirectTargetCapability(active: boolean): void {
  if (directTargetCapability === active) return;
  directTargetCapability = active;
  nuiBestEffort("directTargetCapability", { active });
  publishRealtime();
}
function sendTX(): void {
  control?.transmit(txGeneration, transmitMask(), directTargetCapability ? targetNpcIds : undefined);
}

async function syncMediaTransmitting(active: boolean): Promise<void> {
  const operation = ++mediaTransmitOperation;
  const client = media;
  if (!active) setActualTransmitting(false);
  if (!client || mediaStatus !== "connected" || controlStatus !== "connected") {
    if (operation === mediaTransmitOperation) setActualTransmitting(false);
    return;
  }
  try {
    const applied = await client.setTransmitting(active);
    const current = operation === mediaTransmitOperation && media === client;
    if (!current) {
      if (active && applied) await client.setTransmitting(false).catch(() => false);
      return;
    }
    setActualTransmitting(active && applied && txActive);
  } catch {
    if (operation === mediaTransmitOperation) setActualTransmitting(false);
  }
}

function setActualTransmitting(active: boolean): void {
  if (mediaTransmitting === active) return;
  mediaTransmitting = active;
  nuiBestEffort("transmitState", { active });
}

function scheduleReconnect(): void {
  if (shuttingDown) return;
  window.clearTimeout(reconnectTimer);
  reconnectTimer = window.setTimeout(requestSession, 1500);
}
function retrySession(message: string): void {
  fail(message);
  disconnect();
  scheduleReconnect();
}
function requestSession(): void {
  window.clearTimeout(reconnectTimer);
  disconnect();
  void nui("requestSession").catch(() => scheduleReconnect());
}
function disconnect(): void {
  setTestPTT(false);
  setCabinCapability(false);
  setDirectTargetCapability(false);
  mediaTransmitOperation++;
  setActualTransmitting(false);
  const previous = control; control = null; previous?.close(); controlStatus = "idle"; disconnectMedia(); renderStatus();
}
function disconnectMedia(): void {
  mediaTransmitOperation++;
  setActualTransmitting(false);
  const previous = media; media = null; previous?.disconnect();
  mediaStatus = "idle"; microphone?.close(); microphone = null;
}
function shutdown(): void { shuttingDown = true; window.clearTimeout(reconnectTimer); setNativePTT(false); disconnect(); }

async function refreshDevices(): Promise<void> {
  if (!navigator.mediaDevices?.enumerateDevices) return;
  const devices = await navigator.mediaDevices.enumerateDevices();
  fillDevices(input, devices.filter((item) => item.kind === "audioinput"), settings.inputDevice, "Domyślny mikrofon");
  fillDevices(output, devices.filter((item) => item.kind === "audiooutput"), settings.outputDevice, "Domyślne słuchawki");
}
async function applyOutput(): Promise<void> {
  if (!audio) return;
  const supported = await audio.setOutputDevice(settings.outputDevice).catch(() => false);
  byId("output-hint").textContent = supported ? "Wybrane urządzenie jest aktywne." : "Ta wersja CEF używa domyślnego wyjścia ustawionego w systemie/FiveM.";
}

function renderSettings(): void {
  byId("mic-gain-value").textContent = `${Math.round(settings.microphoneGain * 100)}%`;
  byId("npc-volume-value").textContent = `${Math.round(settings.npcVolume * 100)}%`;
}
function renderStatus(): void {
  byId("control-status").textContent = `CONTROL ${controlStatus.toUpperCase()}`;
  byId("media-status").textContent = `MEDIA ${mediaStatus.toUpperCase()}`;
  byId("ptt-status").textContent = txActive
    ? cabinAuthorized && cabinCapability ? "NADAJESZ PROXIMITY + KABINA" : "NADAJESZ PROXIMITY"
    : "MIKROFON WYCISZONY";
  byId("ptt-status").classList.toggle("live", txActive);
  byId("diag-control").textContent = controlStatus;
  byId("diag-media").textContent = mediaStatus;
  byId("diag-routes").textContent = `${routes.size} źródeł`;
  byId("diag-audio").textContent = audio?.context.state ?? "nieuruchomiony";
  byId("ptt-binding").textContent = proximityBinding;
}

async function testOutput(): Promise<void> {
  if (deviceTestRunning) return;
  deviceTestRunning = true; setDeviceTestButtons(true); clearError();
  try {
    audio ??= new AudioEngine(reportNPCSpeech);
    audio.setNPCVolume(settings.npcVolume); audio.setMasterVolume(1);
    await applyOutput(); await audio.playHeadphoneTest("audio/voice-test.wav");
  } catch (error) { fail(error instanceof Error ? error.message : "Test słuchawek nie powiódł się"); }
  finally { deviceTestRunning = false; setDeviceTestButtons(false); }
}
async function testInput(): Promise<void> {
  if (deviceTestRunning || !microphone || !audio) { if (!microphone) fail("Najpierw połącz mikrofon z voice."); return; }
  deviceTestRunning = true; setDeviceTestButtons(true); clearError();
  byId("output-hint").textContent = "Mów teraz — nagrywam próbkę przez 2,5 sekundy…";
  try {
    await audio.recordAndPlayMicrophone(microphone.stream, settings.microphoneGain);
    byId("output-hint").textContent = "Odtworzono próbkę mikrofonu na wybranych słuchawkach.";
  } catch (error) { fail(error instanceof Error ? error.message : "Test mikrofonu nie powiódł się"); }
  finally { deviceTestRunning = false; setDeviceTestButtons(false); }
}
function setDeviceTestButtons(disabled: boolean): void {
  byId<HTMLButtonElement>("test-output").disabled = disabled;
  byId<HTMLButtonElement>("test-input").disabled = disabled;
}
function normalizeBinding(value: string): string {
  if (!value) return "—";
  if (value.startsWith("t_")) return value.slice(2).toUpperCase();
  if (value.startsWith("b_")) return "PAD";
  return value.toUpperCase();
}
function normalizeTargetNpcIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const result: string[] = [];
  const seen = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string" || item.length === 0 || item.length > 128 || seen.has(item)) continue;
    seen.add(item); result.push(item);
    if (result.length === 16) break;
  }
  return result;
}
function sameStrings(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}
function reportNPCSpeech(id: string, active: boolean): void {
  nuiBestEffort("actorSpeechState", { kind: "npc", id, active });
}
function fillDevices(select: HTMLSelectElement, devices: MediaDeviceInfo[], selected: string, fallback: string): void {
  select.replaceChildren(new Option(fallback, ""));
  devices.forEach((device, index) => select.add(new Option(device.label || `${fallback} ${index + 1}`, device.deviceId)));
  select.value = [...select.options].some((option) => option.value === selected) ? selected : "";
}
function bindHold(button: HTMLElement): void {
  let releaseTimer = 0;
  button.addEventListener("pointerdown", (event) => {
    event.preventDefault(); button.setPointerCapture(event.pointerId);
    window.clearTimeout(releaseTimer); releaseTimer = 0; setTestPTT(true);
  });
  for (const event of ["pointerup", "pointercancel", "lostpointercapture"]) button.addEventListener(event, () => {
    if (releaseTimer) return;
    releaseTimer = window.setTimeout(() => { releaseTimer = 0; setTestPTT(false); }, 200);
  });
}
function fail(message: string): void {
  byId("error").textContent = message;
  renderStatus();
}
function clearError(): void { byId("error").textContent = ""; }
function microphoneError(error: unknown): string {
  if (error instanceof DOMException && (error.name === "NotAllowedError" || error.name === "PermissionDeniedError")) {
    return "Brak zgody na mikrofon. Otwórz F8, zaakceptuj Capture your microphone, potem kliknij Połącz ponownie w /voice.";
  }
  if (error instanceof HubUnavailableError) {
    return `Współdzielony mikrofon (audio hub) nie dostarczył dźwięku: ${error.message}. Kliknij Połącz ponownie albo sprawdź zasób audio hub.`;
  }
  return error instanceof Error ? `Mikrofon WebRTC: ${error.message}` : "Nie udało się uruchomić mikrofonu WebRTC";
}
function signalReady(): void {
  if (readyRequest) return;
  readyRequest = nui("ready", { bootId: nuiBootId }).catch(() => undefined).finally(() => { readyRequest = null; });
}
function isSession(value: unknown): value is Session {
  if (!value || typeof value !== "object") return false;
  const session = value as Partial<Session>;
  if (typeof session.ticket !== "string" || session.ticket.length === 0
    || typeof session.controlUrl !== "string") return false;
  try {
    const url = new URL(session.controlUrl);
    return url.protocol === "wss:"
      || (url.protocol === "ws:" && (url.hostname === "127.0.0.1" || url.hostname === "localhost"));
  } catch { return false; }
}
function byId<T extends HTMLElement = HTMLElement>(id: string): T { const node = document.getElementById(id); if (!node) throw new Error(`missing #${id}`); return node as T; }
function saveSettings(): void { localStorage.setItem("humalike.voice.settings.v1", JSON.stringify(settings)); }
function loadSettings(): Settings { try { return { ...defaults, ...JSON.parse(localStorage.getItem("humalike.voice.settings.v1") ?? "{}") as Partial<Settings> }; } catch { return { ...defaults }; } }
function nuiBestEffort(name: string, body: unknown = {}): void {
  void nui(name, body).catch((error: unknown) => {
    if (!(error && typeof error === "object" && "name" in error && error.name === "AbortError")) {
      console.error(`[humalike:nui] callback ${name} failed`, error);
    }
  });
}
async function nui(name: string, body: unknown = {}): Promise<void> {
  if (typeof GetParentResourceName !== "function") return;
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(`https://${GetParentResourceName()}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`NUI callback ${name} failed with HTTP ${response.status}`);
  } finally {
    window.clearTimeout(timeout);
  }
}
