/**
 * VOICE · the section's content as pure data (Vitest: model.test.ts); the clock is in clock.ts.
 *
 * Every spoken line comes from siri.ts and every number from the ledger. The page shows four
 * exchanges; the lunch one has two parts (12:01 and 12:31), which are one article on desktop
 * and two cards on mobile. Each part has its own scroll progress on mobile; on desktop the
 * lunch article's single progress is split at LUNCH_SPLIT, as the brief lays it out.
 */
import { BREAKS, MOMENTS, fmtTime, type Minute } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import type { PartId } from './clock.ts';

// ---------------------------------------------------------------------------
// Copy

export type { PartId } from './clock.ts';
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
/** What Siri heard instead: the row in its question ('Row 40 in block 2?'). */
export const HEARD_NUMBER = /Row (\d+)/.exec(SIRI.misheard.reply)![1]!;

export const EXCHANGES: readonly Exchange[] = [
  exchange('misheard', [
    part(
      'misheard',
      SIRI.misheard.at,
      [
        said(SIRI.misheard.said, MISHEARD_WORD),
        { ...reply(SIRI.misheard.reply), mark: HEARD_NUMBER },
        { who: 'you', key: 'answer', text: SIRI.misheard.answer },
      ],
      {
        caption: 'Far-off rows get a double check, in case Siri heard forty for fourteen. Nothing changes until you say yes.',
        note: 'Nothing changed.',
      },
    ),
  ]),
  exchange('next', [
    part('next', SIRI.nextRow.at, [said(SIRI.nextRow.said), reply(SIRI.nextRow.reply)], {
      caption: 'It marks the next open row and moves you on. When the block changes, it says the block out loud.',
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
// The clock lives in ./clock.ts (the scene imports it without the copy).

export * from './clock.ts';
