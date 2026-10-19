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
  OFFLINE,
  WORKER,
  fmtTime,
  type Flag,
  type Minute,
  type Person,
  type TreeNote,
} from '../../../data/ledger';

export type FlagTone = 'attention' | 'dead' | 'replant';

const TONES: Record<Flag, FlagTone> = { 'Needs attention': 'attention', Dead: 'dead', Replant: 'replant' };

export const flagTone = (flag: Flag): FlagTone => TONES[flag];

/**
 * The map's three states (decisions.md #4): gold = the viewer's own shift today, green = shaped
 * earlier this season or by anyone else (crew included), ring = not yet.
 */
export interface Shaped {
  state: 'today' | 'earlier' | 'not-yet';
  text: string;
}

/**
 * Whether a row's trees are shaped at `at`, as `who`'s phone shows it. The same rules as the
 * map's treeStatus(): the viewer's own marks are gold at once (an own mark that loses to an
 * earlier one stays gold until the sync rejects it); anyone else's count once the viewer can
 * see them (not while the viewer is offline, not someone's offline mark before it syncs), and
 * only if they were not rejected.
 */
export function treeShaped(block: number, row: number, at: Minute, who: Person = WORKER): Shaped {
  const synced = at >= OFFLINE.back;
  const viewerOffline = who === WORKER && at >= OFFLINE.lost && at < OFFLINE.back;
  const seen = [...MARKS, ...CREW_MARKS]
    .filter((m) => m.block === block && m.row === row && m.at <= at)
    .sort((a, b) => a.at - b.at);
  const said = (m: { at: Minute; by: Person }) => `Shaped today at ${fmtTime(m.at)} by ${m.by}`;

  const mine = seen.find((m) => m.by === who && !(m.rejected && synced));
  if (mine) return { state: 'today', text: said(mine) };
  if (EARLIER.some((r) => r.block === block && row >= r.from && row <= r.to)) {
    return { state: 'earlier', text: 'Shaped earlier this season' };
  }
  const theirs = seen.find(
    (m) => m.by !== who && !m.rejected && !(m.offline && !synced) && !(viewerOffline && m.at >= OFFLINE.lost),
  );
  if (theirs) return { state: 'earlier', text: said(theirs) };
  return { state: 'not-yet', text: 'Not shaped yet this season' };
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
 * `at` is when the sheet is open (default 2:33 PM, right after Alex's note) and `who` whose
 * phone it is (default Alex): pass the host TreesTab's own `at` and `who`.
 */
export function noteSheet(notes: readonly TreeNote[], at: Minute = MOMENTS.treeNote, who: Person = WORKER): NoteSheetModel {
  const first = notes[0];
  if (!first) throw new Error('A tree note sheet needs at least one note.');
  const n = notes.length;
  return {
    title: `Block ${first.block} · Row ${first.row} · Tree ${first.tree}`,
    subtitle: FIELD.name,
    shaped: treeShaped(first.block, first.row, at, who),
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
