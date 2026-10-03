import logoUrl from "./humalike.svg?url";
import { isLabelTuple, normalizeLanguage, presentationScale } from "./model.mjs";
import "./style.css";

// A label is one small DOM element moved with a transform: the compositor
// shifts a layer instead of repainting a screen-sized canvas on every frame.
type LabelTuple = [x: number, y: number, language: string | false, muted: 0 | 1, id?: string];

interface LabelNode {
  root: HTMLDivElement;
  flag: HTMLSpanElement;
  mute: HTMLSpanElement;
  language: string | null;
  muted: boolean;
  seen: number;
  x: number;
  y: number;
  at: number;
}

// Labels missing from the game for this long are dropped (the game sends an
// explicit clear; this covers a dead script).
const STALE_MS = 3000;
const MIN_TRANSITION_MS = 16;
const MAX_TRANSITION_MS = 120;
// A label glides to each new position over one frame interval, so it would
// trail the head by that much. The glide is aimed one interval ahead along
// the label's own motion instead; the step is capped so a stop never overshoots far.
const PREDICT_FACTOR = 1.0;
const MAX_PREDICT_PX = 40;

const container = document.createElement("div");
container.id = "humalike-labels";
container.setAttribute("aria-hidden", "true");
document.body.append(container);

const nodes = new Map<string, LabelNode>();
let generation = 0;
let lastFrameAt = 0;
let staleTimer = 0;
let transitionMs = 50;

window.addEventListener("message", ({ data }: MessageEvent<unknown>) => {
  if (!data || typeof data !== "object") return;
  const message = data as Record<string, unknown>;
  if (message.type === "labels:frame") {
    const labels = Array.isArray(message.labels)
      ? message.labels.filter(isLabelTuple) as LabelTuple[]
      : [];
    const scale = typeof message.scale === "number" ? message.scale : 1;
    applyFrame(labels, scale);
  } else if (message.type === "labels:clear" || message.type === "shutdown") {
    clear();
  }
});

function applyFrame(labels: LabelTuple[], configuredScale: number): void {
  const now = performance.now();
  if (lastFrameAt > 0) {
    const interval = now - lastFrameAt;
    if (interval < STALE_MS) {
      transitionMs = Math.min(MAX_TRANSITION_MS, Math.max(MIN_TRANSITION_MS, interval));
    }
  }
  lastFrameAt = now;
  generation += 1;
  const width = Math.max(1, window.innerWidth);
  const height = Math.max(1, window.innerHeight);
  container.style.setProperty("--s", String(presentationScale(height, configuredScale)));
  container.style.setProperty("--t", `${Math.round(transitionMs)}ms`);
  labels.forEach((label, index) => {
    const [x, y, rawLanguage, muted, id] = label;
    const key = typeof id === "string" && id.length > 0 ? id : `#${index}`;
    const node = nodes.get(key) ?? createNode(key);
    node.seen = generation;
    let px = x * width;
    let py = y * height;
    const dt = now - node.at;
    if (node.at > 0 && dt > 0 && dt < STALE_MS) {
      // Velocity from the last two frames, projected one glide ahead.
      let dx = (px - node.x) / dt * transitionMs * PREDICT_FACTOR;
      let dy = (py - node.y) / dt * transitionMs * PREDICT_FACTOR;
      const step = Math.hypot(dx, dy);
      if (step > MAX_PREDICT_PX) { dx *= MAX_PREDICT_PX / step; dy *= MAX_PREDICT_PX / step; }
      node.x = px; node.y = py;
      px += dx; py += dy;
    } else {
      node.x = px; node.y = py;
    }
    node.at = now;
    node.root.style.transform = `translate3d(${px.toFixed(1)}px, ${py.toFixed(1)}px, 0)`;
    const language = rawLanguage === false ? null : normalizeLanguage(rawLanguage);
    if (language !== node.language) setLanguage(node, language);
    if ((muted === 1) !== node.muted) setMuted(node, muted === 1);
  });
  for (const [key, node] of nodes) {
    if (node.seen !== generation) { node.root.remove(); nodes.delete(key); }
  }
  armStaleCheck();
}

function createNode(key: string): LabelNode {
  const root = document.createElement("div");
  root.className = "hl-label hl-enter";
  const icon = document.createElement("span");
  icon.className = "hl-icon";
  const logo = document.createElement("img");
  logo.src = logoUrl;
  logo.alt = "";
  icon.append(logo);
  const pill = document.createElement("span");
  pill.className = "hl-pill";
  const ai = document.createElement("span");
  ai.className = "hl-ai";
  ai.textContent = "AI";
  const flag = document.createElement("span");
  flag.className = "hl-flag";
  flag.hidden = true;
  const mute = document.createElement("span");
  mute.className = "hl-mute";
  mute.hidden = true;
  mute.innerHTML = '<svg viewBox="0 0 14 14" aria-hidden="true"><path d="M0 5h4l4-3.6v11.2L4 9H0z"/><path class="hl-mute-x" d="M10 4l4 6M14 4l-4 6"/></svg>';
  pill.append(ai, flag, mute);
  root.append(icon, pill);
  container.append(root);
  // The first frame lands without a slide from the corner.
  requestAnimationFrame(() => root.classList.remove("hl-enter"));
  const node: LabelNode = { root, flag, mute, language: null, muted: false, seen: 0, x: 0, y: 0, at: 0 };
  nodes.set(key, node);
  return node;
}

const FLAG_LANGUAGES = new Set(["pl", "de", "es", "fr", "en"]);

function setLanguage(node: LabelNode, language: string | null): void {
  node.language = language;
  const flag = node.flag;
  flag.className = "hl-flag";
  flag.textContent = "";
  if (language === null) { flag.hidden = true; return; }
  flag.hidden = false;
  if (FLAG_LANGUAGES.has(language)) {
    flag.classList.add(`hl-flag-${language}`);
  } else {
    flag.classList.add("hl-flag-code");
    flag.textContent = language;
  }
}

function setMuted(node: LabelNode, muted: boolean): void {
  node.muted = muted;
  node.mute.hidden = !muted;
}

function clear(): void {
  for (const node of nodes.values()) node.root.remove();
  nodes.clear();
  window.clearTimeout(staleTimer);
  staleTimer = 0;
  lastFrameAt = 0;
}

function armStaleCheck(): void {
  if (staleTimer !== 0) return;
  const check = (): void => {
    staleTimer = 0;
    if (nodes.size === 0) return;
    const remaining = STALE_MS - (performance.now() - lastFrameAt);
    if (remaining > 0) {
      staleTimer = window.setTimeout(check, remaining);
      return;
    }
    clear();
  };
  staleTimer = window.setTimeout(check, STALE_MS);
}
