/**
 * Report helpers for ReportTab and PaperTimeCard: the range chips, the period each range
 * covers, the date picker's month grid, and the rows and totals the paper prints.
 *
 * Every value comes from the ledger (src/data/ledger.ts). The ledger names the story's day
 * without a year; 2026 is the year October 16 falls on a Friday, and report.test.ts checks
 * that this date formats back to the ledger's DAY.
 *
 * Pay is never on the time card (TreeFarmKit's Report has no pay), so nothing here has it.
 */
import { DAY, SHIFT, WEEK, fmtClock, fmtCount, fmtHM, fmtTime, type Break, type Day, type Minute, type Seconds } from '../../data/ledger.ts';

export const RANGES = ['This week', 'Last week', 'This month', 'Pick dates'] as const;
export type ReportRange = (typeof RANGES)[number];

/** 'This week' → 'this-week' (the data-range-chip hook). */
export const rangeSlug = (r: ReportRange): string => r.toLowerCase().replace(/\s+/g, '-');

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const STORY_YEAR = 2026;

/** The story's Friday at UTC midnight (all date math here is in UTC, so time zones never shift a day). */
export const STORY_DATE: Date = (() => {
  const [monthName, dayNum] = DAY.monthDay.split(' ');
  const month = MONTHS.findIndex((m) => m.startsWith(monthName ?? ''));
  return new Date(Date.UTC(STORY_YEAR, month, Number(dayNum)));
})();

const DAY_MS = 86_400_000;
const addDays = (d: Date, n: number) => new Date(d.getTime() + n * DAY_MS);

/** 'Fri, Oct 16' */
export function fmtDate(d: Date): string {
  return d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', timeZone: 'UTC' });
}

/** 'October 2026' */
export function fmtMonth(d: Date): string {
  return d.toLocaleDateString('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });
}

/** Monday of the week holding `d` (the farm's week starts on Monday, like the ledger's week). */
function startOfWeek(d: Date): Date {
  const dow = (d.getUTCDay() + 6) % 7; // Monday = 0
  return addDays(d, -dow);
}

export interface Period {
  from: Date;
  to: Date;
  /** 'Mon, Oct 12 – Fri, Oct 16' */
  label: string;
  /** Calendar days covered, both ends included. */
  days: number;
}

const period = (from: Date, to: Date): Period => ({
  from,
  to,
  label: `${fmtDate(from)} – ${fmtDate(to)}`,
  days: Math.round((to.getTime() - from.getTime()) / DAY_MS) + 1,
});

/**
 * The span a range covers, through the story's Friday (a card can't include days that
 * haven't happened). 'Pick dates' defaults to the ledger week: the five days the example picks.
 */
export function periodFor(range: ReportRange, today: Date = STORY_DATE): Period {
  const monday = startOfWeek(today);
  switch (range) {
    case 'This week':
    case 'Pick dates':
      return period(monday, today);
    case 'Last week':
      return period(addDays(monday, -7), addDays(monday, -1));
    case 'This month':
      return period(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1)), today);
  }
}

/**
 * The example shifts a range covers, or null when the ledger has none for it (the story only
 * has the week of Oct 12). Screens show a preview that is still drawing instead of inventing numbers.
 */
export function daysFor(range: ReportRange): readonly Day[] | null {
  return range === 'This week' || range === 'Pick dates' ? WEEK : null;
}

/** Weeks of a month for a Sunday-first calendar (en-US), blanks as null. `month` is 0-based. */
export function monthGrid(year: number, month: number): Array<Array<number | null>> {
  const first = new Date(Date.UTC(year, month, 1));
  const count = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const cells: Array<number | null> = Array.from({ length: first.getUTCDay() }, () => null);
  for (let d = 1; d <= count; d += 1) cells.push(d);
  while (cells.length % 7) cells.push(null);
  const weeks: Array<Array<number | null>> = [];
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7));
  return weeks;
}

// ---------------------------------------------------------------------------
// What the paper prints

const pad2 = (n: number) => String(n).padStart(2, '0');

/** The calendar date of a ledger Day ('Mon, Oct 12'), from the story's Friday. */
function dateOf(day: Day): Date {
  const keys: Day['key'][] = ['mon', 'tue', 'wed', 'thu', 'fri'];
  return addDays(startOfWeek(STORY_DATE), keys.indexOf(day.key));
}

/** '2026-10-16T07:02' for <time datetime>. */
function isoAt(date: Date, min: Minute): string {
  const whole = Math.floor(min + 1e-6);
  return `${date.toISOString().slice(0, 10)}T${pad2(Math.floor(whole / 60))}:${pad2(whole % 60)}`;
}

/** 'PT8H30M' for <time datetime> on a duration. */
function isoDuration(seconds: Seconds): string {
  const m = Math.max(0, Math.floor(seconds / 60 + 1e-6));
  return `PT${Math.floor(m / 60)}H${m % 60}M`;
}

export interface PaperBreak {
  reason: string;
  /** '12:01–12:31' (no AM/PM, as the card lists breaks). */
  span: string;
  iso: [string, string];
}

export interface PaperRow {
  key: Day['key'];
  date: string;
  in: { text: string; iso: string };
  out: { text: string; iso: string };
  trees: { text: string };
  hours: { text: string; iso: string };
  breaks: PaperBreak[];
  note: string | null;
}

export function paperRows(days: readonly Day[]): PaperRow[] {
  return days.map((d) => {
    const date = dateOf(d);
    const breaks = [...d.breaks]
      .sort((a: Break, b: Break) => a.start - b.start)
      .map((b) => ({
        reason: b.reason,
        span: `${fmtClock(b.start)}–${fmtClock(b.end)}`,
        iso: [isoAt(date, b.start), isoAt(date, b.end)] as [string, string],
      }));
    return {
      key: d.key,
      date: d.date,
      in: { text: fmtTime(d.in), iso: isoAt(date, d.in) },
      out: { text: fmtTime(d.out), iso: isoAt(date, d.out) },
      trees: { text: fmtCount(d.trees) },
      hours: { text: fmtHM(d.worked), iso: isoDuration(d.worked) },
      breaks,
      note: d.note,
    };
  });
}

export interface PaperTotals {
  hours: string;
  hoursIso: string;
  trees: string;
  /** Distinct days worked. */
  days: number;
  /** '39:55 hours · 1,347 trees' */
  label: string;
}

export function paperTotals(days: readonly Day[]): PaperTotals {
  const worked = days.reduce((s, d) => s + d.worked, 0);
  const trees = days.reduce((s, d) => s + d.trees, 0);
  const hours = fmtHM(worked);
  return { hours, hoursIso: isoDuration(worked), trees: fmtCount(trees), days: new Set(days.map((d) => d.key)).size, label: `${hours} hours · ${fmtCount(trees)} trees` };
}

/** 'Prepared Fri, Oct 16 at 4:31 PM': the card is made right after clocking out. */
export function preparedLine(date: string = DAY.short, min: Minute = SHIFT.out): string {
  return `Prepared ${date} at ${fmtTime(min)}`;
}

/**
 * The prepared moment in parts, for `Prepared <time datetime="2026-10-16T16:31">Fri, Oct 16 at 4:31 PM</time>`:
 * { date: 'Fri, Oct 16', time: '4:31 PM', iso: '2026-10-16T16:31' }.
 */
export function preparedAt(min: Minute = SHIFT.out): { date: string; time: string; iso: string } {
  return { date: fmtDate(STORY_DATE), time: fmtTime(min), iso: isoAt(STORY_DATE, min) };
}
