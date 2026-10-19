/**
 * Every phrase you say and every Siri reply on the page.
 *
 * Wording follows docs/landing/decisions.md #1: these are the app's real lines from
 * FieldEngine in TreeFarmKit (curly apostrophes included), with numbers from the ledger.
 * siri.test.ts checks them character for character against decisions.md and the ledger.
 *
 * `verified: false` marks wording that is not yet in the app's code. The build prints
 * those lines as a warning (see astro.config.mjs), so they get confirmed or replaced.
 */
import {
  BREAKS,
  CONFLICT_MESSAGE,
  MOMENTS,
  SHIFT,
  SHIFT_NOTE,
  TREE_NOTE,
  fmtSpokenDuration,
  fmtSpokenTime,
  paceAt,
  positionAt,
  treesAt,
  workedAt,
  type Minute,
} from './ledger.ts';

export interface SiriLine {
  key: string;
  /** When it happens in the story (minutes after midnight). */
  at: Minute;
  /** What you say. Null when there is nothing to say (a message on screen). */
  said: string | null;
  /** What Siri answers. Null when the page deliberately shows no reply. */
  reply: string | null;
  /** A follow-up question Siri asks before replying. */
  ask?: string;
  /** Your answer to `ask` or to the reply's choices. */
  answer?: string;
  /** Chips on the snippet. */
  choices?: readonly string[];
  /** True when the reply's wording comes from the app's code. */
  verified: boolean;
  /** True when the `ask` wording comes from the app's code. */
  askVerified?: boolean;
  /** Where the wording comes from. */
  source: string;
}

const place = (min: Minute) => {
  const p = positionAt(min);
  return `block ${p.block}, row ${p.row}`;
};
const sharpening = BREAKS[2]!;

export const SIRI = {
  clockIn: {
    key: 'clockIn',
    at: MOMENTS.clockIn,
    said: 'Clock in with Time Card.',
    reply: `Clocked in at ${fmtSpokenTime(SHIFT.in)}. You’re on ${place(SHIFT.in)}.`,
    verified: true,
    source: 'FieldEngine clock in',
  },
  misheard: {
    key: 'misheard',
    at: MOMENTS.misheard,
    said: 'Mark row fourteen in Time Card.',
    // Siri heard "forty". Far-off rows get a double check.
    reply: `Row 40 in block 2? That’s ${40 - positionAt(MOMENTS.misheard).row} rows ahead.`,
    choices: ['Yes', 'No'],
    answer: 'No.',
    verified: true,
    source: 'FieldEngine.confirmation',
  },
  nextRow: {
    key: 'nextRow',
    at: MOMENTS.firstRow,
    said: 'Next row in Time Card.',
    reply: `Row 14 marked, ${treesAt(MOMENTS.firstRow)} trees. Next is row ${positionAt(MOMENTS.firstRow).row}.`,
    verified: true,
    source: 'FieldEngine mark row',
  },
  takeLunch: {
    key: 'takeLunch',
    at: MOMENTS.lunch,
    said: 'Take lunch with Time Card.',
    // Deliberately not shown on the page: the lock screen turning gold is the answer.
    reply: null,
    verified: true,
    source: 'brief: lunch reply not shown',
  },
  backToWork: {
    key: 'backToWork',
    at: MOMENTS.back,
    said: 'Back to work with Time Card.',
    reply: `Back at ${fmtSpokenTime(MOMENTS.back)}. Lunch was ${fmtSpokenDuration((BREAKS[1]!.end - BREAKS[1]!.start) * 60)}.`,
    verified: true,
    source: 'FieldEngine back to work',
  },
  howMany: {
    key: 'howMany',
    at: MOMENTS.status,
    said: 'How many trees in Time Card?',
    reply: `${treesAt(MOMENTS.status)} trees today, ${paceAt(MOMENTS.status)} an hour. You’re on ${place(MOMENTS.status)}.`,
    verified: true,
    source: 'FieldAnswers trees',
  },
  breakReason: {
    key: 'breakReason',
    at: MOMENTS.break,
    said: 'Take a break with Time Card.',
    // Asked only when "Ask for a break reason" is on in Settings (decisions.md #3).
    ask: 'What’s the break for?',
    answer: 'Sharpening shears.',
    reply: `Break for ${sharpening.reason.toLowerCase()} started at ${fmtSpokenTime(sharpening.start)}.`,
    verified: true,
    askVerified: false,
    source: 'FieldEngine break',
  },
  treeNote: {
    key: 'treeNote',
    at: MOMENTS.treeNote,
    said: 'Note a tree in Time Card.',
    reply: `Noted on block ${TREE_NOTE.block}, row ${TREE_NOTE.row}, tree ${TREE_NOTE.tree}.`,
    verified: true,
    source: 'FieldEngine tree note',
  },
  shiftNote: {
    key: 'shiftNote',
    at: MOMENTS.shiftNote,
    said: 'Add a note in Time Card.',
    answer: SHIFT_NOTE,
    reply: 'Added to today’s notes.',
    verified: true,
    source: 'FieldEngine shift note',
  },
  conflict: {
    key: 'conflict',
    at: MOMENTS.synced,
    said: null,
    reply: CONFLICT_MESSAGE,
    verified: true,
    source: 'Server PushApplier.taken (per-tree sync rejection)',
  },
  clockOutAsk: {
    key: 'clockOutAsk',
    at: MOMENTS.clockOut,
    said: 'Clock out with Time Card.',
    reply: `You’ve worked ${fmtSpokenDuration(workedAt(SHIFT.out))} today. Clock out?`,
    choices: ['Yes', 'No'],
    answer: 'Yes.',
    verified: true,
    source: 'FieldEngine clock-out question',
  },
  clockOut: {
    key: 'clockOut',
    at: MOMENTS.clockOut,
    said: 'Yes.',
    reply: `Clocked out at ${fmtSpokenTime(SHIFT.out)}. ${fmtSpokenDuration(workedAt(SHIFT.out))}, ${treesAt(SHIFT.out)} trees.`,
    verified: true,
    source: 'FieldEngine clock out',
  },
} as const satisfies Record<string, SiriLine>;

export type SiriKey = keyof typeof SIRI;

/** All lines in story order. */
export const SIRI_LINES: readonly SiriLine[] = Object.values(SIRI);

/** The chip row that closes the voice section. */
export const MORE_TO_SAY = [
  'Undo in Time Card',
  'Add a note in Time Card',
  'Note a tree in Time Card',
  'Clock out with Time Card',
] as const;

/** Lines whose wording is not yet in the app's code (printed by the build). */
export function unverifiedLines(): Array<{ key: string; text: string }> {
  const out: Array<{ key: string; text: string }> = [];
  for (const l of SIRI_LINES) {
    if (!l.verified && l.reply) out.push({ key: l.key, text: l.reply });
    if (l.ask && l.askVerified === false) out.push({ key: `${l.key}.ask`, text: l.ask });
  }
  return out;
}
