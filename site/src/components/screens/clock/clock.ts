/**
 * The Clock tab's words and numbers at a ledger minute, worked out the way the app's
 * ClockStatus, NowWorking, PaceCard and HoursPay do (iOS/App/Views/Clock on the app-clock
 * branch), with the brief's strings where it names them. Every number comes from the ledger.
 *
 * Pure: no DOM, safe in Astro frontmatter and in Vitest.
 */
import {
  BEST_DAY,
  BREAKS,
  DAY,
  FIELD,
  FIELD_TREES,
  SHIFT,
  SHIFT_NOTE,
  WEEK,
  WEEK_RANGE,
  breakAt,
  fieldShapedAt,
  fmtCount,
  fmtHM,
  fmtHMS,
  fmtPerTree,
  fmtTime,
  hoursLeftAt,
  paceAt,
  perTreeAt,
  positionAt,
  rowsAt,
  t,
  treesAt,
  weekHoursAt,
  workedAt,
  type Minute,
  type Seconds,
} from '../../../data/ledger';

export type ClockPhase = 'off' | 'working' | 'break' | 'lunch';
export type PaceRange = 'today' | 'week' | 'season';

/** Pay is hidden in every screen on the page. */
export const HIDDEN = '•••';

/** When Alex dictated the shift note ("Add a note in Time Card"). */
export const SHIFT_NOTE_AT: Minute = t(14, 36);

/** Rounded to the minute: "45 min", "1 h 5 min", "2 h" (TreeFarmKit Fmt.minutesText). */
export function minutesText(seconds: Seconds): string {
  const m = Math.round(seconds / 60);
  if (m < 60) return `${m} min`;
  return `${Math.floor(m / 60)} h` + (m % 60 === 0 ? '' : ` ${m % 60} min`);
}

/** Rounded, but never 100 until every tree is shaped (NowWorking.percent). */
export function percentShaped(shaped: number, total: number): number {
  if (total <= 0) return 0;
  if (shaped >= total) return 100;
  return Math.min(99, Math.round((shaped / total) * 100));
}

function phaseAt(min: Minute): ClockPhase {
  if (min < SHIFT.in || min >= SHIFT.out) return 'off';
  const b = breakAt(min);
  return b ? b.kind : 'working';
}

/** Finished break time on the shift at `min`, in seconds (running breaks excluded). */
function finishedBreaks(min: Minute): Seconds {
  return BREAKS.filter((b) => b.end <= min).reduce((s, b) => s + (b.end - b.start) * 60, 0);
}

export interface StatusModel {
  phase: ClockPhase;
  /** 'On the clock', 'On break', 'On lunch', 'Off the clock' */
  pill: string;
  /** 'Friday, Oct 16' */
  date: string;
  /** The big h:mm:ss clock. */
  timer: string;
  /** 'worked today', plus '· paused while you’re on break' on a break. */
  workedLabel: string;
  /** 'Clocked in at 7:02 AM' (the brief's wording). */
  clockedIn: string;
  /** The quiet line under the timer. */
  meta: string;
  /** 'Break started 2:30 PM · Sharpening shears' */
  breakLine: string | null;
  /** '0:03:00' */
  breakSoFar: string | null;
}

function status(min: Minute): StatusModel {
  const phase = phaseAt(min);
  const date = `${DAY.weekday}, ${DAY.monthDay}`;
  const timer = fmtHMS(workedAt(min));
  const clockedIn = `Clocked in at ${fmtTime(SHIFT.in)}`;
  const base = { phase, date, timer, clockedIn, breakLine: null, breakSoFar: null };
  if (phase === 'off') {
    const meta = min < SHIFT.in ? 'Not clocked in yet today.' : `Last clocked out at ${fmtTime(SHIFT.out)}.`;
    return { ...base, pill: 'Off the clock', workedLabel: 'worked today', meta };
  }
  if (phase === 'working') {
    const breaks = finishedBreaks(min);
    return {
      ...base,
      pill: 'On the clock',
      workedLabel: 'worked today',
      meta: `${clockedIn} · ${breaks > 0 ? `Breaks ${minutesText(breaks)}` : 'No breaks yet'}`,
    };
  }
  const b = breakAt(min)!;
  const start = BREAKS.find((x) => min >= x.start && min < x.end)!.start;
  const word = phase === 'lunch' ? 'Lunch' : 'Break';
  const reason = phase === 'break' && b.reason ? ` · ${b.reason}` : '';
  return {
    ...base,
    pill: phase === 'lunch' ? 'On lunch' : 'On break',
    workedLabel: `worked today · paused while you’re on ${phase}`,
    meta: clockedIn,
    breakLine: `${word} started ${fmtTime(start)}${reason}`,
    breakSoFar: fmtHMS(b.seconds),
  };
}

export interface NowModel {
  field: string;
  block: number;
  row: number;
  /** 'Block 2 · Row 39' */
  place: string;
  /** The same three rows as the lock screen. */
  rows: [number, number, number];
  /** On a break the row buttons rest: 'Row 37 is next when you’re back.' */
  waiting: string | null;
}

function now(min: Minute): NowModel | null {
  const phase = phaseAt(min);
  if (phase === 'off') return null;
  const { block, row } = positionAt(min);
  return {
    field: FIELD.name,
    block,
    row,
    place: `Block ${block} · Row ${row}`,
    rows: rowsAt(min),
    waiting: phase === 'working' ? null : `Row ${row} is next when you’re back.`,
  };
}

export interface TreesModel {
  /** 'Trees this shift', or 'Field' off the clock. */
  label: string;
  big: string;
  /** '2,460 of 8,540 trees shaped in North field' */
  line: string;
  /** '29%', beside the progress bar (null off the clock, where it is the big number). */
  pct: string | null;
  fraction: number;
  /** 'Mark trees' on a shift, 'See the field' off it. */
  button: string;
}

function trees(min: Minute): TreesModel {
  const shaped = fieldShapedAt(min);
  const pct = percentShaped(shaped, FIELD_TREES);
  const of = `${fmtCount(shaped)} of ${fmtCount(FIELD_TREES)} trees shaped in ${FIELD.name}`;
  const fraction = shaped / FIELD_TREES;
  const base = { line: of, pct: `${pct}%`, fraction };
  if (phaseAt(min) === 'off') return { ...base, pct: null, label: 'Field', big: `${pct}%`, button: 'See the field' };
  return { ...base, label: 'Trees this shift', big: fmtCount(treesAt(min)), button: 'Mark trees' };
}

export interface PaceModel {
  range: PaceRange;
  treesHour: { value: string; unit: string };
  perTree: { value: string; unit: string };
  pay: { label: string; value: string };
  /** 'Best day · Thu, Oct 15 · 318 trees' */
  best: string;
  /** 'About 179 hours left in North field at your pace' */
  left: string;
}

/**
 * Today uses the ledger's own pace helpers. This week and Season count every shift the
 * ledger knows (Mon–Thu plus Friday so far): the story's history starts on Monday.
 */
function pace(min: Minute, range: PaceRange): PaceModel {
  let perHour = 0;
  let each: Seconds = 0;
  let left = 0;
  if (range === 'today') {
    perHour = paceAt(min);
    each = perTreeAt(min);
    left = hoursLeftAt(min);
  } else {
    const before = WEEK.filter((d) => d.key !== 'fri');
    const trees = before.reduce((s, d) => s + d.trees, 0) + treesAt(min);
    const worked = before.reduce((s, d) => s + d.worked, 0) + workedAt(min);
    perHour = worked > 0 ? Math.round(trees / (worked / 3600)) : 0;
    each = trees > 0 ? Math.round(worked / trees) : 0;
    left = perHour > 0 ? Math.round((FIELD_TREES - fieldShapedAt(min)) / perHour) : 0;
  }
  return {
    range,
    treesHour: { value: perHour > 0 ? String(perHour) : '–', unit: 'trees an hour' },
    perTree: { value: each > 0 ? fmtPerTree(each) : '–', unit: 'a tree' },
    pay: { label: 'Pay per tree', value: HIDDEN },
    best: `Best day · ${BEST_DAY.date} · ${fmtCount(BEST_DAY.trees)} trees`,
    left: left > 0 ? `About ${fmtCount(left)} hours left in ${FIELD.name} at your pace` : `Mark a row to see your pace`,
  };
}

export interface NotesModel {
  text: string;
  placeholder: string;
}

function notes(min: Minute): NotesModel {
  return {
    text: min >= SHIFT_NOTE_AT && min >= SHIFT.in ? SHIFT_NOTE : '',
    placeholder: 'Which rows or blocks, what you worked on, anything to remember',
  };
}

export interface DayBar {
  key: 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun';
  label: string;
  /** 'h:mm', or '–' for a day off. */
  hm: string;
  /** Bar height, 0–1 of the chart. */
  fraction: number;
  today: boolean;
}

export interface HoursModel {
  today: string;
  week: string;
  pay: string;
  days: DayBar[];
  footnote: string;
}

/** The chart's top: 8 hours, or the longest day (HoursPay.chartMax). */
const CHART_MIN_TOP: Seconds = 8 * 3600;

function hours(min: Minute): HoursModel {
  const week = weekHoursAt(min);
  const top = Math.max(CHART_MIN_TOP, ...week.map((d) => d.seconds));
  const days: DayBar[] = [
    ...week.map((d, i) => ({
      key: WEEK[i]!.key,
      label: d.label,
      hm: d.seconds > 0 ? d.hm : '–',
      fraction: Math.min(1, d.seconds / top),
      today: d.today,
    })),
    { key: 'sat' as const, label: 'Sat', hm: '–', fraction: 0, today: false },
    { key: 'sun' as const, label: 'Sun', hm: '–', fraction: 0, today: false },
  ];
  const total = week.reduce((s, d) => s + d.seconds, 0);
  return {
    today: fmtHM(workedAt(min)),
    week: fmtHM(total),
    pay: HIDDEN,
    days,
    footnote: `${WEEK_RANGE}. Breaks don’t count toward hours. Pay never shows on the report.`,
  };
}

export interface ClockTabModel {
  at: Minute;
  status: StatusModel;
  now: NowModel | null;
  trees: TreesModel;
  pace: PaceModel;
  notes: NotesModel;
  hours: HoursModel;
}

/** Everything the Clock tab shows at ledger minute `at`. */
export function clockTab(at: Minute, range: PaceRange = 'today'): ClockTabModel {
  return { at, status: status(at), now: now(at), trees: trees(at), pace: pace(at, range), notes: notes(at), hours: hours(at) };
}
