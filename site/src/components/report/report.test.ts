import { describe, expect, it } from 'vitest';
import { BREAKS, DAY, SHIFT, SHIFT_NOTE, WEEK, WEEK_RANGE, fmtHM, weekTotals } from '../../data/ledger.ts';
import {
  RANGES,
  STORY_DATE,
  daysFor,
  fmtDate,
  monthGrid,
  paperRows,
  paperTotals,
  periodFor,
  preparedLine,
  rangeSlug,
} from './report.ts';

describe('the story date', () => {
  it('is the ledger’s Friday, October 16 (2026)', () => {
    expect(STORY_DATE.toISOString().slice(0, 10)).toBe('2026-10-16');
    const long = STORY_DATE.toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric', timeZone: 'UTC' });
    expect(long).toBe(DAY.date);
    expect(fmtDate(STORY_DATE)).toBe(DAY.short);
  });
});

describe('range chips', () => {
  it('are the four ranges, in order, with stable slugs', () => {
    expect(RANGES).toEqual(['This week', 'Last week', 'This month', 'Pick dates']);
    expect(RANGES.map(rangeSlug)).toEqual(['this-week', 'last-week', 'this-month', 'pick-dates']);
  });
});

describe('periods', () => {
  it('This week runs Monday through the story’s Friday, exactly the ledger’s WEEK_RANGE', () => {
    expect(periodFor('This week').label).toBe(WEEK_RANGE);
    expect(periodFor('This week').days).toBe(5);
  });

  it('Last week is the whole week before (Monday to Sunday)', () => {
    const p = periodFor('Last week');
    expect(p.label).toBe('Mon, Oct 5 – Sun, Oct 11');
    expect(p.days).toBe(7);
  });

  it('This month runs from the 1st through the story’s Friday', () => {
    const p = periodFor('This month');
    expect(p.label).toBe('Thu, Oct 1 – Fri, Oct 16');
    expect(p.days).toBe(16);
  });

  it('Pick dates defaults to the same five days the example picks', () => {
    expect(periodFor('Pick dates').label).toBe(WEEK_RANGE);
  });

  it('only has example shifts for the ranges that cover the ledger week', () => {
    expect(daysFor('This week')).toBe(WEEK);
    expect(daysFor('Pick dates')).toBe(WEEK);
    expect(daysFor('Last week')).toBeNull();
    expect(daysFor('This month')).toBeNull();
  });
});

describe('the calendar grid', () => {
  it('lays out October 2026 starting on a Thursday, Sunday first', () => {
    const weeks = monthGrid(2026, 9);
    expect(weeks).toHaveLength(5);
    expect(weeks[0]).toEqual([null, null, null, null, 1, 2, 3]);
    expect(weeks[2]).toEqual([11, 12, 13, 14, 15, 16, 17]);
    expect(weeks[4]).toEqual([25, 26, 27, 28, 29, 30, 31]);
    expect(weeks.flat().filter((d) => d !== null)).toHaveLength(31);
  });

  it('pads the last week with blanks', () => {
    // February 2026 starts on a Sunday and has 28 days: exactly four weeks.
    expect(monthGrid(2026, 1)).toHaveLength(4);
    // November 2026 starts on a Sunday and ends on a Monday.
    const nov = monthGrid(2026, 10);
    expect(nov.at(-1)).toEqual([29, 30, null, null, null, null, null]);
  });
});

describe('the paper rows', () => {
  const rows = paperRows(WEEK);

  it('has one row per day, Monday to Friday', () => {
    expect(rows.map((r) => r.key)).toEqual(['mon', 'tue', 'wed', 'thu', 'fri']);
    expect(rows.map((r) => r.date)).toEqual(['Mon, Oct 12', 'Tue, Oct 13', 'Wed, Oct 14', 'Thu, Oct 15', 'Fri, Oct 16']);
  });

  it('prints Friday from the ledger: 7:02 AM to 4:31 PM, 8:30 worked, 290 trees', () => {
    const fri = rows.at(-1)!;
    expect(fri.in.text).toBe('7:02 AM');
    expect(fri.out.text).toBe('4:31 PM');
    expect(fri.hours.text).toBe('8:30');
    expect(fri.trees.text).toBe('290');
    expect(fri.note).toBe(SHIFT_NOTE);
  });

  it('lists every break, in order, without AM/PM, and does not count them', () => {
    const fri = rows.at(-1)!;
    expect(fri.breaks.map((b) => `${b.reason} ${b.span}`)).toEqual([
      'Water 9:45–10:00',
      'Lunch 12:01–12:31',
      'Sharpening shears 2:30–2:44',
    ]);
    const breakMins = BREAKS.reduce((s, b) => s + (b.end - b.start), 0);
    expect(fri.hours.text).toBe(fmtHM((SHIFT.out - SHIFT.in - breakMins) * 60));
    // Wednesday had no breaks.
    expect(rows[2]!.breaks).toEqual([]);
  });

  it('gives machine-readable times for <time> elements', () => {
    const fri = rows.at(-1)!;
    expect(fri.in.iso).toBe('2026-10-16T07:02');
    expect(fri.out.iso).toBe('2026-10-16T16:31');
    expect(fri.hours.iso).toBe('PT8H30M');
    expect(fri.breaks[1]!.iso).toEqual(['2026-10-16T12:01', '2026-10-16T12:31']);
    expect(rows[0]!.in.iso).toBe('2026-10-12T07:05');
  });
});

describe('the totals', () => {
  it('read 39:55 hours · 1,347 trees and equal the ledger sums', () => {
    const t = paperTotals(WEEK);
    expect(t.label).toBe('39:55 hours · 1,347 trees');
    expect(t.label).toBe(weekTotals(WEEK).label);
    expect(t.hours).toBe('39:55');
    expect(t.trees).toBe('1,347');
    expect(t.days).toBe(5);
    expect(t.hoursIso).toBe('PT39H55M');
  });

  it('sum the printed rows, so the paper reconciles with itself', () => {
    const rows = paperRows(WEEK);
    const mins = rows.reduce((s, r) => {
      const [h, m] = r.hours.text.split(':').map(Number);
      return s + h! * 60 + m!;
    }, 0);
    expect(`${Math.floor(mins / 60)}:${String(mins % 60).padStart(2, '0')}`).toBe(paperTotals(WEEK).hours);
    expect(rows.reduce((s, r) => s + Number(r.trees.text), 0).toLocaleString('en-US')).toBe(paperTotals(WEEK).trees);
  });
});

describe('the prepared line', () => {
  it('says when the card was made: right after clock-out', () => {
    expect(preparedLine()).toBe('Prepared Fri, Oct 16 at 4:31 PM');
  });
});

describe('no pay, ever', () => {
  it('has no pay or currency anywhere in what the paper prints', () => {
    const text = JSON.stringify({ rows: paperRows(WEEK), totals: paperTotals(WEEK), prepared: preparedLine() });
    expect(text).not.toMatch(/\$|pay|rate|wage|USD/i);
  });
});
