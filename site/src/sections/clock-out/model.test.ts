import { describe, expect, it } from 'vitest';
import { MOMENTS, WEEK, fmtCount, fmtHM, fmtHMS, treesAt, workedAt } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { paperTotals } from '../../components/report/report.ts';
import { BEAT_AT, COPY, DESK, LABELS, MOB, TOTALS, TRANSCRIPT, lapse, lapseAt, type Window } from './model.ts';

const windows = (beats: Record<string, Window | number>) =>
  Object.entries(beats).filter((e): e is [string, Window] => Array.isArray(e[1]));

describe('clock-out transcript', () => {
  it('uses the app’s verified wording, with curly apostrophes (decisions.md #1)', () => {
    expect(TRANSCRIPT.map((l) => [l.who, l.text])).toEqual([
      ['you', 'Clock out with Time Card.'],
      ['siri', 'You’ve worked 8 hours 30 minutes today. Clock out?'],
      ['you', 'Yes.'],
      ['siri', 'Clocked out at 4:31. 8 hours 30 minutes, 290 trees.'],
    ]);
    expect(SIRI.clockOutAsk.verified && SIRI.clockOut.verified).toBe(true);
  });

  it('reads its numbers from the ledger', () => {
    expect(fmtHMS(workedAt(MOMENTS.clockOut))).toBe('8:30:00');
    expect(treesAt(MOMENTS.clockOut)).toBe(290);
    expect(TRANSCRIPT[3]!.text).toContain(`${treesAt(MOMENTS.clockOut)} trees`);
  });
});

describe('the 3:40 → 4:31 time-lapse', () => {
  const l = lapse();

  it('runs from the pace chapter to clock-out', () => {
    expect(l.from).toBe(MOMENTS.pace);
    expect(l.to).toBe(MOMENTS.clockOut);
  });

  it('spins the timer 7:39 → 8:30 and rolls the trees 260 → 290 (brief)', () => {
    expect(l.worked).toEqual(['7:39:00', '8:30:00']);
    expect(l.trees).toEqual([260, 290]);
  });

  it('advances the row strip from rows 39–41 to rows 42–44', () => {
    expect(l.rows[0]).toEqual([39, 40, 41]);
    expect(l.rows[1]).toEqual([42, 43, 44]);
  });

  it('fills the field bar to the 29% the brief shows at 4:31', () => {
    expect(Math.round(l.fieldPct[1] * 100)).toBe(29);
    expect(l.fieldPct[0]).toBeLessThan(l.fieldPct[1]);
  });

  it('steps once per mark, in order, inside the lapse', () => {
    expect(l.steps.map((s) => s.row)).toEqual([39, 40, 41]);
    expect(l.steps.map((s) => s.trees)).toEqual([270, 280, 290]);
    for (let i = 0; i < l.steps.length; i += 1) {
      const s = l.steps[i]!;
      expect(s.t).toBeGreaterThan(0);
      expect(s.t).toBeLessThan(1);
      if (i > 0) expect(s.t).toBeGreaterThan(l.steps[i - 1]!.t);
    }
  });

  it('maps a lapse fraction onto a progress window', () => {
    expect(lapseAt([0, 0.08], 0)).toBe(0);
    expect(lapseAt([0, 0.08], 1)).toBeCloseTo(0.08);
    expect(lapseAt([0.1, 0.2], 0.5)).toBeCloseTo(0.15);
  });
});

describe('scene timing', () => {
  it('desktop keeps the brief’s windows for the exchange and the lights-up', () => {
    expect(DESK.lapse).toEqual([0, 0.08]);
    expect(DESK.karaoke[0]).toBe(0.08);
    expect(DESK.ask[1]).toBeLessThanOrEqual(0.2);
    expect(DESK.yes).toEqual([0.2, 0.24]);
    expect(DESK.answer).toEqual([0.24, 0.3]);
    // The Live Activity leaves as the answer appears (the app ends it at clock-out).
    expect(DESK.dismiss).toEqual([0.24, 0.3]);
    expect(DESK.lights).toEqual([0.36, 0.44]);
    expect(DESK.theme).toBe(0.4);
    expect(DESK.unlock).toEqual([0.44, 0.52]);
    expect(DESK.exports[1]).toBeLessThanOrEqual(0.9);
    expect(DESK.rest[0]).toBeGreaterThanOrEqual(0.9);
  });

  it('desktop holds the report copy for at least 0.12 of progress before the paper takes its place', () => {
    expect(DESK.copyIn[0]).toBeGreaterThanOrEqual(DESK.theme);
    expect(DESK.copyOut[0] - DESK.copyIn[1]).toBeGreaterThanOrEqual(0.12 - 1e-9);
    // The copy is still up while the phone unlocks and taps This week.
    expect(DESK.copyOut[0]).toBeGreaterThanOrEqual(DESK.unlock[1]);
    expect(DESK.lift[0]).toBeGreaterThanOrEqual(DESK.copyOut[0]);
  });

  it('desktop: the paper lifts, prints, totals, is annotated and exports, in that order', () => {
    const order = ['lift', 'print', 'totals', 'annotate', 'exports', 'rest'] as const;
    for (let i = 1; i < order.length; i += 1) {
      expect(DESK[order[i]!][0]).toBeGreaterThanOrEqual(DESK[order[i - 1]!][1] - 1e-9);
    }
  });

  for (const [name, beats] of [
    ['desktop', DESK],
    ['mobile', MOB],
  ] as const) {
    it(`${name}: every window sits inside 0–1 and runs forwards`, () => {
      for (const [, [a, b]] of windows(beats)) {
        expect(a).toBeGreaterThanOrEqual(0);
        expect(b).toBeLessThanOrEqual(1);
        expect(b).toBeGreaterThan(a);
      }
    });

    it(`${name}: the story plays in order`, () => {
      const order = ['lapse', 'ask', 'yes', 'answer', 'quiet'] as const;
      for (let i = 1; i < order.length; i += 1) {
        expect(beats[order[i]!][0]).toBeGreaterThanOrEqual(beats[order[i - 1]!][1] - 1e-9);
      }
      // The Live Activity leaves once you have said yes, by the time Siri's card goes.
      expect(beats.dismiss[0]).toBeGreaterThanOrEqual(beats.yes[1] - 1e-9);
      expect(beats.dismiss[1]).toBeLessThanOrEqual(beats.quiet[0] + 1e-9);
      expect(beats.theme).toBeGreaterThan(beats.lights[0]);
      expect(beats.theme).toBeLessThan(beats.lights[1]);
      expect(beats.lights[0]).toBeGreaterThanOrEqual(beats.dismiss[1]);
    });

    it(`${name}: the gold rule sweeps under the stopped timer after the yes, before the dismiss`, () => {
      expect(beats.underline[0]).toBeGreaterThanOrEqual(beats.yes[0]);
      expect(beats.underline[1]).toBeLessThanOrEqual(beats.dismiss[0] + 1e-9);
    });

    it(`${name}: the Live Activity hands over to the question layer when the lapse ends, before Siri`, () => {
      expect(beats.glow[0]).toBeGreaterThanOrEqual(beats.lapse[1]);
    });
  }

  it('desktop: the quiet lock screen shows before the unlock', () => {
    expect(DESK.quiet[1]).toBeLessThanOrEqual(DESK.unlock[0]);
  });
});

/**
 * The mobile cards against the sticky phone, measured at 375 × 812 (Pixel 7 emulation): the
 * track scrolls 1462 px over progress 0–1; a card is centered at 82svh (666 px) when the
 * progress equals its --at-m; the phone's snippet spans y 142–217 and its Live Activity
 * 400–476 (the timer 416–437). The Playwright spec checks the same thing on the real page.
 */
describe('mobile cards and the sticky phone (375 × 812)', () => {
  const SCROLL = 1462;
  const ANCHOR = 666;
  const VIEW = 812;
  const SNIPPET: Window = [142, 217];
  const ACTIVITY: Window = [400, 476];
  const cards = [
    { at: BEAT_AT.askEx.mob, h: 191 },
    { at: BEAT_AT.yesEx.mob, h: 191 },
    { at: BEAT_AT.forgot.mob, h: 213 },
  ];
  const rect = (c: (typeof cards)[number], p: number): Window => {
    const mid = ANCHOR - (p - c.at) * SCROLL;
    return [mid - c.h / 2, mid + c.h / 2];
  };
  const overlaps = (a: Window, b: Window) => a[0] < b[1] && a[1] > b[0];
  const across = (w: Window, n = 24) => Array.from({ length: n + 1 }, (_, i) => w[0] + ((w[1] - w[0]) * i) / n);

  it('the cards never overlap each other', () => {
    for (let i = 1; i < cards.length; i += 1) {
      const gap = (cards[i]!.at - cards[i - 1]!.at) * SCROLL - (cards[i]!.h + cards[i - 1]!.h) / 2;
      expect(gap).toBeGreaterThanOrEqual(24);
    }
  });

  it('no card covers the Live Activity while the gold rule sweeps or the card dismisses', () => {
    for (const p of [...across(MOB.underline), ...across(MOB.dismiss)]) {
      for (const c of cards) expect(overlaps(rect(c, p), ACTIVITY), `card at ${c.at}, p ${p.toFixed(3)}`).toBe(false);
    }
  });

  it('no card covers the snippet while the question, the Yes tap and the answer play', () => {
    for (const p of [...across(MOB.ask), ...across(MOB.yes), ...across(MOB.answer)]) {
      for (const c of cards) expect(overlaps(rect(c, p), SNIPPET), `card at ${c.at}, p ${p.toFixed(3)}`).toBe(false);
    }
  });

  it('each card’s words light only once its top is above 85% of the viewport', () => {
    const top = (c: (typeof cards)[number], p: number) => rect(c, p)[0];
    expect(top(cards[0]!, MOB.karaoke[0])).toBeLessThanOrEqual(VIEW * 0.85);
    expect(top(cards[1]!, MOB.yes[0])).toBeLessThanOrEqual(VIEW * 0.85);
    // The answer's words light (from 20% into its window, as the phone types) with the whole card in view.
    expect(rect(cards[1]!, lapseAt(MOB.answer, 0.2))[1]).toBeLessThanOrEqual(VIEW);
  });
});

describe('the paper time card', () => {
  it('totals read 39:55 hours · 1,347 trees and equal the ledger sums', () => {
    const worked = WEEK.reduce((s, d) => s + d.worked, 0);
    const trees = WEEK.reduce((s, d) => s + d.trees, 0);
    expect(TOTALS.label).toBe('39:55 hours · 1,347 trees');
    expect(TOTALS.label).toBe(`${fmtHM(worked)} hours · ${fmtCount(trees)} trees`);
    expect(TOTALS).toEqual(paperTotals(WEEK));
  });
});

describe('truth rules', () => {
  const all = [...Object.values(COPY).flat(), ...Object.values(LABELS)].join('\n');

  it('never shows money, ratings or store badges', () => {
    expect(all).not.toMatch(/[$€£]|\bUSD\b|\bpaid\b|\bwage|App Store|Google Play|★|download/i);
  });

  it('says no pay, and never prints a pay figure', () => {
    expect(COPY.annotation).toBe('No pay on the report. Ever.');
    expect(all).not.toMatch(/\bpay\b.*\d/i);
  });

  it('uses curly quotes and apostrophes only', () => {
    expect(all).not.toMatch(/['"]/);
  });

  it('describes both phones for screen readers', () => {
    expect(LABELS.lock).toContain(SIRI.clockOut.reply);
    expect(LABELS.report).toContain('This week');
    expect(LABELS.report).toContain(TOTALS.hours);
    expect(LABELS.report).toContain(TOTALS.trees);
  });
});
