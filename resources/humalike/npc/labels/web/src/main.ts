import logoUrl from "./humalike.svg?url";
import { isLabelTuple, labelLayout, normalizeLanguage, presentationScale } from "./model.mjs";
import "./style.css";

type LabelTuple = [x: number, y: number, language: string | false, muted: 0 | 1];

const canvas = document.createElement("canvas");
canvas.id = "humalike-labels";
canvas.setAttribute("aria-hidden", "true");
document.body.append(canvas);

const context = requireCanvasContext();

const logo = new Image();
logo.src = logoUrl;

let labels: LabelTuple[] = [];
let configuredScale = 1;
let dirty = true;
let lastFrameAt = 0;
let staleCleared = true;
let width = 0;
let height = 0;
let pixelRatio = 1;
let drawScheduled = false;
let staleTimer = 0;

function resize(): void {
  const nextWidth = Math.max(1, window.innerWidth);
  const nextHeight = Math.max(1, window.innerHeight);
  const nextRatio = Math.min(window.devicePixelRatio || 1, 1.5);
  if (width === nextWidth && height === nextHeight && pixelRatio === nextRatio) return;
  width = nextWidth; height = nextHeight; pixelRatio = nextRatio;
  canvas.width = Math.round(width * pixelRatio);
  canvas.height = Math.round(height * pixelRatio);
  canvas.style.width = `${width}px`;
  canvas.style.height = `${height}px`;
  dirty = true;
}

window.addEventListener("resize", () => { resize(); scheduleDraw(); }, { passive: true });
window.addEventListener("message", ({ data }: MessageEvent<unknown>) => {
  if (!data || typeof data !== "object") return;
  const message = data as Record<string, unknown>;
  if (message.type === "labels:frame") {
    labels = Array.isArray(message.labels)
      ? message.labels.filter(isLabelTuple) as LabelTuple[]
      : [];
    configuredScale = typeof message.scale === "number" ? message.scale : 1;
    lastFrameAt = performance.now();
    staleCleared = false;
    dirty = true;
    scheduleDraw();
    armStaleCheck();
  } else if (message.type === "labels:clear" || message.type === "shutdown") {
    labels = [];
    dirty = true;
    window.clearTimeout(staleTimer);
    staleTimer = 0;
    scheduleDraw();
  }
});

logo.addEventListener("load", () => { dirty = true; scheduleDraw(); });
resize();
scheduleDraw();

function scheduleDraw(): void {
  if (drawScheduled) return;
  drawScheduled = true;
  requestAnimationFrame(() => {
    drawScheduled = false;
    resize();
    if (!dirty) return;
    draw();
    dirty = false;
    staleCleared = labels.length === 0;
  });
}

function armStaleCheck(): void {
  if (staleTimer !== 0) return;
  const check = (): void => {
    staleTimer = 0;
    if (labels.length === 0) return;
    const remaining = 250 - (performance.now() - lastFrameAt);
    if (remaining > 0) {
      staleTimer = window.setTimeout(check, remaining);
      return;
    }
    labels = [];
    dirty = true;
    scheduleDraw();
  };
  staleTimer = window.setTimeout(check, 250);
}

function draw(): void {
  context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
  context.clearRect(0, 0, width, height);
  if (labels.length === 0 && staleCleared) return;
  const scale = presentationScale(height, configuredScale);
  for (const label of labels) drawLabel(label, scale);
}

function drawLabel([normalizedX, normalizedY, rawLanguage, muted]: LabelTuple, scale: number): void {
  const language = rawLanguage === false ? null : normalizeLanguage(rawLanguage);
  const layout = labelLayout(language !== null, muted === 1, scale);
  const { iconSize, gap, flagWidth, textWidth, labelPadding, labelWidth, totalWidth } = layout;
  const left = normalizedX * width - totalWidth / 2;
  const top = normalizedY * height - iconSize - 4 * scale;

  context.save();
  context.fillStyle = "rgba(103, 203, 193, .14)";
  roundedRect(left - 2 * scale, top - 2 * scale, iconSize + 4 * scale, iconSize + 4 * scale, 9 * scale);
  context.fill();
  const gradient = context.createLinearGradient(left, top, left + iconSize, top + iconSize);
  gradient.addColorStop(0, "#67cbc1");
  gradient.addColorStop(1, "#3e8e86");
  context.fillStyle = gradient;
  roundedRect(left, top, iconSize, iconSize, 7 * scale);
  context.fill();
  context.strokeStyle = "#67cbc1";
  context.lineWidth = 1.5 * scale;
  context.stroke();
  if (logo.complete && logo.naturalWidth > 0) {
    const logoSize = 19 * scale;
    context.drawImage(logo, left + (iconSize - logoSize) / 2, top + (iconSize - logoSize) / 2, logoSize, logoSize);
  }

  const labelLeft = left + iconSize + gap;
  context.fillStyle = "rgba(0, 0, 0, .24)";
  oldLabelPath(labelLeft, top + 2 * scale, labelWidth, iconSize, 10 * scale);
  context.fill();
  context.fillStyle = "rgba(22, 25, 22, .68)";
  oldLabelPath(labelLeft, top, labelWidth, iconSize, 10 * scale);
  context.fill();
  context.strokeStyle = "rgba(103, 203, 193, .18)";
  context.lineWidth = .75 * scale;
  context.stroke();

  let cursor = labelLeft + labelPadding;
  context.font = `600 ${14 * scale}px Nunito, Arial, sans-serif`;
  context.textAlign = "left";
  context.textBaseline = "middle";
  context.fillStyle = "rgba(0, 0, 0, .55)";
  context.fillText("AI", cursor, top + 16 * scale);
  context.fillStyle = "#ffffff";
  context.fillText("AI", cursor, top + 15 * scale);
  cursor += textWidth;
  if (language) {
    cursor = labelLeft + layout.flagOffset;
    drawLanguage(language, cursor, top + 9 * scale, flagWidth, 12 * scale, scale);
  }
  if (muted) drawMuted(labelLeft + layout.muteOffset, top + 8 * scale, 14 * scale, scale);
  context.restore();
}

function drawLanguage(language: string, x: number, y: number, w: number, h: number, scale: number): void {
  context.save();
  roundedRect(x, y, w, h, 2 * scale);
  context.clip();
  if (language === "pl") {
    context.fillStyle = "#fff"; context.fillRect(x, y, w, h / 2);
    context.fillStyle = "#dc143c"; context.fillRect(x, y + h / 2, w, h / 2);
  } else if (language === "de") {
    context.fillStyle = "#171717"; context.fillRect(x, y, w, h / 3);
    context.fillStyle = "#dd1f2d"; context.fillRect(x, y + h / 3, w, h / 3);
    context.fillStyle = "#f4cc18"; context.fillRect(x, y + h * 2 / 3, w, h / 3);
  } else if (language === "es") {
    context.fillStyle = "#aa151b"; context.fillRect(x, y, w, h);
    context.fillStyle = "#f1bf00"; context.fillRect(x, y + h * .25, w, h * .5);
  } else if (language === "fr") {
    context.fillStyle = "#1a47b8"; context.fillRect(x, y, w / 3, h);
    context.fillStyle = "#fff"; context.fillRect(x + w / 3, y, w / 3, h);
    context.fillStyle = "#e8323c"; context.fillRect(x + w * 2 / 3, y, w / 3, h);
  } else if (language === "en") {
    drawUnitedKingdom(x, y, w, h);
  } else {
    context.fillStyle = "rgba(8, 20, 18, .82)"; context.fillRect(x, y, w, h);
    context.shadowColor = "transparent";
    context.fillStyle = "#eaf6f2";
    context.font = `800 ${7.5 * scale}px Arial, sans-serif`;
    context.textAlign = "center"; context.textBaseline = "middle";
    context.fillText(language, x + w / 2, y + h / 2 + .3 * scale);
  }
  context.restore();
  context.save();
  context.strokeStyle = "rgba(255,255,255,.48)";
  context.lineWidth = .65 * scale;
  roundedRect(x, y, w, h, 2 * scale);
  context.stroke();
  context.restore();
}

function drawUnitedKingdom(x: number, y: number, w: number, h: number): void {
  context.fillStyle = "#173f90"; context.fillRect(x, y, w, h);
  context.strokeStyle = "#fff"; context.lineWidth = h * .28;
  context.beginPath(); context.moveTo(x, y); context.lineTo(x + w, y + h); context.moveTo(x + w, y); context.lineTo(x, y + h); context.stroke();
  context.strokeStyle = "#d5273e"; context.lineWidth = h * .11; context.stroke();
  context.fillStyle = "#fff"; context.fillRect(x, y + h * .34, w, h * .32); context.fillRect(x + w * .39, y, w * .22, h);
  context.fillStyle = "#d5273e"; context.fillRect(x, y + h * .41, w, h * .18); context.fillRect(x + w * .44, y, w * .12, h);
}

function drawMuted(x: number, y: number, size: number, scale: number): void {
  context.strokeStyle = "#f2faf7";
  context.fillStyle = "#f2faf7";
  context.lineWidth = 1.5 * scale;
  context.lineCap = "round";
  context.beginPath();
  context.moveTo(x, y + size * .36); context.lineTo(x + size * .28, y + size * .36);
  context.lineTo(x + size * .58, y + size * .1); context.lineTo(x + size * .58, y + size * .9);
  context.lineTo(x + size * .28, y + size * .64); context.lineTo(x, y + size * .64); context.closePath(); context.fill();
  context.beginPath(); context.moveTo(x + size * .72, y + size * .28); context.lineTo(x + size, y + size * .72);
  context.moveTo(x + size, y + size * .28); context.lineTo(x + size * .72, y + size * .72); context.stroke();
}

function roundedRect(x: number, y: number, w: number, h: number, radius: number): void {
  context.beginPath();
  context.roundRect(x, y, w, h, radius);
}

function oldLabelPath(x: number, y: number, w: number, h: number, radius: number): void {
  context.beginPath();
  context.moveTo(x, y);
  context.lineTo(x + w - radius, y);
  context.quadraticCurveTo(x + w, y, x + w, y + radius);
  context.lineTo(x + w, y + h);
  context.lineTo(x + radius, y + h);
  context.quadraticCurveTo(x, y + h, x, y + h - radius);
  context.closePath();
}

function requireCanvasContext(): CanvasRenderingContext2D {
  const value = canvas.getContext("2d", { alpha: true });
  if (!value) throw new Error("2D canvas unavailable");
  return value;
}
