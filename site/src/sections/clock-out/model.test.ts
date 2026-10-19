import { describe, expect, it } from 'vitest';
import { MOMENTS, WEEK, fmtCount, fmtHM, fmtHMS, treesAt, workedAt } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { paperTotals } from '../../components/report/report.ts';
import { COPY, DESK, LABELS, MOB, TOTALS, TRANSCRIPT, lapse, lapseAt, type Window } from './model.ts';

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
  it('desktop matches the brief’s progress windows', () => {
    expect(DESK.lapse).toEqual([0, 0.08]);
    expect(DESK.karaoke[0]).toBe(0.08);
    expect(DESK.ask[1]).toBeLessThanOrEqual(0.2);
    expect(DESK.yes).toEqual([0.2, 0.24]);
    expect(DESK.answer).toEqual([0.24, 0.3]);
    expect(DESK.dismiss).toEqual([0.3, 0.36]);
    expect(DESK.lights).toEqual([0.36, 0.44]);
    expect(DESK.theme).toBe(0.4);
    expect(DESK.unlock).toEqual([0.44, 0.52]);
    expect(DESK.lift[0]).toBe(0.52);
    expect(DESK.totals[1]).toBeLessThanOrEqual(0.76);
    expect(DESK.annotate[0]).toBeGreaterThanOrEqual(0.76);
    expect(DESK.exports[1]).toBeLessThanOrEqual(0.9);
    expect(DESK.rest[0]).toBeGreaterThanOrEqual(0.9);
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
      const order = ['lapse', 'ask', 'yes', 'answer', 'dismiss', 'lights'] as const;
      for (let i = 1; i < order.length; i += 1) {
        expect(beats[order[i]!][0]).toBeGreaterThanOrEqual(beats[order[i - 1]!][1] - 1e-9);
      }
      expect(beats.theme).toBeGreaterThan(beats.lights[0]);
      expect(beats.theme).toBeLessThan(beats.lights[1]);
    });
  }
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
