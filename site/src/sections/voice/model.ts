/**
 * VOICE · the section's content and its clock, as pure data (Vitest: model.test.ts).
 *
 * Every spoken line comes from siri.ts and every number from the ledger. The page shows four
 * exchanges; the lunch one has two parts (12:01 and 12:31), which are one article on desktop
 * and two cards on mobile. Each part has its own scroll progress on mobile; on desktop the
 * lunch article's single progress is split at LUNCH_SPLIT, as the brief lays it out.
 *
 * voiceMinute() turns the progress of the section and of every exchange into the DayClock
 * minute. It is a pure function of all of them (not a chain of tweens on one object), so
 * jumping anywhere on the page, forwards or backwards, always lands on the right time.
 */
import { BREAKS, MOMENTS, fmtTime, type Minute } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';

// ---------------------------------------------------------------------------
// Copy

export type PartId = 'misheard' | 'next' | 'lunchA' | 'lunchB' | 'status';
export type ExchangeId = 'misheard' | 'next' | 'lunch' | 'status';

export interface Turn {
  who: 'you' | 'siri';
  /** 'said' is the command, 'answer' your reply to Siri's question, 'reply' Siri's answer. */
  key: 'said' | 'answer' | 'reply';
  text: string;
  /** A word to flag (the misheard 'fourteen'). */
  mark?: string;
}

export interface Part {
  id: PartId;
  at: Minute;
  /** '7:18 AM' */
  stamp: string;
  /** '07:18' for <time datetime> */
  datetime: string;
  turns: Turn[];
  caption?: string;
  /** A short status line after the caption ('Nothing changed.'). */
  note?: string;
}

export interface Exchange {
  id: ExchangeId;
  parts: Part[];
  /** Every turn of every part, in order. */
  turns: Turn[];
}

const pad2 = (n: number) => String(n).padStart(2, '0');
const datetime = (min: Minute) => `${pad2(Math.floor(min / 60))}:${pad2(Math.floor(min % 60))}`;

const part = (id: PartId, at: Minute, turns: Turn[], extra: Pick<Part, 'caption' | 'note'> = {}): Part => ({
  id,
  at,
  stamp: fmtTime(at),
  datetime: datetime(at),
  turns,
  ...extra,
});

const exchange = (id: ExchangeId, parts: Part[]): Exchange => ({ id, parts, turns: parts.flatMap((p) => p.turns) });

const said = (text: string, mark?: string): Turn => ({ who: 'you', key: 'said', text, ...(mark ? { mark } : {}) });
const reply = (text: string): Turn => ({ who: 'siri', key: 'reply', text });

export const MISHEARD_WORD = 'fourteen';

export const EXCHANGES: readonly Exchange[] = [
  exchange('misheard', [
    part(
      'misheard',
      SIRI.misheard.at,
      [said(SIRI.misheard.said, MISHEARD_WORD), reply(SIRI.misheard.reply), { who: 'you', key: 'answer', text: SIRI.misheard.answer }],
      {
        caption: 'Far-off rows get a double check, in case Siri heard forty for fourteen. Nothing changes until you say yes.',
        note: 'Nothing changed.',
      },
    ),
  ]),
  exchange('next', [
    part('next', SIRI.nextRow.at, [said(SIRI.nextRow.said), reply(SIRI.nextRow.reply)], {
      caption: 'It marks the next row you haven’t done and moves you on. When the block changes, it says the block out loud.',
    }),
  ]),
  exchange('lunch', [
    // No reply on purpose: the lock screen turning gold is the answer (siri.ts).
    part('lunchA', SIRI.takeLunch.at, [said(SIRI.takeLunch.said)], {
      caption: 'The lock screen turns gold and a lunch timer starts. Your worked time stops right where it was.',
    }),
    part('lunchB', SIRI.backToWork.at, [said(SIRI.backToWork.said), reply(SIRI.backToWork.reply)]),
  ]),
  exchange('status', [
    part('status', SIRI.howMany.at, [said(SIRI.howMany.said), reply(SIRI.howMany.reply)], {
      caption: 'Ask about hours, pace or pay too. On a locked phone, Siri only says your pay out loud if you allow it.',
    }),
  ]),
];

export const LUNCH_MINUTES = (() => {
  const l = BREAKS.find((b) => b.kind === 'lunch')!;
  return l.end - l.start;
})();

const NB = '\u00a0';

/**
 * Keeps places and amounts on one line, as SiriSnippet does in the phone: 'block 2', 'row 35',
 * '10 trees', '26 rows', '34 an hour', '30 minutes' (their spaces become no-break spaces).
 */
export function keepTogether(text: string): string {
  return text
    .replace(/\b(block|row|tree|Block|Row|Tree) (\d+)/g, `$1${NB}$2`)
    .replace(/(\d+) an hour\b/g, `$1${NB}an${NB}hour`)
    .replace(/(\d+) (hours?|minutes?|seconds?|trees?|rows?)\b/g, `$1${NB}$2`)
    .replace(/\b(hours?|minutes?) (\d+)/g, `$1${NB}$2`);
}

/** Splits a line into words for scrubbed reveals (no-break groups stay whole), flagging `mark`. */
export function splitWords(text: string, mark?: string): Array<{ w: string; mark: boolean }> {
  return keepTogether(text)
    .split(/ +/)
    .filter(Boolean)
    .map((w) => ({ w, mark: !!mark && w.replace(/[^\p{L}\p{N}]/gu, '') === mark }));
}

// ---------------------------------------------------------------------------
// Screen layers (CONTRACT.md's state id registry), bottom to top

export interface Layer {
  id: string;
  /** The ledger minute the layer shows. */
  at: Minute;
  /** Has a Siri snippet (the big clock gives way to it). */
  snippet: boolean;
  final?: boolean;
}

export const LAYERS: readonly Layer[] = [
  { id: 'lock-0718-misheard', at: MOMENTS.misheard, snippet: true },
  { id: 'lock-0719-next', at: MOMENTS.firstRow, snippet: true },
  { id: 'lock-1201-lunch', at: MOMENTS.lunch, snippet: false },
  { id: 'lock-1231-back', at: MOMENTS.back, snippet: true },
  { id: 'lock-1401-status', at: MOMENTS.status, snippet: true, final: true },
];

// ---------------------------------------------------------------------------
// The clock

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
