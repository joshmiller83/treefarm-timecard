/**
 * STUB (device-b): deterministic dictation-wave heights. Keep the signature; make it pretty.
 * Same progress and seed always give the same heights, so scrubbing is deterministic.
 */
export function waveHeights(progress: number, seed = 7, bars = 24): number[] {
  return Array.from({ length: bars }, (_, i) => {
    const x = Math.sin((i + 1) * 12.9898 * seed + progress * 31.4) * 43758.5453;
    return 0.2 + 0.8 * (x - Math.floor(x));
  });
}
