/**
 * THE LEDGER: the single source of every number on the page.
 *
 * One illustrative shift: Alex, a trimmer, on Friday, October 16, in "North field".
 * Every section, screen and Siri reply reads its numbers from here, and
 * ledger.test.ts checks that they reconcile (7:02 in, 4:31 out, 59 minutes of
 * breaks, 8 hours 30 minutes worked, 290 trees, 34 an hour).
 *
 * Times are MINUTES AFTER MIDNIGHT on the example day (422 = 7:02 AM). They may be
 * fractional, because the DayClock scrubs smoothly between ledger times.
 * Durations returned by helpers are SECONDS.
 *
 * This file imports nothing so Node can run it directly (astro.config's Siri check).
 */

export type Minute = number;
export type Seconds = number;

/** 24-hour clock to minutes after midnight: t(14, 14) = 854 (2:14 PM). */
export const t = (h: number, m: number): Minute => h * 60 + m;

// ---------------------------------------------------------------------------
// People, place and day

export const DAY = {
  weekday: 'Friday',
  /** Lock-screen date line. */
  date: 'Friday, October 16',
  short: 'Fri, Oct 16',
  monthDay: 'Oct 16',
} as const;

export const WORKER = 'Alex';
export const CREW = ['Sam', 'Rosa'] as const;
export const PEOPLE = [WORKER, ...CREW] as const;
export type Person = (typeof PEOPLE)[number];

export const FIELD = {
  name: 'North field',
  blocks: 14,
  /** Blocks are laid out in 2 grid rows of 7: blocks 1–7 on top, 8–14 below. */
  gridRows: 2,
  blocksPerGridRow: 7,
  rowsPerBlock: 61,
  treesPerRow: 10,
} as const;

export const FIELD_TREES = FIELD.blocks * FIELD.rowsPerBlock * FIELD.treesPerRow; // 8,540

export interface RowRange {
  block: number;
  /** First row, 1-based, inclusive. */
  from: number;
  /** Last row, inclusive. */
  to: number;
}

/** Shaped earlier this season, by anyone (green on every map): 2,190 trees. */
export const EARLIER: readonly RowRange[] = [
  { block: 1, from: 1, to: 61 },
  { block: 2, from: 1, to: 13 },
  { block: 3, from: 1, to: 10 },
  { block: 4, from: 1, to: 13 },
  { block: 8, from: 1, to: 61 },
  { block: 9, from: 1, to: 61 },
];

export const EARLIER_COUNT = EARLIER.reduce((s, r) => s + (r.to - r.from + 1) * FIELD.treesPerRow, 0);

/** Tree-note flags, exactly as the app names them. */
export const FLAGS = ['Needs attention', 'Dead', 'Replant'] as const;
export type Flag = (typeof FLAGS)[number];

export interface TreeNote {
  block: number;
  row: number;
  tree: number;
  flag: Flag;
  text: string;
  by: Person;
  /** How the note's byline reads in the app. */
  byline: string;
}

/** An older note that survives the season reset. */
export const OLD_NOTE: TreeNote = {
  block: 2,
  row: 31,
  tree: 4,
  flag: 'Replant',
  text: 'Lost its top in the wind.',
  by: 'Sam',
  byline: 'Sam · Oct 9',
};

/** Alex's note at 2:33 PM, made by voice on a break. */
export const TREE_NOTE: TreeNote = {
  block: 2,
  row: 36,
  tree: 7,
  flag: 'Needs attention',
  text: 'Leader’s broken. Needs a stake.',
  by: 'Alex',
  byline: 'Alex · Today 2:33 PM',
};

export const SHIFT_NOTE = 'Rows past 30 are tall. Slower going.';

// ---------------------------------------------------------------------------
// The shift

export const SHIFT = { in: t(7, 2), out: t(16, 31) } as const;

export type BreakKind = 'break' | 'lunch';
export interface Break {
  kind: BreakKind;
  reason: string;
  start: Minute;
  end: Minute;
}

export const BREAKS: readonly Break[] = [
  { kind: 'break', reason: 'Water', start: t(9, 45), end: t(10, 0) },
  { kind: 'lunch', reason: 'Lunch', start: t(12, 1), end: t(12, 31) },
  { kind: 'break', reason: 'Sharpening shears', start: t(14, 30), end: t(14, 44) },
];

export type MarkVia = 'siri' | 'lock-screen' | 'app';
export interface Mark {
  at: Minute;
  block: number;
  row: number;
  trees: number;
  by: Person;
  via: MarkVia;
  /** Made with no signal; synced at OFFLINE.back. */
  offline?: boolean;
  /** Someone else marked it first, so it does not count (first mark wins). */
  rejected?: boolean;
}

const b2 = (row: number, at: Minute, via: MarkVia = 'siri', trees = 10): Mark => ({
  at,
  block: 2,
  row,
  trees,
  by: 'Alex',
  via,
});

/** Alex's marks today, in order. Times between the brief's fixed points are illustrative. */
export const MARKS: readonly Mark[] = [
  b2(14, t(7, 19)),
  b2(15, t(7, 37)),
  b2(16, t(7, 55)),
  b2(17, t(8, 13)),
  b2(18, t(8, 31)),
  b2(19, t(8, 49)),
  b2(20, t(9, 7)),
  b2(21, t(9, 25)),
  b2(22, t(9, 43)),
  // Water 9:45–10:00
  b2(23, t(10, 17)),
  b2(24, t(10, 34)),
  b2(25, t(10, 51)),
  b2(26, t(11, 8)),
  b2(27, t(11, 25)),
  b2(28, t(11, 42)),
  b2(29, t(11, 59)),
  // Lunch 12:01–12:31
  b2(30, t(12, 48)),
  b2(31, t(13, 5)),
  b2(32, t(13, 22)),
  b2(33, t(13, 39)),
  b2(34, t(13, 56)),
  b2(35, t(14, 0), 'app', 2), // two trees of row 35 on the map: 212 at 2:01
  b2(35, t(14, 12), 'app', 8), // the rest of row 35: 220 at 2:14
  b2(36, t(14, 14) + 0.5, 'lock-screen'), // the tap on [Row 36]: 230
  // Sharpening shears 2:30–2:44, then Alex helps Sam finish block 3
  { at: t(14, 50), block: 3, row: 11, trees: 10, by: 'Alex', via: 'app', offline: true },
  { at: t(14, 56), block: 3, row: 12, trees: 10, by: 'Alex', via: 'app', offline: true, rejected: true },
  b2(37, t(15, 15)),
  b2(38, t(15, 33)),
  b2(39, t(15, 51)),
  b2(40, t(16, 9)),
  b2(41, t(16, 27)),
];

/** Marks by the rest of the crew that this story shows. */
export const CREW_MARKS: readonly Mark[] = [
  { at: t(14, 49), block: 3, row: 12, trees: 10, by: 'Sam', via: 'app' },
];

export const OFFLINE = { lost: t(14, 48), back: t(15, 0) } as const;
export const CONFLICT_MESSAGE = 'Row 12 was shaped by Sam on Oct 16.';

/** Named moments in the story, in minutes. Scenes tween the DayClock between these. */
export const MOMENTS = {
  clockIn: t(7, 2),
  misheard: t(7, 18),
  firstRow: t(7, 19),
  lunch: t(12, 1),
  back: t(12, 31),
  status: t(14, 1),
  lockScreen: t(14, 14),
  tapped: t(14, 14) + 0.5,
  field: t(14, 15),
  island: t(14, 16),
  break: t(14, 30),
  treeNote: t(14, 33),
  shiftNote: t(14, 36),
  backFromBreak: t(14, 44),
  crew: t(14, 47),
  offline: t(14, 48),
  samMarks: t(14, 49),
  alexRow11: t(14, 50),
  alexRow12: t(14, 56),
  synced: t(15, 0),
  pace: t(15, 40),
  clockOut: t(16, 31),
} as const;
export type MomentKey = keyof typeof MOMENTS;

// ---------------------------------------------------------------------------
// Pure helpers over the shift

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

/** The break running at `min`, if any. */
export function currentBreak(min: Minute, breaks: readonly Break[] = BREAKS): Break | null {
  return breaks.find((b) => min >= b.start && min < b.end) ?? null;
}

/** Seconds worked at `min`: clock-in to now, minus finished and running breaks. */
export function workedAt(min: Minute): Seconds {
  const now = clamp(min, SHIFT.in, SHIFT.out);
  let mins = now - SHIFT.in;
  for (const b of BREAKS) mins -= clamp(now, b.start, b.end) - b.start;
  return Math.round(mins * 60 * 1000) / 1000;
}

/** The running break at `min` and its seconds so far, or null when working. */
export function breakAt(min: Minute): { kind: BreakKind; reason: string; seconds: Seconds } | null {
  const b = currentBreak(min);
  if (!b) return null;
  return { kind: b.kind, reason: b.reason, seconds: Math.round((min - b.start) * 60 * 1000) / 1000 };
}

const counts = (m: Mark, min: Minute) => !m.rejected && m.at <= min;

/** Alex's trees at `min`. */
export function treesAt(min: Minute): number {
  return MARKS.reduce((s, m) => (counts(m, min) ? s + m.trees : s), 0);
}

/** Everyone's shaped trees in the field at `min` (the Live Activity's field bar). */
export function fieldShapedAt(min: Minute): number {
  const crew = CREW_MARKS.reduce((s, m) => (counts(m, min) ? s + m.trees : s), 0);
  return EARLIER_COUNT + treesAt(min) + crew;
}

export interface Position {
  block: number;
  row: number;
}

/** Where Alex is working at `min`: "You’re on block 2, row 35." */
export function positionAt(min: Minute): Position {
  // 2:47–3:00 PM: helping Sam finish block 3.
  if (min >= MOMENTS.crew && min < MOMENTS.synced) {
    const done = MARKS.filter((m) => m.block === 3 && m.at <= min).length;
    return { block: 3, row: 11 + done };
  }
  const full = new Map<number, number>();
  for (const m of MARKS) {
    if (m.block !== 2 || m.at > min) continue;
    full.set(m.row, (full.get(m.row) ?? 0) + m.trees);
  }
  let row = 14;
  while ((full.get(row) ?? 0) >= FIELD.treesPerRow) row += 1;
  return { block: 2, row };
}

/** The three row buttons on the Live Activity at `min`. */
export function rowsAt(min: Minute): [number, number, number] {
  const { row } = positionAt(min);
  return [row, row + 1, row + 2];
}

/** Trees an hour, rounded, at `min`. */
export function paceAt(min: Minute): number {
  const hours = workedAt(min) / 3600;
  return hours > 0 ? Math.round(treesAt(min) / hours) : 0;
}

/** Seconds a tree, rounded to the second, at `min`. */
export function perTreeAt(min: Minute): Seconds {
  const trees = treesAt(min);
  return trees > 0 ? Math.round(workedAt(min) / trees) : 0;
}

/** Hours of work left in North field at the current pace, rounded. */
export function hoursLeftAt(min: Minute): number {
  const pace = paceAt(min);
  return pace > 0 ? Math.round((FIELD_TREES - fieldShapedAt(min)) / pace) : 0;
}

// ---------------------------------------------------------------------------
// Formatting (every number on the page is set in Plex Mono with tabular figures)

const pad2 = (n: number) => String(n).padStart(2, '0');

/** h:mm:ss for timers: 6:27:00. Fractions of a second are dropped. */
export function fmtHMS(seconds: Seconds): string {
  const s = Math.max(0, Math.floor(seconds + 1e-6));
  return `${Math.floor(s / 3600)}:${pad2(Math.floor((s % 3600) / 60))}:${pad2(s % 60)}`;
}

/** h:mm for durations: 8:30, 39:55. */
export function fmtHM(seconds: Seconds): string {
  const m = Math.max(0, Math.floor(seconds / 60 + 1e-6));
  return `${Math.floor(m / 60)}:${pad2(m % 60)}`;
}

/** m:ss for time per tree: 1:46. */
export function fmtPerTree(seconds: Seconds): string {
  const s = Math.round(seconds);
  return `${Math.floor(s / 60)}:${pad2(s % 60)}`;
}

function hm12(min: Minute) {
  const whole = Math.floor(min + 1e-6);
  const h24 = Math.floor(whole / 60) % 24;
  const h = h24 % 12 === 0 ? 12 : h24 % 12;
  return { h, m: whole % 60, pm: h24 >= 12 };
}

/** iOS status-bar clock: 12-hour, no AM/PM. 7:02, 2:14. */
export function fmtClock(min: Minute): string {
  const { h, m } = hm12(min);
  return `${h}:${pad2(m)}`;
}

/** Written time: 7:02 AM, 4:31 PM. */
export function fmtTime(min: Minute): string {
  const { h, m, pm } = hm12(min);
  return `${h}:${pad2(m)} ${pm ? 'PM' : 'AM'}`;
}

/** Spoken time, like the app: no AM/PM from 6:00 AM to 5:59 PM. */
export function fmtSpokenTime(min: Minute): string {
  const h24 = Math.floor(Math.floor(min + 1e-6) / 60) % 24;
  return h24 >= 6 && h24 < 18 ? fmtClock(min) : fmtTime(min);
}

/** Spoken duration, like the app: "8 hours 30 minutes", "30 minutes". */
export function fmtSpokenDuration(seconds: Seconds): string {
  const m = Math.round(seconds / 60);
  if (m === 0) return 'less than a minute';
  const parts: string[] = [];
  const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? '' : 's'}`;
  if (m >= 60) parts.push(plural(Math.floor(m / 60), 'hour'));
  if (m % 60 > 0) parts.push(plural(m % 60, 'minute'));
  return parts.join(' ');
}

/** 8,540 */
export function fmtCount(n: number): string {
  return Math.round(n).toLocaleString('en-US');
}

/** 0.2564 → "26%" */
export function fmtPct(fraction: number): string {
  return `${Math.round(fraction * 100)}%`;
}

/** A break span without AM/PM, as the time card lists it: "Lunch 12:01–12:31". */
export function fmtBreak(b: Pick<Break, 'reason' | 'start' | 'end'>): string {
  return `${b.reason} ${fmtClock(b.start)}–${fmtClock(b.end)}`;
}

/** "Water 9:45–10:00; Lunch 12:01–12:31; Sharpening shears 2:30–2:44" */
export function breaksText(breaks: readonly Pick<Break, 'reason' | 'start' | 'end'>[]): string {
  return [...breaks].sort((a, b) => a.start - b.start).map(fmtBreak).join('; ');
}

// ---------------------------------------------------------------------------
// The week (Mon Oct 12 – Fri Oct 16) for the Clock tab chart and the paper time card

export interface Day {
  key: 'mon' | 'tue' | 'wed' | 'thu' | 'fri';
  /** Chart label. */
  label: string;
  /** Time-card date: "Mon, Oct 12". */
  date: string;
  long: string;
  in: Minute;
  out: Minute;
  trees: number;
  breaks: readonly Break[];
  note: string | null;
  /** Seconds worked. */
  worked: Seconds;
}

function day(
  key: Day['key'],
  label: string,
  date: string,
  long: string,
  inAt: Minute,
  out: Minute,
  trees: number,
  breaks: readonly Break[],
  note: string | null = null,
): Day {
  const breakMins = breaks.reduce((s, b) => s + (b.end - b.start), 0);
  return { key, label, date, long, in: inAt, out, trees, breaks, note, worked: (out - inAt - breakMins) * 60 };
}

const lunch = (start: Minute, end: Minute): Break => ({ kind: 'lunch', reason: 'Lunch', start, end });

export const WEEK: readonly Day[] = [
  day('mon', 'Mon', 'Mon, Oct 12', 'Monday', t(7, 5), t(16, 12), 281, [lunch(t(12, 0), t(12, 30))]),
  day('tue', 'Tue', 'Tue, Oct 13', 'Tuesday', t(7, 0), t(15, 48), 276, [lunch(t(12, 5), t(12, 35))]),
  day('wed', 'Wed', 'Wed, Oct 14', 'Wednesday', t(7, 30), t(13, 15), 182, [], 'Rain after 1.'),
  day('thu', 'Thu', 'Thu, Oct 15', 'Thursday', t(7, 0), t(16, 30), 318, [
    lunch(t(12, 10), t(12, 40)),
    { kind: 'break', reason: 'Water', start: t(14, 15), end: t(14, 30) },
  ]),
  day('fri', 'Fri', 'Fri, Oct 16', 'Friday', SHIFT.in, SHIFT.out, 290, BREAKS, SHIFT_NOTE),
];

export const WEEK_RANGE = 'Mon, Oct 12 – Fri, Oct 16';

export function weekTotals(days: readonly Day[] = WEEK) {
  const worked = days.reduce((s, d) => s + d.worked, 0);
  const trees = days.reduce((s, d) => s + d.trees, 0);
  return { worked, trees, label: `${fmtHM(worked)} hours · ${fmtCount(trees)} trees` };
}

export const BEST_DAY = [...WEEK].sort((a, b) => b.trees - a.trees)[0]!;

/** Hours per weekday for the Clock tab chart at `min` on Friday (Friday counts so far). */
export function weekHoursAt(min: Minute): Array<{ label: string; seconds: Seconds; hm: string; today: boolean }> {
  return WEEK.map((d) => {
    const seconds = d.key === 'fri' ? workedAt(min) : d.worked;
    return { label: d.label, seconds, hm: fmtHM(seconds), today: d.key === 'fri' };
  });
}

/** The Team tab's "This week", through Friday 3:00 PM. */
export const TEAM: ReadonlyArray<{ name: Person; hours: string; trees: number }> = [
  { name: 'Alex', hours: '38:24', trees: 1297 },
  { name: 'Sam', hours: '36:50', trees: 1214 },
  { name: 'Rosa', hours: '31:15', trees: 1046 },
];

// ---------------------------------------------------------------------------
// Screen states

export type ActivityState = 'working' | 'tapped' | 'lunch' | 'break';

export interface ShiftState {
  min: Minute;
  worked: Seconds;
  onBreak: ReturnType<typeof breakAt>;
  trees: number;
  position: Position;
  rows: [number, number, number];
  fieldShaped: number;
  fieldPct: number;
}

export function stateAt(min: Minute): ShiftState {
  const fieldShaped = fieldShapedAt(min);
  return {
    min,
    worked: workedAt(min),
    onBreak: breakAt(min),
    trees: treesAt(min),
    position: positionAt(min),
    rows: rowsAt(min),
    fieldShaped,
    fieldPct: fieldShaped / FIELD_TREES,
  };
}

/** The last lock-screen tap that still shows "Row n marked · Undo" (until the next break). */
function undoRowAt(min: Minute): number | null {
  const tap = [...MARKS].reverse().find((m) => m.via === 'lock-screen' && m.at <= min);
  if (!tap) return null;
  const nextBreak = BREAKS.find((b) => b.start >= tap.at);
  return nextBreak && min >= nextBreak.start ? null : tap.row;
}

export interface LiveActivityData {
  state: ActivityState;
  /** "On the clock", "On lunch", "On break · Sharpening shears". */
  pill: string;
  /** h:mm:ss */
  worked: string;
  /** h:mm:ss of the running break, "0:00:00" when working. */
  breakTime: string;
  breakReason: string | null;
  trees: number;
  field: string;
  block: string;
  /** 0–1 */
  fieldPct: number;
  rows: [number, number, number];
  /** The fourth row button waiting off the right edge of the strip. */
  nextRow: number;
  undoRow: number | null;
}

/** Everything the Live Activity shows at `min`. */
export function liveActivityAt(min: Minute): LiveActivityData {
  const s = stateAt(min);
  const brk = s.onBreak;
  const undoRow = brk ? null : undoRowAt(min);
  const state: ActivityState = brk ? (brk.kind === 'lunch' ? 'lunch' : 'break') : undoRow ? 'tapped' : 'working';
  // The Live Activity button starts a break with no reason; the 2:30 break got its reason by voice.
  const pill = !brk ? 'On the clock' : brk.kind === 'lunch' ? 'On lunch' : `On break · ${brk.reason}`;
  return {
    state,
    pill,
    worked: fmtHMS(s.worked),
    breakTime: fmtHMS(brk?.seconds ?? 0),
    breakReason: brk && brk.kind === 'break' ? brk.reason : null,
    trees: s.trees,
    field: FIELD.name,
    block: `Block ${s.position.block}`,
    fieldPct: s.fieldPct,
    rows: s.rows,
    nextRow: s.rows[2] + 1,
    undoRow,
  };
}
