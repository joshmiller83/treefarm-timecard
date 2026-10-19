/**
 * VOICE · the section's clock, as pure data (Vitest: model.test.ts). Kept apart from the copy
 * in model.ts so the scene's chunk carries no strings.
 *
 * voiceMinute() turns the progress of the section and of every exchange into the DayClock
 * minute. It is a pure function of all of them (not a chain of tweens on one object), so
 * jumping anywhere on the page, forwards or backwards, always lands on the right time.
 */
import { BREAKS, MOMENTS, type Minute } from '../../data/ledger.ts';

export type PartId = 'misheard' | 'next' | 'lunchA' | 'lunchB' | 'status';

/**
 * Lunch edges. EDGE (30 microseconds) and NUDGE (12 ms) keep every clock honest at
 * the instant lunch starts and ends: the status bar already reads 12:01 (or 12:31) while the
 * timer still shows the worked time (or the full 0:30:00 of lunch). model.test.ts checks
 * each reading against the DayClock's own formatting.
 */
const EDGE = 5e-7;
const NUDGE = 2e-4;
const lunch = BREAKS.find((b) => b.kind === 'lunch')!;
/** The morning's water break (9:45–10:00): the time-lapse steps over it (see daySteps). */
export const WATER = BREAKS.find((b) => b.kind === 'break' && b.start < lunch.start)!;
export const BEFORE_LUNCH = lunch.start - EDGE;
export const LUNCH_STARTED = lunch.start + NUDGE;
export const BEFORE_BACK = lunch.end - EDGE;
export const BACK = lunch.end + NUDGE;

/** Where each scrubbed timeline gets its progress. */
export type Source = 'main' | 'misheard' | 'next' | 'lunch' | 'lunchA' | 'lunchB' | 'status';

/** Desktop: the lunch article's progress at which 'Take lunch' ends and the 12:31 half begins. */
export const LUNCH_SPLIT = 0.45;

/** Where a part's local progress `at` lands: which timeline, at what progress. */
export function place(p: PartId | 'main', at: number, desk: boolean): { src: Source; p: number } {
  if (desk && p === 'lunchA') return { src: 'lunch', p: at * LUNCH_SPLIT };
  if (desk && p === 'lunchB') return { src: 'lunch', p: LUNCH_SPLIT + at * (1 - LUNCH_SPLIT) };
  return { src: p, p: at };
}

export interface DayStep {
  part: PartId | 'main';
  /** Window in the part's local progress. */
  at: readonly [number, number];
  from: Minute;
  to: Minute;
}

type Win = readonly [number, number];

/**
 * The moments the clock and the Live Activity share, in each part's local progress, per mode.
 * The scene flips the card at `lunchAt` and `backAt`; the day steps put the lunch edges there.
 *
 * Mobile runs earlier than desktop: each card ('top 80%' → 'top 35%') slides over the Live
 * Activity at about .45, so everything the card shows changes before then.
 */
export interface Beats {
  /** 7:18 → 7:19 as the next exchange starts. */
  nextDay: Win;
  /** The morning passes: 7:19 → 12:01 (the trees roll with it). */
  morning: Win;
  /** 'Take lunch': the card turns gold. */
  lunchAt: number;
  /** Thirty minutes of lunch: 12:01 → 12:31 (the lunch timer spins to 0:30:00). */
  spin: Win;
  /** 'Back to work': the card turns green. */
  backAt: number;
  /** The early afternoon passes: 12:31 → 2:01. */
  afternoon: Win;
}

export const BEATS: { readonly desk: Beats; readonly mob: Beats } = {
  desk: { nextDay: [0.08, 0.16], morning: [0.09, 0.26], lunchAt: 0.48, spin: [0, 0.18], backAt: 0.34, afternoon: [0.06, 0.18] },
  mob: { nextDay: [0.04, 0.1], morning: [0.03, 0.14], lunchAt: 0.3, spin: [0.02, 0.12], backAt: 0.29, afternoon: [0.04, 0.14] },
};

/** How long the instant lunch starts or ends takes on the scroll (a hair, so it reads as a cut). */
const EDGE_W = 0.02;

/**
 * The day through the section. Time passes as each exchange scrolls in, so the clock reads
 * the exchange's time while its line is spoken; lunch starts and ends on the spoken command.
 */
export function daySteps(desk: boolean): readonly DayStep[] {
  const b = desk ? BEATS.desk : BEATS.mob;
  // The morning time-lapse runs over worked minutes only: it steps over the water break
  // (9:45 → 10:00 in one frame), so the card never reads 'On the clock' at a time Alex was
  // on a break and its timer never stands still while the clock runs.
  const [m0, m1] = b.morning;
  const worked = BEFORE_LUNCH - MOMENTS.firstRow - (WATER.end - WATER.start);
  const cut = m0 + ((WATER.start - MOMENTS.firstRow) / worked) * (m1 - m0);
  return [
    { part: 'misheard', at: [0, 0.16], from: MOMENTS.clockIn, to: MOMENTS.misheard },
    { part: 'next', at: b.nextDay, from: MOMENTS.misheard, to: MOMENTS.firstRow },
    { part: 'lunchA', at: [m0, cut], from: MOMENTS.firstRow, to: WATER.start },
    { part: 'lunchA', at: [cut, m1], from: WATER.end, to: BEFORE_LUNCH },
    { part: 'lunchA', at: [b.lunchAt, b.lunchAt + EDGE_W], from: BEFORE_LUNCH, to: LUNCH_STARTED },
    { part: 'lunchB', at: b.spin, from: LUNCH_STARTED, to: BEFORE_BACK },
    { part: 'lunchB', at: [b.backAt, b.backAt + EDGE_W], from: BEFORE_BACK, to: BACK },
    { part: 'status', at: b.afternoon, from: BACK, to: MOMENTS.status },
  ];
}

/** The desktop steps (the brief's layout). */
export const DAY_STEPS = daySteps(true);
const STEPS = { desk: DAY_STEPS, mob: daySteps(false) };

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

/** The DayClock minute for the given progress of each timeline (missing = 0). */
export function voiceMinute(progress: Partial<Record<Source, number>>, desk: boolean): Minute {
  const steps = desk ? STEPS.desk : STEPS.mob;
  let min = steps[0]!.from;
  for (const s of steps) {
    const a = place(s.part, s.at[0], desk);
    const b = place(s.part, s.at[1], desk);
    const t = clamp01(((progress[a.src] ?? 0) - a.p) / Math.max(b.p - a.p, 1e-9));
    if (t > 0) min = s.from + (s.to - s.from) * t;
  }
  return min;
}
