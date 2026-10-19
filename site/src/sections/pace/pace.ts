/**
 * PACE (3:40 PM · the Clock tab): the chapter's words, numbers and choreography as pure data.
 *
 * Pace.astro renders from here, scenes/pace.ts animates from here, and pace.test.ts checks it
 * against the ledger and the brief. Every number comes from src/data/ledger.ts (through the
 * screens team's clock view model where the phone shows the same value), so the page tiles
 * and the phone's pace card can never disagree.
 *
 * Pure: no DOM and no GSAP, safe in Astro frontmatter and in Vitest.
 */
import {
  BEST_DAY,
  FIELD,
  MARKS,
  MOMENTS,
  WEEK,
  fmtCount,
  fmtSpokenDuration,
  fmtTime,
  hoursLeftAt,
  paceAt,
  perTreeAt,
  rowsAt,
  treesAt,
  weekHoursAt,
  workedAt,
  type Minute,
  type Seconds,
} from '../../data/ledger.ts';
import { clockTab } from '../../components/screens/clock/clock.ts';

/** The chapter's moment: 3:40 PM. */
export const PACE_AT: Minute = MOMENTS.pace;
/** Where the day stands when the chapter starts: the crew chapter ends at 3:00 PM (synced). */
export const PACE_FROM: Minute = MOMENTS.synced;

// ---------------------------------------------------------------------------
// Copy (the brief's final copy; numbers filled from the ledger)

export interface Bullet {
  before?: string;
  /** The part set in cream and 600 (Apple-style lead-in or punchline). */
  em: string;
  after?: string;
}

/** Keeps a number with its unit, and the last word off a line of its own. */
export const NBSP = '\u00a0';

export const bulletText = (b: Bullet) => `${b.before ?? ''}${b.em}${b.after ?? ''}`;

export const COPY = {
  body: 'Open the app and the Clock tab has your day. Today’s hours. Trees this shift. Your pace, worked out for you.',
  bullets: [
    { em: 'Trees an hour, time per tree and pay per tree', after: ', for today, this week and the season.' },
    { before: 'Your best day: ', em: `${BEST_DAY.long}, ${fmtCount(BEST_DAY.trees)}${NBSP}trees.` },
    { before: 'This week’s hours and pay sit in a bar chart. ', em: `Hide your pay with one${NBSP}tap.` },
  ] as Bullet[],
  small: 'Pay is hidden in every screen on this page, the way you can hide it in the app.',
  caption: 'The Clock tab at 3:40 PM, from the top down to Hours & pay, with pay hidden.',
} as const;

// ---------------------------------------------------------------------------
// The stat tiles

export type PaceRowId = 'trees-hour' | 'per-tree' | 'left';

export interface Tile {
  id: PaceRowId;
  /** The phone's matching [data-pace-row]: its gold rule draws when the tile reveals. */
  row: PaceRowId;
  /** What the tile shows: '34', '1:46', '179'. */
  text: string;
  unit: string;
  /** The whole tile in words, for screen readers: '1 minute 46 seconds a tree'. */
  spoken: string;
}

/** '1 minute 46 seconds' */
export function spokenMinSec(seconds: Seconds): string {
  const s = Math.round(seconds);
  const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? '' : 's'}`;
  const parts: string[] = [];
  if (s >= 60) parts.push(plural(Math.floor(s / 60), 'minute'));
  if (s % 60 > 0 || s === 0) parts.push(plural(s % 60, 'second'));
  return parts.join(' ');
}

/** The three page tiles at `at`, from the same model the phone's pace card renders. */
export function tilesAt(at: Minute = PACE_AT): Tile[] {
  const p = clockTab(at).pace;
  const left = fmtCount(hoursLeftAt(at));
  const leftUnit = 'hours of work left in this field at your pace';
  return [
    { id: 'trees-hour', row: 'trees-hour', text: p.treesHour.value, unit: p.treesHour.unit, spoken: `${paceAt(at)} ${p.treesHour.unit}` },
    { id: 'per-tree', row: 'per-tree', text: p.perTree.value, unit: p.perTree.unit, spoken: `${spokenMinSec(perTreeAt(at))} ${p.perTree.unit}` },
    { id: 'left', row: 'left', text: left, unit: leftUnit, spoken: `${left} ${leftUnit}` },
  ];
}

// ---------------------------------------------------------------------------
// Rolling digits (page tiles only; the phone uses the shared odometer)
//
// Each digit is a clipped column holding 0–9 twice. A roll moves the column from the first 0
// to the digit's place in the second cycle, so every column spins at least ten steps and
// lands exactly on its digit: no counting, no rounding, no drift.

const isDigit = (ch: string) => ch >= '0' && ch <= '9';
const CYCLE = '01234567890123456789';

/** translateY (percent of the column) that rests each digit column on its digit. */
export function rollStops(text: string): number[] {
  return Array.from(text)
    .filter(isDigit)
    .map((ch) => -((10 + Number(ch)) * 100) / CYCLE.length);
}

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);

/** Markup for a rolling reading, at rest on its final value (correct before any script runs). */
export function rollHTML(text: string): string {
  let out = '';
  for (const ch of text) {
    if (!isDigit(ch)) {
      out += `<span class="roll-s">${esc(ch)}</span>`;
      continue;
    }
    const stop = rollStops(ch)[0]!;
    out +=
      `<span class="roll-d"><span class="roll-col" data-digit="${ch}" style="transform:translateY(${stop}%)">` +
      Array.from(CYCLE, (n) => `<span>${n}</span>`).join('') +
      `</span></span>`;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Choreography, in progress units of the section's scrubbed timeline (0–1)

type Span = readonly [number, number];
type Three = readonly [number, number, number];

export interface Beats {
  lapse: Span;
  unlock: Span;
  toPace: Span;
  tiles: Three;
  bullets: Three;
  toHours: Span;
  bars: number;
  tap: number;
  pulse: number;
  small: Span;
  back: Span;
  relock: Span;
}

export const BEATS: Beats = {
  /** Time-lapse 3:00 → 3:40 on the lock screen: timer spins, trees roll, rows step. */
  lapse: [0, 0.1],
  /** Unlock: lock layer yPercent → -100, Clock tab .94 → 1. */
  unlock: [0.1, 0.18],
  /** In-phone scroll from the top to the pace card. */
  toPace: [0.19, 0.29],
  /** One tile lights per mark (triggered): rule, rise, rolling digits, and the phone row's gold rule. */
  tiles: [0.3, 0.38, 0.46],
  /** Desktop: the bullets come in one by one as the copy reaches them. */
  bullets: [0.52, 0.58, 0.64],
  /** In-phone scroll from the pace card to the end (Hours & pay). */
  toHours: [0.55, 0.65],
  /** The week's bars grow (triggered) as the hours card settles. */
  bars: 0.63,
  /** A tap on the eye-slash 'Show pay' toggle. */
  tap: 0.77,
  /** The masked pay does a single pulse. */
  pulse: 0.8,
  /** The small print fades in. */
  small: [0.79, 0.86],
  /** The scroll layer returns to the top. */
  back: [0.88, 0.94],
  /** The lock screen returns: the phone ends at rest on it. */
  relock: [0.92, 0.99],
};

export const LAPSE = BEATS.lapse;

/**
 * Below 900px the copy cards scroll up over the sticky phone, so the phone's moments go
 * where no card covers them: the tiles light while their card sits just under the phone,
 * and the tab reaches Hours & pay after that card has passed the chart.
 */
export const BEATS_MOB: Partial<Beats> = {
  tiles: [0.3, 0.35, 0.4],
  toHours: [0.5, 0.6],
  bars: 0.64,
};

/** The beats for a breakpoint. */
export function beatsFor(desk: boolean): Beats {
  return desk ? { ...BEATS } : { ...BEATS, ...BEATS_MOB };
}

/** Where the copy beats sit (SectionShell --at). The tiles card sits earlier below 900px. */
export const AT = { stats: 0.45, statsMob: 0.34, bullets: 0.88 } as const;

// ---------------------------------------------------------------------------
// The time-lapse (3:00 → 3:40 PM on the Live Activity)

export interface LapseEvent {
  at: Minute;
  row: number;
  before: number;
  after: number;
  /** Timeline progress where the day reaches `at`. */
  p: number;
}

/** Every row Alex marks between `from` and `to`, placed on the lapse window linearly in the minute. */
export function lapseEvents(from: Minute = PACE_FROM, to: Minute = PACE_AT, window: readonly [number, number] = LAPSE): LapseEvent[] {
  const marks = MARKS.filter((m) => m.by === 'Alex' && !m.rejected && m.at > from && m.at <= to).sort((a, b) => a.at - b.at);
  return marks.map((m) => ({
    at: m.at,
    row: m.row,
    before: treesAt(m.at - 1e-6),
    after: treesAt(m.at),
    p: window[0] + ((m.at - from) / (to - from)) * (window[1] - window[0]),
  }));
}

/** Rows the strip shows at `from` that the final card (at `to`) has already passed: [37, 38]. */
export function leadRows(from: Minute = PACE_FROM, to: Minute = PACE_AT): number[] {
  const a = rowsAt(from)[0];
  const b = rowsAt(to)[0];
  return Array.from({ length: Math.max(0, b - a) }, (_, i) => a + i);
}

// ---------------------------------------------------------------------------
// The in-phone scroll

export interface ScrollGeo {
  /** The scroll layer's height (px or pt, any unit, as long as all four agree). */
  layerH: number;
  /** The visible screen's height. */
  screenH: number;
  /** The pace card's top inside the layer. */
  paceTop: number;
  /** One pt in the same unit. */
  pt: number;
}

/** The pace card parks just under the toolbar (as the screens lab crops it). */
export const PACE_PARK_PT = 110;

/** Scroll offsets (positive, in the geo's unit) and the same as yPercent of the layer. */
export function scrollStops(g: ScrollGeo) {
  const end = Math.max(0, g.layerH - g.screenH);
  const pace = Math.min(end, Math.max(0, g.paceTop - PACE_PARK_PT * g.pt));
  const pct = (v: number) => (g.layerH > 0 ? (-v / g.layerH) * 100 : 0);
  return { pace, end, pacePct: pct(pace), endPct: pct(end) };
}

// ---------------------------------------------------------------------------
// Triggered tweens follow the scrubbed playhead

/** Marks the playhead passed going from `prev` to `next`, in the order it passed them. */
export function crossed(prev: number, next: number, marks: readonly number[]): Array<{ i: number; forward: boolean }> {
  if (next > prev) return marks.flatMap((m, i) => (m > prev && m <= next ? [{ i, forward: true }] : []));
  if (next < prev)
    return marks
      .flatMap((m, i) => (m > next && m <= prev ? [{ i, forward: false }] : []))
      .reverse();
  return [];
}

// ---------------------------------------------------------------------------
// Words for screen readers

/** 'Monday 8:37, Tuesday 8:18, Wednesday 5:45, Thursday 8:45 and Friday 7:39 so far' */
export function weekSentence(at: Minute = PACE_AT): string {
  const days = weekHoursAt(at).map((d, i) => `${WEEK[i]!.long} ${d.hm}${d.today ? ' so far' : ''}`);
  return days.length > 1 ? `${days.slice(0, -1).join(', ')} and ${days.at(-1)}` : (days[0] ?? '');
}

/** The section phone's aria-label: the brief's sentence, with the week chart's values in words. */
export function phoneLabel(at: Minute = PACE_AT): string {
  return (
    `Time Card Clock tab at ${fmtTime(at)}: on the clock ${fmtSpokenDuration(workedAt(at))}, ` +
    `${fmtCount(treesAt(at))} trees this shift, ${paceAt(at)} trees an hour, ${spokenMinSec(perTreeAt(at))} a tree, ` +
    `best day ${BEST_DAY.long} with ${fmtCount(BEST_DAY.trees)} trees, about ${fmtCount(hoursLeftAt(at))} hours left in ${FIELD.name}, ` +
    `and a week chart of hours worked, ${weekSentence(at)}, with pay hidden.`
  );
}

/** The static page's second crop (the bottom of the Clock tab). */
export function bottomCropLabel(at: Minute = PACE_AT): string {
  return (
    `The same Clock tab scrolled to the bottom: best day ${BEST_DAY.long} with ${fmtCount(BEST_DAY.trees)} trees, ` +
    `about ${fmtCount(hoursLeftAt(at))} hours left in ${FIELD.name}, the shift notes, and Hours & pay with a bar for each day, ` +
    `Friday in gold, and pay hidden behind dots.`
  );
}
