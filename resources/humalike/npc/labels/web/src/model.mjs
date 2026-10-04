const LANGUAGE_ALIASES = Object.freeze({
  pl: "pl", en: "en", de: "de", es: "es", fr: "fr",
});

/** @param {unknown} value */
export function normalizeLanguage(value) {
  if (typeof value !== "string") return null;
  const code = value.trim().toLowerCase().split(/[-_]/, 1)[0]?.replace(/[^a-z0-9]/g, "") ?? "";
  if (!code) return null;
  return LANGUAGE_ALIASES[/** @type {keyof typeof LANGUAGE_ALIASES} */ (code)] ?? code.slice(0, 3).toUpperCase();
}

/** @param {number} viewportHeight @param {number} configuredScale */
export function presentationScale(viewportHeight, configuredScale) {
  const resolutionScale = Math.max(0.9, Math.min(1.1, viewportHeight / 1080));
  const safeConfiguredScale = Number.isFinite(configuredScale)
    ? Math.max(0.65, Math.min(1.5, configuredScale))
    : 1;
  return resolutionScale * safeConfiguredScale;
}

/** @param {boolean} hasLanguage @param {boolean} muted @param {number} scale */
export function labelLayout(hasLanguage, muted, scale) {
  const iconSize = 30 * scale;
  const gap = 8 * scale;
  const flagWidth = hasLanguage ? 19 * scale : 0;
  const flagGap = hasLanguage ? 8 * scale : 0;
  const textWidth = 17 * scale;
  const muteGap = muted ? 7 * scale : 0;
  const muteWidth = muted ? 21 * scale : 0;
  const labelPadding = 11 * scale;
  const flagOffset = labelPadding + textWidth + flagGap;
  const muteOffset = labelPadding + textWidth
    + (hasLanguage ? flagGap + flagWidth : 0) + muteGap;
  const labelWidth = labelPadding * 2 + textWidth + flagGap + flagWidth + muteGap + muteWidth;
  return {
    iconSize, gap, flagWidth, flagGap, textWidth, muteGap, muteWidth,
    labelPadding, flagOffset, muteOffset, labelWidth,
    totalWidth: iconSize + gap + labelWidth,
  };
}

/** @param {unknown} value */
export function isLabelTuple(value) {
  return Array.isArray(value)
    && value.length >= 4
    && Number.isFinite(value[0])
    && Number.isFinite(value[1])
    && value[0] >= 0 && value[0] <= 1
    && value[1] >= 0 && value[1] <= 1
    && (value[2] === false || typeof value[2] === "string")
    && (value[3] === 0 || value[3] === 1)
    && (value[4] === undefined || typeof value[4] === "string");
}

// A label glides to each new position over one frame interval, so it would
// trail the head by that much. The glide is aimed one interval ahead along
// the label's own motion instead; the step is capped so a stop never overshoots far.
const PREDICT_FACTOR = 1.0;
const MAX_PREDICT_PX = 40;

/**
 * Where a label is drawn for a newly reported position. `node` holds the
 * position the game last reported (`x`, `y`) and when (`at`); both are updated.
 * @param {{ x: number, y: number, at: number }} node
 * @param {number} x @param {number} y reported position in pixels
 * @param {number} now @param {number} transitionMs @param {number} staleMs
 * @returns {[number, number, boolean]} the position to draw at, and whether it is ahead of the reported one
 */
export function aimLabel(node, x, y, now, transitionMs, staleMs) {
  let dx = 0;
  let dy = 0;
  const dt = now - node.at;
  if (node.at > 0 && dt > 0 && dt < staleMs) {
    dx = (x - node.x) / dt * transitionMs * PREDICT_FACTOR;
    dy = (y - node.y) / dt * transitionMs * PREDICT_FACTOR;
    const step = Math.hypot(dx, dy);
    if (step > MAX_PREDICT_PX) { dx *= MAX_PREDICT_PX / step; dy *= MAX_PREDICT_PX / step; }
  }
  node.x = x; node.y = y; node.at = now;
  return [x + dx, y + dy, dx !== 0 || dy !== 0];
}

/**
 * A label aimed ahead waits this long for the next frame. When none comes (the
 * camera and the NPC stopped, so the game has nothing new to say) it is put
 * back on the position the game last reported.
 * @param {number} transitionMs
 */
export function settleDelayMs(transitionMs) {
  return Math.round(transitionMs * 1.5);
}
