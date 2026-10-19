/**
 * The tree note sheet's words: the tree, whether it is shaped (in the map's own terms), its
 * notes (newest first) and each flag's tone.
 * Pure: no DOM, safe in Astro frontmatter and in Vitest.
 */
import {
  CREW_MARKS,
  EARLIER,
  FIELD,
  MARKS,
  MOMENTS,
  fmtTime,
  type Flag,
  type Minute,
  type TreeNote,
} from '../../../data/ledger';

export type FlagTone = 'attention' | 'dead' | 'replant';

const TONES: Record<Flag, FlagTone> = { 'Needs attention': 'attention', Dead: 'dead', Replant: 'replant' };

export const flagTone = (flag: Flag): FlagTone => TONES[flag];

/** The map's three states: gold (today), green (earlier this season), ring (not yet). */
export interface Shaped {
  state: 'today' | 'earlier' | 'not-yet';
  text: string;
}

/** Whether a row's trees are shaped at `at`: first mark wins, rejected marks never count. */
export function treeShaped(block: number, row: number, at: Minute): Shaped {
  if (EARLIER.some((r) => r.block === block && row >= r.from && row <= r.to)) {
    return { state: 'earlier', text: 'Shaped earlier this season' };
  }
  const first = [...MARKS, ...CREW_MARKS]
    .filter((m) => m.block === block && m.row === row && !m.rejected && m.at <= at)
    .sort((a, b) => a.at - b.at)[0];
  if (!first) return { state: 'not-yet', text: 'Not shaped yet this season' };
  return { state: 'today', text: `Shaped today at ${fmtTime(first.at)} by ${first.by}` };
}

export interface NoteRow {
  flag: Flag;
  tone: FlagTone;
  text: string;
  author: string;
  initial: string;
  byline: string;
}

export interface NoteSheetModel {
  /** 'Block 2 · Row 36 · Tree 7' */
  title: string;
  /** 'North field' */
  subtitle: string;
  shaped: Shaped;
  /** '1 note' */
  count: string;
  notes: NoteRow[];
}

/**
 * `notes` are one tree's notes in the order they were written; the sheet lists newest first.
 * `at` is when the sheet is open (default 2:33 PM, right after Alex's note).
 */
export function noteSheet(notes: readonly TreeNote[], at: Minute = MOMENTS.treeNote): NoteSheetModel {
  const first = notes[0];
  if (!first) throw new Error('A tree note sheet needs at least one note.');
  const n = notes.length;
  return {
    title: `Block ${first.block} · Row ${first.row} · Tree ${first.tree}`,
    subtitle: FIELD.name,
    shaped: treeShaped(first.block, first.row, at),
    count: `${n} ${n === 1 ? 'note' : 'notes'}`,
    notes: [...notes].reverse().map((note) => ({
      flag: note.flag,
      tone: flagTone(note.flag),
      text: note.text,
      author: note.by,
      initial: note.by.slice(0, 1).toUpperCase(),
      byline: note.byline,
    })),
  };
}
