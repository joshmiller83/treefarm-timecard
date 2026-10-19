import { describe, expect, it } from 'vitest';
import { MOMENTS, fmtTime } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { heroPhoneLabel, spokenWords } from './copy.ts';
import {
  BANDS,
  INTRO,
  INTRO_END,
  MOBILE_SCALE,
  SCROLL,
  STARS,
  bandGround,
  bandHeight,
  bandTrees,
  cue,
  groundAt,
  introEnd,
} from './hero.ts';

describe('the phone label', () => {
  it('is the brief’s sentence, with the app’s real wording (curly apostrophe)', () => {
    expect(heroPhoneLabel()).toBe(
      'iPhone lock screen at 7:02 AM. Siri says: Clocked in at 7:02. You’re on block 2, row 14. ' +
        'The Time Card Live Activity shows On the clock, North field, Block 2, 0 trees this shift, ' +
        'and buttons for row 14, row 15, row 16 and Break.',
    );
  });

  it('comes from the ledger and the Siri lines, not typed by hand', () => {
    expect(heroPhoneLabel()).toContain(fmtTime(MOMENTS.clockIn));
    expect(heroPhoneLabel()).toContain(SIRI.clockIn.reply);
  });
});

describe('the spoken line', () => {
  it('splits “Clock in with Time Card.” into words, quotes on the first and last', () => {
    const words = spokenWords(SIRI.clockIn.said);
    expect(words.map((w) => w.text)).toEqual(['Clock', 'in', 'with', 'Time', 'Card.']);
    expect(words[0]!.open).toBe(true);
    expect(words.at(-1)!.close).toBe(true);
    expect(words.slice(1, -1).every((w) => !w.open && !w.close)).toBe(true);
  });

  it('keeps “Time Card” together so the app’s name never breaks', () => {
    const words = spokenWords(SIRI.clockIn.said);
    expect(words[3]!.glue).toBe(true);
  });
});

describe('the load sequence', () => {
  it('follows the brief’s cues, in seconds', () => {
    expect(INTRO.tint).toMatchObject({ at: 0, dur: 0.6 });
    expect(INTRO.bands).toMatchObject({ at: 0.1, dur: 0.9, stagger: 0.1 });
    expect(INTRO.copy).toMatchObject({ at: 0.35, dur: 0.5, stagger: 0.06 });
    expect(INTRO.phone).toMatchObject({ at: 0.3, dur: 0.9 });
    expect(INTRO.words).toMatchObject({ at: 0.9, stagger: 0.06 });
    expect(INTRO.glow).toMatchObject({ at: 1.3, dur: 0.4 });
    expect(INTRO.wake).toMatchObject({ at: 1.5, dur: 0.4 });
    expect(INTRO.snippet).toMatchObject({ at: 1.8, dur: 0.45 });
    expect(INTRO.siriOut).toMatchObject({ at: 2.5, dur: 0.3 });
    expect(INTRO.activity).toMatchObject({ at: 2.6, dur: 0.5 });
    expect(INTRO.buttons.stagger).toBe(0.05);
  });

  it('breathes the glow twice before Siri’s card leaves', () => {
    const b = INTRO.breathe;
    expect(b.at).toBe(INTRO.glow.at);
    // Two breaths: up and down twice, .6 s each.
    expect((b.repeat + 1) * b.dur).toBeCloseTo(1.2, 5);
    expect(b.at + (b.repeat + 1) * b.dur).toBeLessThanOrEqual(INTRO.siriOut.at + 1e-9);
  });

  it('finishes in 3.1 s or less (the acceptance bar), and at 70% on mobile', () => {
    expect(INTRO_END).toBeLessThanOrEqual(3.1 + 1e-9);
    expect(introEnd(1)).toBeCloseTo(INTRO_END, 9);
    expect(MOBILE_SCALE).toBe(0.7);
    expect(introEnd(MOBILE_SCALE)).toBeCloseTo(INTRO_END * 0.7, 9);
  });

  it('wakes the screen before Siri’s card drops, and the activity rises after it leaves', () => {
    expect(INTRO.wake.at).toBeLessThan(INTRO.snippet.at);
    expect(INTRO.snippet.at + INTRO.snippet.dur).toBeLessThanOrEqual(INTRO.siriOut.at);
    expect(INTRO.activity.at).toBeGreaterThanOrEqual(INTRO.siriOut.at);
  });

  it('scales every cue for mobile', () => {
    expect(cue(INTRO.activity, 0.7)).toEqual({ at: 2.6 * 0.7, dur: 0.5 * 0.7, stagger: 0 });
    expect(cue(INTRO.copy, 1)).toEqual({ at: 0.35, dur: 0.5, stagger: 0.06 });
  });
});

describe('the scroll scene', () => {
  it('uses the brief’s windows, inside 0–1', () => {
    expect(SCROLL.said).toEqual([0, 0.3]);
    expect(SCROLL.copy).toEqual([0.15, 0.6]);
    expect(SCROLL.bands).toEqual([0, 1]);
    expect(SCROLL.ribbon).toEqual([0.5, 0.7]);
    for (const [a, b] of Object.values(SCROLL)) {
      expect(a).toBeGreaterThanOrEqual(0);
      expect(b).toBeLessThanOrEqual(1);
      expect(b).toBeGreaterThan(a);
    }
  });

  it('sinks the near rows most (depth), 8vh at most on desktop', () => {
    const [far, mid, near] = BANDS;
    expect(near!.sink).toBe(8);
    expect(mid!.sink).toBeLessThan(near!.sink);
    expect(far!.sink).toBeLessThan(mid!.sink);
  });
});

describe('the fir bands', () => {
  it('bury the trunks of the distant rows, so they read as one line', () => {
    expect(BANDS.map((b) => b.plant)).toEqual([0.86, 0.86, 0.93]);
  });

  it('are the brief’s three bands: far, mid and near', () => {
    expect(BANDS.map((b) => [b.id, b.color, b.tree])).toEqual([
      ['far', '#173229', 42],
      ['mid', '#10261B', 72],
      ['near', '#0A1C13', 120],
    ]);
    expect(BANDS[0]!.opacity).toBe(0.6);
  });

  for (const band of BANDS) {
    describe(band.id, () => {
      const trees = bandTrees(band);
      const h = bandHeight(band);

      it('is deterministic', () => {
        expect(bandTrees(band)).toEqual(trees);
      });

      it('keeps trees near their nominal height, standing on the ground', () => {
        for (const t of trees) {
          expect(t.h).toBeGreaterThanOrEqual(band.tree * 0.78 - 1e-9);
          expect(t.h).toBeLessThanOrEqual(band.tree * 1.12 + 1e-9);
          expect(t.w).toBeCloseTo((t.h * 500) / 600, 6);
          expect(t.y).toBeGreaterThanOrEqual(0);
          expect(t.y + t.h).toBeLessThanOrEqual(h);
          // Planted: the ground meets the tree at band.plant of its height.
          const cx = t.x + t.w / 2;
          const g = groundAt(band, ((cx % band.tile) + band.tile) % band.tile);
          expect(t.y + t.h * band.plant).toBeCloseTo(g, 0);
        }
      });

      it('tiles without seams: a tree over an edge is drawn again one tile over', () => {
        for (const t of trees) {
          if (t.x < 0) expect(trees.some((u) => Math.abs(u.x - (t.x + band.tile)) < 1e-6 && u.h === t.h)).toBe(true);
          if (t.x + t.w > band.tile) expect(trees.some((u) => Math.abs(u.x - (t.x - band.tile)) < 1e-6 && u.h === t.h)).toBe(true);
        }
      });

      it('leaves no gaps wider than a tree along the row', () => {
        const xs = trees.map((t) => [t.x, t.x + t.w] as const).sort((a, b) => a[0] - b[0]);
        let reach = xs[0]![1];
        for (const [a, b] of xs.slice(1)) {
          expect(a - reach).toBeLessThan(band.tree * 0.6);
          reach = Math.max(reach, b);
        }
      });

      it('has a ground line that wraps around the tile', () => {
        const d = bandGround(band);
        expect(d.startsWith('M0 ')).toBe(true);
        expect(d.endsWith('Z')).toBe(true);
        const nums = d.match(/-?\d+(\.\d+)?/g)!.map(Number);
        expect(Math.max(...nums)).toBeLessThanOrEqual(Math.max(band.tile, h) + 1e-6);
      });
    });
  }
});

describe('the stars', () => {
  it('are four faint dots placed in percent', () => {
    expect(STARS).toHaveLength(4);
    for (const s of STARS) {
      for (const v of [s.x, s.y, s.mx, s.my]) {
        expect(v).toBeGreaterThan(0);
        expect(v).toBeLessThan(100);
      }
    }
  });
});
