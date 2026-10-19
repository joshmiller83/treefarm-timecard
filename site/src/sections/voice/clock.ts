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

/**
 * The day through the section. Time passes as each exchange scrolls in, so the clock reads
 * the exchange's time while its line is spoken; lunch starts and ends on the spoken command.
 */
export const DAY_STEPS: readonly DayStep[] = [
  { part: 'misheard', at: [0, 0.16], from: MOMENTS.clockIn, to: MOMENTS.misheard },
  { part: 'next', at: [0.08, 0.16], from: MOMENTS.misheard, to: MOMENTS.firstRow },
  { part: 'lunchA', at: [0.06, 0.24], from: MOMENTS.firstRow, to: BEFORE_LUNCH },
  { part: 'lunchA', at: [0.48, 0.5], from: BEFORE_LUNCH, to: LUNCH_STARTED },
  { part: 'lunchB', at: [0, 0.18], from: LUNCH_STARTED, to: BEFORE_BACK },
  { part: 'lunchB', at: [0.38, 0.4], from: BEFORE_BACK, to: BACK },
  { part: 'status', at: [0.06, 0.18], from: BACK, to: MOMENTS.status },
];

const clamp01 = (v: number) => Math.min(1, Math.max(0, v));

/** The DayClock minute for the given progress of each timeline (missing = 0). */
export function voiceMinute(progress: Partial<Record<Source, number>>, desk: boolean): Minute {
  let min = DAY_STEPS[0]!.from;
  for (const s of DAY_STEPS) {
    const a = place(s.part, s.at[0], desk);
    const b = place(s.part, s.at[1], desk);
    const t = clamp01(((progress[a.src] ?? 0) - a.p) / Math.max(b.p - a.p, 1e-9));
    if (t > 0) min = s.from + (s.to - s.from) * t;
  }
  return min;
}
