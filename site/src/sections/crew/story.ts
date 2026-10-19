/**
 * THE CREW CHAPTER'S STORY, read from the ledger: Sam marks block 3 row 12 at 2:49 while
 * Alex has no signal; Alex marks rows 11 and 12 offline; at 3:00 the phone syncs, row 11
 * counts, row 12 was Sam's first, and Alex's phone says so. Every number, row and time on
 * the section comes from here (and so from src/data/ledger.ts).
 *
 * Pure: no DOM, safe in Astro frontmatter, the scene and Vitest.
 */
import { CONFLICT_MESSAGE, CREW_MARKS, MARKS, MOMENTS, PEOPLE, TEAM, fmtTime, type Mark } from '../../data/ledger.ts';

const must = <T>(v: T | undefined, what: string): T => {
  if (v === undefined) throw new Error(`crew story: no ${what} in the ledger`);
  return v;
};

/** Alex's marks made with no signal (block 3, rows 11 and 12). */
export const OFFLINE_MARKS: readonly Mark[] = MARKS.filter((m) => m.offline);
/** The offline mark that loses: someone else shaped that row first. */
export const REJECTED: Mark = must(
  OFFLINE_MARKS.find((m) => m.rejected),
  'rejected offline mark',
);
/** The offline marks that count once the phone syncs. */
export const KEPT: readonly Mark[] = OFFLINE_MARKS.filter((m) => !m.rejected);
/** The crew mark that came first (Sam's row 12 at 2:49). */
export const CONFLICT: Mark = must(
  CREW_MARKS.find((m) => m.block === REJECTED.block && m.row === REJECTED.row && m.at < REJECTED.at),
  'first crew mark on the rejected row',
);

/**
 * Changes waiting on Alex's phone at 2:56: the outbox holds one entry per tree mark, so two
 * whole rows queue 20 (the app: '20 changes waiting to sync').
 */
export const WAITING = OFFLINE_MARKS.filter((m) => m.at <= MOMENTS.alexRow12).reduce((n, m) => n + m.trees, 0);
/** Waiting after the first offline row (10). */
export const WAITING_FIRST = OFFLINE_MARKS[0]?.trees ?? 0;

/** The Trees tab's offline line (the app's SyncState summary, prefixed with Offline). */
export const syncLine = (n: number) => `Offline · ${n} change${n === 1 ? '' : 's'} waiting`;
export const OFFLINE_LINE = syncLine(WAITING);
export const SYNCED_LINE = 'Synced';

/** The rows the scene works with. */
export const BLOCK = REJECTED.block;
export const ROWS = {
  /** Rows the Trees tab is about (the map centres them). */
  view: [6, 16] as [number, number],
  kept: KEPT.map((m) => m.row),
  conflict: CONFLICT.row,
};

const names = (list: readonly string[]) =>
  list.length < 2 ? list.join('') : `${list.slice(0, -1).join(', ')} and ${list[list.length - 1]}`;
const rowsText = (rows: readonly number[]) => `row${rows.length === 1 ? '' : 's'} ${names(rows.map(String))}`;
const teamHours = TEAM.map((r) => `${r.name} ${r.hours}`).join(', ');

/** aria-labels for the phones (each phone root is role="img"). */
export const LABELS = {
  /** Alex's phone, final state (the section figure; the stage phone shows it on desktop). */
  main: `Your map, back in range: Synced, and the message ${CONFLICT_MESSAGE} ${rowsText(KEPT.map((m) => m.row)).replace(/^r/, 'R')} count${KEPT.length === 1 ? 's' : ''} as yours. Row ${CONFLICT.row} does not: ${CONFLICT.by} shaped it first.`,
  /** Static figure 1: Alex's phone with no signal. */
  offline: `Your map with no signal: No Service, ${rowsText(OFFLINE_MARKS.map((m) => m.row))} in gold, and the line ${OFFLINE_LINE}.`,
  /** Static figure 3: the owner's phone. */
  owner: `The owner’s phone: the Team tab with this week’s hours, ${teamHours}, and an Invite someone button.`,
  /** The second phone on the moving page: Sam's map, then the owner's Team tab. */
  peek: `A second phone. First ${CONFLICT.by}’s map, with his row ${CONFLICT.row} in gold. Then the owner’s phone: the Team tab with this week’s hours for ${names(PEOPLE)} and an Invite someone button.`,
};

/** The static figure's three steps (visible labels under each phone). */
export const STEPS = [
  { n: 1, time: fmtTime(MOMENTS.alexRow12), title: 'No signal' },
  { n: 2, time: fmtTime(MOMENTS.synced), title: 'Back in range' },
  { n: 3, time: fmtTime(MOMENTS.synced), title: 'The owner’s phone' },
] as const;

/** The figure's caption: first mark wins, told with the ledger's times. */
export const CAPTION = `First mark wins. ${CONFLICT.by} marked row ${CONFLICT.row} at ${fmtTime(CONFLICT.at)}. You marked it too, at ${fmtTime(REJECTED.at)} with no signal. When your phone syncs, it tells you ${CONFLICT.by} got there first.`;
