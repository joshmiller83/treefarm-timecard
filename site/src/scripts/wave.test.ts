import { describe, expect, it } from 'vitest';
import { WAVE_MIN, setWave, waveHeights } from './wave';

describe('waveHeights', () => {
  it('returns one height per bar (24 by default)', () => {
    expect(waveHeights(0.5)).toHaveLength(24);
    expect(waveHeights(0.5, 7, 9)).toHaveLength(9);
    expect(waveHeights(0.5, 7, 0)).toEqual([]);
  });

  it('is deterministic: the same progress and seed give the same heights', () => {
    for (const p of [0, 0.013, 0.25, 0.5, 0.731, 0.99, 1]) {
      expect(waveHeights(p, 7, 24)).toEqual(waveHeights(p, 7, 24));
    }
  });

  it('keeps every height between WAVE_MIN and 1', () => {
    for (let i = 0; i <= 400; i += 1) {
      for (const h of waveHeights(i / 400, 7, 24)) {
        expect(h).toBeGreaterThanOrEqual(WAVE_MIN);
        expect(h).toBeLessThanOrEqual(1);
      }
    }
    expect(WAVE_MIN).toBeGreaterThan(0);
    expect(WAVE_MIN).toBeLessThan(0.2);
  });

  it('is silent (a flat row of dots) at progress 0 and 1', () => {
    expect(waveHeights(0).every((h) => h === WAVE_MIN)).toBe(true);
    expect(waveHeights(1).every((h) => h === WAVE_MIN)).toBe(true);
  });

  it('clamps progress outside 0–1 and treats NaN as 0', () => {
    expect(waveHeights(-2)).toEqual(waveHeights(0));
    expect(waveHeights(3)).toEqual(waveHeights(1));
    expect(waveHeights(Number.NaN)).toEqual(waveHeights(0));
  });

  it('looks like speech mid-sentence: tall and short bars together', () => {
    let tallest = 0;
    let shortest = 1;
    for (let i = 10; i <= 90; i += 1) {
      const hs = waveHeights(i / 100);
      tallest = Math.max(tallest, ...hs);
      shortest = Math.min(shortest, ...hs);
    }
    expect(tallest).toBeGreaterThan(0.75);
    expect(shortest).toBeLessThan(0.3);
    // A loud frame is spiky like a level meter, not a solid block.
    const frames = Array.from({ length: 81 }, (_, i) => waveHeights((i + 10) / 100));
    const mean = (hs: number[]) => hs.reduce((a, b) => a + b, 0) / hs.length;
    const loudest = frames.reduce((a, b) => (mean(b) > mean(a) ? b : a));
    expect(Math.max(...loudest) - Math.min(...loudest)).toBeGreaterThan(0.4);
    // And it has quiet moments between words.
    expect(frames.some((hs) => Math.max(...hs) < 0.35)).toBe(true);
  });

  it('moves smoothly when scrubbed (no flicker between nearby progress values)', () => {
    for (let i = 0; i < 1000; i += 1) {
      const a = waveHeights(i / 1000);
      const b = waveHeights((i + 1) / 1000);
      for (let k = 0; k < a.length; k += 1) expect(Math.abs(a[k]! - b[k]!)).toBeLessThan(0.12);
    }
  });

  it('changes over time and with the seed', () => {
    expect(waveHeights(0.3)).not.toEqual(waveHeights(0.5));
    expect(waveHeights(0.5, 7)).not.toEqual(waveHeights(0.5, 8));
  });
});

describe('setWave', () => {
  const fakeWave = (bars: number, seed?: number) => {
    const els = Array.from({ length: bars }, () => ({ style: { transform: '' } }));
    const root = {
      dataset: seed === undefined ? {} : { seed: String(seed) },
      querySelectorAll: (sel: string) => (sel === '[data-wave-bar]' ? els : []),
    };
    return { root: root as unknown as HTMLElement, els };
  };

  it('writes scaleY transforms from waveHeights using the root’s seed', () => {
    const { root, els } = fakeWave(24, 7);
    setWave(root, 0.5);
    const want = waveHeights(0.5, 7, 24);
    els.forEach((el, i) => expect(el.style.transform).toBe(`scaleY(${want[i]!.toFixed(3)})`));
  });

  it('defaults the seed to 7 and sizes to the bars it finds', () => {
    const { root, els } = fakeWave(10);
    setWave(root, 0.42);
    const want = waveHeights(0.42, 7, 10);
    els.forEach((el, i) => expect(el.style.transform).toBe(`scaleY(${want[i]!.toFixed(3)})`));
  });

  it('does nothing without a root', () => {
    expect(() => setWave(null, 0.5)).not.toThrow();
  });
});
