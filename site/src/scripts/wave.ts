/**
 * The dictation wave's bar heights: seeded value noise sampled at scroll progress, so the
 * same progress always draws the same wave and scrubbing backwards replays it exactly.
 *
 *   waveHeights(progress, seed?, bars?)  heights 0–1 (never below WAVE_MIN), one per bar
 *   setWave(waveEl, progress)            writes them as scaleY onto [data-wave-bar]s
 *
 * The shape reads as speech: loud and quiet syllables over time (a slow loudness curve),
 * bar-to-bar detail that drifts quickly but continuously, a gentle bump toward the middle
 * bars, and silence (a flat row of dots) at progress 0 and 1.
 */

/** The resting height of a bar (a dot), as a fraction of the full bar height. */
export const WAVE_MIN = 0.1;

/** How many "syllables" the loudness curve runs through between progress 0 and 1. */
const SYLLABLES = 22;
/** How fast the per-bar detail drifts (noise cells per unit of progress). */
const DRIFT = 46;

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
const smooth = (t: number) => t * t * (3 - 2 * t);
const smoothstep = (a: number, b: number, v: number) => smooth(clamp01((v - a) / (b - a)));

/** Integer hash → [0, 1). */
function hash(seed: number, x: number, y: number): number {
  let h = Math.imul(seed | 0, 0x27d4eb2d) ^ Math.imul(x | 0, 0x165667b1) ^ Math.imul(y | 0, 0x9e3779b1);
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

/** Smooth 2D value noise in [0, 1). */
function noise(seed: number, x: number, y: number): number {
  const x0 = Math.floor(x);
  const y0 = Math.floor(y);
  const tx = smooth(x - x0);
  const ty = smooth(y - y0);
  const a = hash(seed, x0, y0);
  const b = hash(seed, x0 + 1, y0);
  const c = hash(seed, x0, y0 + 1);
  const d = hash(seed, x0 + 1, y0 + 1);
  return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty;
}

export function waveHeights(progress: number, seed = 7, bars = 24): number[] {
  const p = Number.isFinite(progress) ? clamp01(progress) : 0;
  const n = Math.max(0, Math.floor(bars));
  // Silence at both ends, so the wave rests as dots before and after you speak.
  const fade = smoothstep(0, 0.07, p) * smoothstep(1, 0.93, p);
  // Loudness over time: syllables with short pauses between words.
  const t = p * SYLLABLES;
  const loud = smoothstep(0.18, 0.8, noise(seed, t, 0.5)) * 0.8 + 0.2 * noise(seed + 3, t * 2.3, 1.5);
  const out: number[] = [];
  for (let i = 0; i < n; i += 1) {
    const u = n > 1 ? i / (n - 1) : 0.5;
    // Middle bars a little taller, edges still alive.
    const env = 0.42 + 0.58 * Math.pow(Math.sin(Math.PI * (0.06 + 0.88 * u)), 0.9);
    // Bar-to-bar detail: two octaves, contrast-stretched so neighbours differ like a level meter.
    const detail = smoothstep(0.12, 0.88, 0.7 * noise(seed + 1, i * 0.9, p * DRIFT) + 0.3 * noise(seed + 2, i * 2.1, p * DRIFT * 1.7));
    const v = env * loud * (0.12 + 1.05 * detail) * 1.35 * fade;
    out.push(Math.round((WAVE_MIN + (1 - WAVE_MIN) * clamp01(v)) * 1000) / 1000);
  }
  return out;
}

/**
 * Applies waveHeights(progress) to a DictationWave: every [data-wave-bar] under `wave` gets
 * transform: scaleY(h). The seed comes from the wave's data-seed (default 7) and the bar count
 * from the bars it finds, so a scene only needs the element and a progress value.
 */
export function setWave(wave: HTMLElement | null | undefined, progress: number): void {
  if (!wave) return;
  const bars = Array.from(wave.querySelectorAll<HTMLElement>('[data-wave-bar]'));
  const seed = Number(wave.dataset.seed ?? 7);
  const hs = waveHeights(progress, Number.isFinite(seed) ? seed : 7, bars.length);
  bars.forEach((bar, i) => {
    bar.style.transform = `scaleY(${hs[i]!.toFixed(3)})`;
  });
}
