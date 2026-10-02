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
