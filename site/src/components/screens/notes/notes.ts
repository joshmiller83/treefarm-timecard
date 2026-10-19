/**
 * The tree note sheet's words: the tree, its notes (newest first) and each flag's tone.
 * Pure: no DOM, safe in Astro frontmatter and in Vitest.
 */
import { FIELD, type Flag, type TreeNote } from '../../../data/ledger';

export type FlagTone = 'attention' | 'dead' | 'replant';

const TONES: Record<Flag, FlagTone> = { 'Needs attention': 'attention', Dead: 'dead', Replant: 'replant' };

export const flagTone = (flag: Flag): FlagTone => TONES[flag];

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
  /** 'North field · 1 note' */
  subtitle: string;
  notes: NoteRow[];
}

/** `notes` are one tree's notes in the order they were written; the sheet lists newest first. */
export function noteSheet(notes: readonly TreeNote[]): NoteSheetModel {
  const first = notes[0];
  if (!first) throw new Error('A tree note sheet needs at least one note.');
  const n = notes.length;
  return {
    title: `Block ${first.block} · Row ${first.row} · Tree ${first.tree}`,
    subtitle: `${FIELD.name} · ${n} ${n === 1 ? 'note' : 'notes'}`,
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
