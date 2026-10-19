/**
 * CLOCK OUT · the section's data: the spoken exchange, the 3:40 → 4:31 time-lapse, the
 * scene's progress windows, the page copy and the phones' labels. Every number comes from
 * the ledger and every spoken line from siri.ts; model.test.ts checks them against the brief.
 *
 * Pure data, no DOM: safe in Astro frontmatter, in the scene and in Vitest.
 */
import {
  FIELD_TREES,
  MARKS,
  MOMENTS,
  WEEK,
  fieldShapedAt,
  fmtHMS,
  fmtTime,
  rowsAt,
  treesAt,
  workedAt,
  type Minute,
} from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { paperTotals, periodFor } from '../../components/report/report.ts';

/** Where the pace chapter leaves the day (3:40 PM). */
export const FROM: Minute = MOMENTS.pace;
/** Clock-out (4:31 PM). */
export const AT: Minute = MOMENTS.clockOut;

export interface Line {
  who: 'you' | 'siri';
  text: string;
}

/** The exchange, in order: you ask, Siri checks, you say yes, Siri confirms. */
export const TRANSCRIPT: readonly Line[] = [
  { who: 'you', text: SIRI.clockOutAsk.said },
  { who: 'siri', text: SIRI.clockOutAsk.reply },
  { who: 'you', text: SIRI.clockOutAsk.answer },
  { who: 'siri', text: SIRI.clockOut.reply },
];

// ---------------------------------------------------------------------------
// The time-lapse at the top of the section

export interface LapseStep {
  /** 0–1 through the lapse. */
  t: number;
  /** The row just marked. */
  row: number;
  /** Trees this shift after the mark. */
  trees: number;
  /** The three row buttons after the mark. */
  rows: [number, number, number];
  /** The field bar after the mark (0–1). */
  fieldPct: number;
}

export interface Lapse {
  from: Minute;
  to: Minute;
  /** The Live Activity timer at each end (h:mm:ss). */
  worked: [string, string];
  trees: [number, number];
  rows: [[number, number, number], [number, number, number]];
  fieldPct: [number, number];
  /** One step per row marked during the lapse. */
  steps: LapseStep[];
}

const pct = (min: Minute) => fieldShapedAt(min) / FIELD_TREES;

/** What the Live Activity does while the day runs from `from` to `to`. */
export function lapse(from: Minute = FROM, to: Minute = AT): Lapse {
  const steps = MARKS.filter((m) => !m.rejected && m.at > from && m.at <= to).map((m) => ({
    t: (m.at - from) / (to - from),
    row: m.row,
    trees: treesAt(m.at),
    rows: rowsAt(m.at),
    fieldPct: pct(m.at),
  }));
  return {
    from,
    to,
    worked: [fmtHMS(workedAt(from)), fmtHMS(workedAt(to))],
    trees: [treesAt(from), treesAt(to)],
    rows: [rowsAt(from), rowsAt(to)],
    fieldPct: [pct(from), pct(to)],
    steps,
  };
}

export type Window = readonly [number, number];

/** A fraction `t` (0–1) of a progress window. */
export const lapseAt = (w: Window, t: number): number => w[0] + (w[1] - w[0]) * t;

// ---------------------------------------------------------------------------
// Scene timing, in scroll progress (0–1) of the section's track

/** Desktop (the stage phone): the brief's windows. */
export const DESK = {
  /** Day 3:40 → 4:31: the timer spins, the trees roll, the strip advances. */
  lapse: [0, 0.08],
  /** The user line lights word by word. */
  karaoke: [0.08, 0.14],
  /** Siri's glow comes on. */
  glow: [0.08, 0.11],
  /** The question drops in, types, and its Yes and No chips appear. */
  ask: [0.12, 0.2],
  /** Tap Yes; the page's “Yes.” appears. */
  yes: [0.2, 0.24],
  /** The answer replaces the question and types in; a gold rule sweeps under the timer. */
  answer: [0.24, 0.3],
  /** The Live Activity dismisses; the ribbon completes. */
  dismiss: [0.3, 0.36],
  /** The light layer fades over the stage; the rim light goes out. */
  lights: [0.36, 0.44],
  /** The section turns light (data-theme, with 0.4 s color transitions). */
  theme: 0.4,
  /** The report copy takes over columns 1–5 (it holds in the sticky frame). */
  copyIn: [0.42, 0.47],
  /** Unlock to the Report tab and tap This week. */
  unlock: [0.44, 0.52],
  /** The dusk copy makes way for the paper. */
  copyOut: [0.51, 0.555],
  /** The paper lifts out of the preview; the phone steps right. */
  lift: [0.52, 0.6],
  /** Rows print top to bottom; Friday last, with a gold flash. */
  print: [0.6, 0.72],
  /** The totals rule draws and the totals fade in. */
  totals: [0.72, 0.76],
  /** “No pay on the report. Ever.”: the leader line draws, the label fades. */
  annotate: [0.76, 0.82],
  /** Tap Export PDF, then CSV; the page chips pop. */
  exports: [0.82, 0.9],
  /** The phone settles back to rest for the next chapter. */
  rest: [0.92, 1],
} as const;

/**
 * Mobile (the section's own sticky phone; the paper is in flow after the track, so the
 * exchange gets the whole track). The cards pass over the lower phone, so the Live Activity
 * beats sit between them.
 */
export const MOB = {
  lapse: [0, 0.1],
  karaoke: [0.13, 0.2],
  glow: [0.13, 0.16],
  ask: [0.16, 0.27],
  yes: [0.3, 0.34],
  answer: [0.34, 0.43],
  dismiss: [0.44, 0.5],
  lights: [0.72, 0.84],
  theme: 0.78,
} as const;

/**
 * Where each copy beat sits in the track (SectionShell's --at): centered in the viewport when
 * the scroll progress equals it. Desktop beats follow the exchange (the report copy then holds
 * in the sticky frame); mobile cards pass over the lower part of the sticky phone between the
 * Live Activity beats.
 */
export const BEAT_AT = {
  head: { desk: -0.08, mob: 0 },
  askEx: { desk: 0.085, mob: 0.22 },
  yesEx: { desk: 0.215, mob: 0.46 },
  forgot: { desk: 0.32, mob: 0.7 },
} as const;

// ---------------------------------------------------------------------------
// The paper, the copy and the labels

export const TOTALS = paperTotals(WEEK);
const WEEK_PERIOD = periodFor('This week');

export const COPY = {
  intro: 'Say “Clock out with Time Card.” Siri asks first, so a stray word can’t end your day. Say yes, and the timer stops.',
  /** The safety net under the exchange: [lead, text]. */
  forgot: [
    ['Forget to clock out?', 'Time Card warns you about a shift left open overnight.'],
    ['Clocked in late, or forgot to clock in?', 'Change your start time.'],
  ],
  reportHeading: 'A time card you can hand in.',
  report:
    'Pick this week, last week, this month or any dates. You get a clean, paper-style time card with the date, in, out, trees, hours, breaks and notes.',
  points: [
    'Breaks are listed so everyone can see them. They never count as hours.',
    'Share it as a PDF, or export a CSV for your spreadsheet.',
  ],
  annotation: 'No pay on the report. Ever.',
  exports: ['PDF', 'CSV'],
  lockCaption: `At ${fmtTime(AT)} Siri confirms, the Live Activity ends and the lock screen goes quiet.`,
  reportCaption: 'The Report tab: pick a range, then share it as a PDF or a CSV.',
} as const;

export const LABELS = {
  /** The section's phone: where the exchange ends (its static final state). */
  lock: `iPhone lock screen at ${fmtTime(AT)}, just after clocking out by voice. The Live Activity is gone, and Siri’s card says: “${SIRI.clockOut.reply}”`,
  /** The Report tab beside the paper. */
  report: `Time Card’s Report tab with This week selected: ${WEEK_PERIOD.label}, ${TOTALS.hours} hours and ${TOTALS.trees} trees over ${TOTALS.days} days, a preview of the paper time card, and buttons to export a PDF or a CSV.`,
  exports: 'Export formats',
} as const;
