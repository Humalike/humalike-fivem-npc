export function hasAudibleSamples(samples, threshold = 0.003) {
  if (!samples || samples.length === 0 || !Number.isFinite(threshold) || threshold <= 0) return false;
  let energy = 0;
  for (const sample of samples) energy += sample * sample;
  return Math.sqrt(energy / samples.length) >= threshold;
}
