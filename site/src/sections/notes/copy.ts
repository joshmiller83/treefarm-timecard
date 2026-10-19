/**
 * NOTES · 2:30 PM: every string and number the section shows, built from the ledger and the
 * Siri lines (never typed by hand). Notes.astro renders these; copy.test.ts pins them.
 *
 * The break by voice follows decisions.md #3: the lock screen's Break button starts a break
 * with no reason, so the "Sharpening shears" beat is the voice version, and Siri asks for a
 * reason only when "Ask for a break reason" is on in Settings.
 */
import {
  BREAKS,
  DAY,
  FLAGS,
  MOMENTS,
  OLD_NOTE,
  SHIFT_NOTE,
  TREE_NOTE,
  WORKER,
  fmtBreak,
  fmtHMS,
  fmtTime,
  liveActivityAt,
  workedAt,
  type TreeNote,
} from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';

/** The break with a reason: the third break of the day (2:30–2:44). */
export const SHARPENING = BREAKS.find((b) => b.start === MOMENTS.break)!;

export const BODY =
  'Tap Break when you stop. The lock screen turns gold, with a break timer and one big button: Back to work. Breaks can carry a reason, like water or sharpening shears.';

/** "Needs attention, Dead or Replant": the app's flag vocabulary, exactly. */
export const FLAG_LIST = `${FLAGS.slice(0, -1).join(', ')} or ${FLAGS[FLAGS.length - 1]}`;

/** A beat's timestamp line: "2:33 PM · Tree note". */
export const stamp = (min: number, label: string) => `${fmtTime(min)} · ${label}`;

export const STAMPS = {
  break: stamp(MOMENTS.break, 'Break by voice'),
  tree: stamp(MOMENTS.treeNote, 'Tree note'),
  crew: stamp(MOMENTS.treeNote, 'On the map'),
  shift: stamp(MOMENTS.shiftNote, 'Shift note'),
  back: stamp(MOMENTS.backFromBreak, 'Back to work'),
} as const;

/** A minute after midnight as a valid <time datetime>: 870 → "14:30". */
export const isoClock = (min: number) => {
  const m = Math.floor(min + 1e-6);
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
};

/** Each stamp's machine-readable time. */
export const STAMP_ISO = {
  break: isoClock(MOMENTS.break),
  tree: isoClock(MOMENTS.treeNote),
  crew: isoClock(MOMENTS.treeNote),
  shift: isoClock(MOMENTS.shiftNote),
  back: isoClock(MOMENTS.backFromBreak),
} as const;

export type ChipKind = 'row' | 'tree' | 'quote' | 'flag';
export interface Chip {
  kind: ChipKind;
  text: string;
}

/** The answers to "Note a tree": the row, the tree, what's wrong and the flag. */
export function answerChips(note: TreeNote = TREE_NOTE): Chip[] {
  return [
    { kind: 'row', text: `Row ${note.row}` },
    { kind: 'tree', text: `Tree ${note.tree}` },
    { kind: 'quote', text: note.text },
    { kind: 'flag', text: note.flag },
  ];
}

/**
 * What the dictation card types while you answer "Note a tree": the row and the tree as
 * their chips appear, then what's wrong. TRANSCRIPT_PARTS splits it the same way.
 */
export const TRANSCRIPT_PARTS = [`Row ${TREE_NOTE.row},`, `tree ${TREE_NOTE.tree}.`, TREE_NOTE.text] as const;
export const TREE_TRANSCRIPT = TRANSCRIPT_PARTS.join(' ');

/** Worked time when the break starts, and still when it ends: "6:43:00". */
export const WORKED_ON_BREAK = fmtHMS(workedAt(MOMENTS.break));

/** The gold pill on the break: "On break · Sharpening shears". */
export const BREAK_PILL = liveActivityAt(MOMENTS.break).pill;

/** "Sharpening shears 2:30–2:44", as the time card lists it. */
export const BREAK_ON_CARD = fmtBreak(SHARPENING);

/** The day the shift note lands on, as the paper time card writes it. */
export const CARD_DAY = DAY.short;
export const SHIFT_NOTE_TEXT = SHIFT_NOTE;

/** "Alex, today 2:33 PM": the note's byline, spoken. */
export const bylineSpoken = (note: TreeNote = TREE_NOTE, at = MOMENTS.treeNote) => `${note.by}, today ${fmtTime(at)}`;

/** The section phone's label (its final state: the tree note sheet over the map). */
export const PHONE_LABEL = `Time Card tree note for block ${TREE_NOTE.block}, row ${TREE_NOTE.row}, tree ${TREE_NOTE.tree}: ${TREE_NOTE.flag}. ${TREE_NOTE.text} ${bylineSpoken()}. The map shows a flag on that tree.`;

export const CAPTION = 'A tree note with a flag, shared with the crew.';

/** Alt text for each screen state (used when a real capture replaces the recreation). */
export const ALTS = {
  break: `Lock screen at ${fmtTime(MOMENTS.break)}. Siri: “${SIRI.breakReason.reply}” The Live Activity reads ${BREAK_PILL}, with a gold break timer, ${WORKED_ON_BREAK} worked and a Back to work button.`,
  treeNote: `Lock screen at ${fmtTime(MOMENTS.treeNote)}. Siri: “${SIRI.treeNote.reply}” The Live Activity is still on the break.`,
  map: `Trees tab, block ${TREE_NOTE.block}: a rust flag on row ${TREE_NOTE.row}, tree ${TREE_NOTE.tree}, and an older flag on row ${OLD_NOTE.row}, tree ${OLD_NOTE.tree}.`,
  note: PHONE_LABEL,
  dictation: `Lock screen at ${fmtTime(MOMENTS.shiftNote)}. Siri: “${SIRI.shiftNote.reply}” after the shift note “${SHIFT_NOTE}”`,
  back: `Lock screen at ${fmtTime(MOMENTS.backFromBreak)}. The Live Activity is back on the clock at ${fmtHMS(workedAt(MOMENTS.backFromBreak))} worked, ${liveActivityAt(MOMENTS.backFromBreak).trees} trees, with buttons for rows ${liveActivityAt(MOMENTS.backFromBreak).rows.join(', ')} and Break.`,
} as const;

/** Who is speaking, for the static transcript. */
export const YOU = 'You';
export const ME = WORKER;
