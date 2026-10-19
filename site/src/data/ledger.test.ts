import { describe, expect, it } from 'vitest';
import {
  BEST_DAY,
  BREAKS,
  CREW_MARKS,
  EARLIER,
  EARLIER_COUNT,
  FIELD,
  FIELD_TREES,
  MARKS,
  MOMENTS,
  SHIFT,
  TEAM,
  WEEK,
  breakAt,
  breaksText,
  fieldShapedAt,
  fmtClock,
  fmtCount,
  fmtHM,
  fmtHMS,
  fmtPct,
  fmtPerTree,
  fmtSpokenDuration,
  fmtSpokenTime,
  fmtTime,
  hoursLeftAt,
  liveActivityAt,
  paceAt,
  perTreeAt,
  positionAt,
  rowsAt,
  stateAt,
  t,
  treesAt,
  weekTotals,
  workedAt,
} from './ledger.ts';

const H = 3600;
const M = 60;

describe('the shift adds up', () => {
  it('clocks in at 7:02 AM and out at 4:31 PM', () => {
    expect(SHIFT.in).toBe(422);
    expect(SHIFT.out).toBe(991);
    expect(fmtTime(SHIFT.in)).toBe('7:02 AM');
    expect(fmtTime(SHIFT.out)).toBe('4:31 PM');
  });

  it('has 59 minutes of breaks: water, lunch and sharpening shears', () => {
    const total = BREAKS.reduce((s, b) => s + (b.end - b.start), 0);
    expect(total).toBe(59);
    expect(BREAKS.map((b) => b.reason)).toEqual(['Water', 'Lunch', 'Sharpening shears']);
    expect(breaksText(BREAKS)).toBe('Water 9:45–10:00; Lunch 12:01–12:31; Sharpening shears 2:30–2:44');
  });

  it('7:02 to 4:31 minus 59 minutes is 8 hours 30 minutes worked', () => {
    expect(SHIFT.out - SHIFT.in - 59).toBe(8 * 60 + 30);
    expect(workedAt(SHIFT.out)).toBe(8 * H + 30 * M);
    expect(fmtHMS(workedAt(SHIFT.out))).toBe('8:30:00');
    expect(fmtSpokenDuration(workedAt(SHIFT.out))).toBe('8 hours 30 minutes');
  });

  it('matches every worked time the brief lists', () => {
    const cases: Array<[number, string]> = [
      [t(7, 2), '0:00:00'],
      [t(7, 19), '0:17:00'],
      [t(12, 1), '4:44:00'],
      [t(12, 31), '4:44:00'],
      [t(14, 1), '6:14:00'],
      [t(14, 14), '6:27:00'],
      [t(14, 16), '6:29:00'],
      [t(14, 30), '6:43:00'],
      [t(14, 36), '6:43:00'],
      [t(14, 44), '6:43:00'],
      [t(15, 0), '6:59:00'],
      [t(15, 40), '7:39:00'],
      [t(16, 31), '8:30:00'],
    ];
    for (const [min, hms] of cases) expect(fmtHMS(workedAt(min)), `worked at ${fmtTime(min)}`).toBe(hms);
  });

  it('freezes worked time on a break and counts the break instead', () => {
    expect(workedAt(t(14, 30))).toBe(workedAt(t(14, 43.5)));
    expect(breakAt(t(14, 33))?.seconds).toBe(3 * M);
    expect(breakAt(t(14, 33))?.reason).toBe('Sharpening shears');
    expect(breakAt(t(12, 31) - 0.001)?.seconds).toBeCloseTo(30 * M - 0.06, 1);
    expect(breakAt(t(12, 1))?.kind).toBe('lunch');
    expect(breakAt(t(13, 0))).toBeNull();
  });

  it('works in fractional minutes so a scrubbed clock moves smoothly', () => {
    expect(workedAt(t(7, 2) + 0.5)).toBe(30);
    expect(workedAt(SHIFT.in - 10)).toBe(0);
    expect(workedAt(SHIFT.out + 30)).toBe(workedAt(SHIFT.out));
  });
});

describe('the trees add up', () => {
  it('lays out 14 blocks of 61 rows of 10 trees: 8,540 trees', () => {
    expect(FIELD.blocks).toBe(FIELD.gridRows * FIELD.blocksPerGridRow);
    expect(FIELD.blocks * FIELD.rowsPerBlock * FIELD.treesPerRow).toBe(8540);
    expect(FIELD_TREES).toBe(8540);
    expect(fmtCount(FIELD_TREES)).toBe('8,540');
  });

  it('has 2,190 trees shaped earlier this season', () => {
    const counted = EARLIER.reduce((s, r) => s + (r.to - r.from + 1) * FIELD.treesPerRow, 0);
    expect(counted).toBe(2190);
    expect(EARLIER_COUNT).toBe(2190);
  });

  it('marks 290 trees: block 2 rows 14–41 plus block 3 row 11', () => {
    const counted = MARKS.filter((m) => !m.rejected);
    expect(counted.reduce((s, m) => s + m.trees, 0)).toBe(290);
    const b2 = new Set(counted.filter((m) => m.block === 2).map((m) => m.row));
    expect([...b2].sort((a, b) => a - b)).toEqual(Array.from({ length: 28 }, (_, i) => 14 + i));
    expect(counted.filter((m) => m.block === 3).map((m) => m.row)).toEqual([11]);
    expect(EARLIER_COUNT + 290).toBe(2480);
  });

  it('matches every tree count the brief lists', () => {
    const cases: Array<[number, number]> = [
      [t(7, 2), 0],
      [t(7, 18), 0],
      [t(7, 19), 10],
      [t(12, 1), 160],
      [t(14, 1), 212],
      [t(14, 14), 220],
      [t(14, 15), 230],
      [t(15, 0), 240],
      [t(15, 40), 260],
      [t(16, 31), 290],
    ];
    for (const [min, n] of cases) expect(treesAt(min), `trees at ${fmtTime(min)}`).toBe(n);
  });

  it('has 212 trees at 2:01 PM on block 2, row 35', () => {
    expect(treesAt(t(14, 1))).toBe(212);
    expect(positionAt(t(14, 1))).toEqual({ block: 2, row: 35 });
  });

  it('puts the right rows on the Live Activity buttons', () => {
    expect(rowsAt(t(7, 2))).toEqual([14, 15, 16]);
    expect(rowsAt(t(7, 18))).toEqual([14, 15, 16]);
    expect(rowsAt(t(7, 19))).toEqual([15, 16, 17]);
    expect(rowsAt(t(12, 31))).toEqual([30, 31, 32]);
    expect(rowsAt(t(14, 14))).toEqual([36, 37, 38]);
    expect(rowsAt(MOMENTS.tapped)).toEqual([37, 38, 39]);
    expect(rowsAt(t(14, 44))).toEqual([37, 38, 39]);
    expect(rowsAt(t(15, 40))).toEqual([39, 40, 41]);
    expect(rowsAt(t(16, 31))).toEqual([42, 43, 44]);
  });

  it('counts everyone’s marks on the field bar', () => {
    expect(fieldShapedAt(t(7, 2))).toBe(2190);
    expect(fmtPct(fieldShapedAt(t(7, 2)) / FIELD_TREES)).toBe('26%');
    expect(fieldShapedAt(t(14, 14))).toBe(2410);
    expect(fieldShapedAt(t(14, 15))).toBe(2420);
    expect((fieldShapedAt(t(14, 14)) / FIELD_TREES).toFixed(3)).toBe('0.282');
    expect((fieldShapedAt(t(14, 15)) / FIELD_TREES).toFixed(3)).toBe('0.283');
    // Sam's row 12 in block 3 at 2:49 counts too (decisions.md #4).
    expect(CREW_MARKS).toEqual([expect.objectContaining({ block: 3, row: 12, by: 'Sam', at: t(14, 49) })]);
    expect(fieldShapedAt(t(16, 31))).toBe(2480 + 10);
    expect(fmtPct(fieldShapedAt(t(16, 31)) / FIELD_TREES)).toBe('29%');
  });

  it('keeps first-mark-wins: Sam’s row 12 comes before Alex’s', () => {
    const alexRow12 = MARKS.find((m) => m.block === 3 && m.row === 12);
    const samRow12 = CREW_MARKS.find((m) => m.block === 3 && m.row === 12);
    expect(alexRow12?.rejected).toBe(true);
    expect(samRow12!.at).toBeLessThan(alexRow12!.at);
    expect(MOMENTS.samMarks).toBeLessThan(MOMENTS.alexRow12);
  });
});

describe('pace adds up', () => {
  it('212 trees in 6.233 hours rounds to 34 an hour', () => {
    expect(Math.round(212 / (374 / 60))).toBe(34);
    expect(paceAt(t(14, 1))).toBe(34);
  });

  it('is 34 an hour at 3:40 PM and at clock-out', () => {
    expect(paceAt(t(15, 40))).toBe(34);
    expect(paceAt(t(16, 31))).toBe(34);
  });

  it('459 minutes for 260 trees is 1:46 a tree', () => {
    expect(workedAt(t(15, 40))).toBe(459 * M);
    expect(fmtPerTree(perTreeAt(t(15, 40)))).toBe('1:46');
  });

  it('leaves about 179 hours in North field at 34 an hour', () => {
    expect(Math.round((8540 - 2450) / 34)).toBe(179);
    expect(hoursLeftAt(t(15, 40))).toBe(179);
  });
});

describe('the week adds up', () => {
  it('has five days that each reconcile', () => {
    const expected = [
      ['Mon, Oct 12', '7:05 AM', '4:12 PM', 281, '8:37'],
      ['Tue, Oct 13', '7:00 AM', '3:48 PM', 276, '8:18'],
      ['Wed, Oct 14', '7:30 AM', '1:15 PM', 182, '5:45'],
      ['Thu, Oct 15', '7:00 AM', '4:30 PM', 318, '8:45'],
      ['Fri, Oct 16', '7:02 AM', '4:31 PM', 290, '8:30'],
    ];
    expect(WEEK.map((d) => [d.date, fmtTime(d.in), fmtTime(d.out), d.trees, fmtHM(d.worked)])).toEqual(expected);
    for (const d of WEEK) {
      const breaks = d.breaks.reduce((s, b) => s + (b.end - b.start), 0);
      expect(d.worked).toBe((d.out - d.in - breaks) * M);
    }
  });

  it('totals 39:55 hours and 1,347 trees', () => {
    const tot = weekTotals();
    expect(fmtHM(tot.worked)).toBe('39:55');
    expect(fmtCount(tot.trees)).toBe('1,347');
    expect(tot.label).toBe('39:55 hours · 1,347 trees');
  });

  it('has Thursday, Oct 15 as the best day with 318 trees', () => {
    expect(BEST_DAY.date).toBe('Thu, Oct 15');
    expect(BEST_DAY.trees).toBe(318);
    expect(Math.max(...WEEK.map((d) => d.trees))).toBe(318);
  });

  it('keeps Friday’s note and Wednesday’s rain note', () => {
    expect(WEEK[4]!.note).toBe('Rows past 30 are tall. Slower going.');
    expect(WEEK[2]!.note).toBe('Rain after 1.');
    expect(breaksText(WEEK[3]!.breaks)).toBe('Lunch 12:10–12:40; Water 2:15–2:30');
  });

  it('team hours through Friday 3:00 PM reconcile for Alex', () => {
    const alex = TEAM.find((p) => p.name === 'Alex')!;
    const monThu = WEEK.slice(0, 4);
    const worked = monThu.reduce((s, d) => s + d.worked, 0) + workedAt(t(15, 0));
    const trees = monThu.reduce((s, d) => s + d.trees, 0) + treesAt(t(15, 0));
    expect(fmtHM(worked)).toBe('38:24');
    expect(trees).toBe(1297);
    expect(alex.hours).toBe('38:24');
    expect(alex.trees).toBe(1297);
    expect(TEAM.map((p) => [p.name, p.hours, fmtCount(p.trees)])).toEqual([
      ['Alex', '38:24', '1,297'],
      ['Sam', '36:50', '1,214'],
      ['Rosa', '31:15', '1,046'],
    ]);
  });
});

describe('formatting', () => {
  it('formats the status bar like iOS: 12-hour, no AM/PM', () => {
    expect(fmtClock(t(7, 2))).toBe('7:02');
    expect(fmtClock(t(12, 1))).toBe('12:01');
    expect(fmtClock(t(14, 14))).toBe('2:14');
    expect(fmtClock(t(16, 31) + 0.99)).toBe('4:31');
    expect(fmtClock(t(0, 5))).toBe('12:05');
  });

  it('speaks times without AM/PM from 6:00 AM to 5:59 PM', () => {
    expect(fmtSpokenTime(t(7, 2))).toBe('7:02');
    expect(fmtSpokenTime(t(16, 31))).toBe('4:31');
    expect(fmtSpokenTime(t(17, 59))).toBe('5:59');
    expect(fmtSpokenTime(t(18, 0))).toBe('6:00 PM');
    expect(fmtSpokenTime(t(5, 59))).toBe('5:59 AM');
  });

  it('formats durations', () => {
    expect(fmtHMS(0)).toBe('0:00:00');
    expect(fmtHMS(6 * H + 29 * M + 10)).toBe('6:29:10');
    expect(fmtHMS(59.9)).toBe('0:00:59');
    expect(fmtHM(39 * H + 55 * M)).toBe('39:55');
    expect(fmtSpokenDuration(30 * M)).toBe('30 minutes');
    expect(fmtSpokenDuration(H)).toBe('1 hour');
    expect(fmtSpokenDuration(H + M)).toBe('1 hour 1 minute');
  });
});

describe('screen states', () => {
  it('describes the Live Activity at 2:14 PM before and after the tap', () => {
    expect(liveActivityAt(t(14, 14))).toEqual({
      state: 'working',
      pill: 'On the clock',
      worked: '6:27:00',
      breakTime: '0:00:00',
      breakReason: null,
      trees: 220,
      field: 'North field',
      block: 'Block 2',
      fieldPct: 2410 / 8540,
      rows: [36, 37, 38],
      nextRow: 39,
      undoRow: null,
    });
    const tapped = liveActivityAt(MOMENTS.tapped);
    expect(tapped.state).toBe('tapped');
    expect(tapped.trees).toBe(230);
    expect(tapped.rows).toEqual([37, 38, 39]);
    expect(tapped.undoRow).toBe(36);
  });

  it('describes lunch and the sharpening-shears break', () => {
    const lunch = liveActivityAt(t(12, 1));
    expect(lunch.state).toBe('lunch');
    expect(lunch.pill).toBe('On lunch');
    expect(lunch.worked).toBe('4:44:00');
    expect(lunch.breakTime).toBe('0:00:00');
    const brk = liveActivityAt(t(14, 30));
    expect(brk.state).toBe('break');
    expect(brk.pill).toBe('On break · Sharpening shears');
    expect(brk.worked).toBe('6:43:00');
    expect(liveActivityAt(t(14, 33)).breakTime).toBe('0:03:00');
  });

  it('has a state for every minute of the shift', () => {
    for (let m = SHIFT.in; m <= SHIFT.out; m += 1) {
      const s = stateAt(m);
      expect(s.worked).toBeGreaterThanOrEqual(0);
      expect(s.trees).toBeGreaterThanOrEqual(0);
      expect(s.rows).toHaveLength(3);
    }
  });
});
