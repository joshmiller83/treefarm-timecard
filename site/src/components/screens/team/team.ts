/**
 * The Team tab's rows and totals (admins only): this week's hours and trees per person.
 * Pure: no DOM, safe in Astro frontmatter and in Vitest. No invite codes, expiry or pay.
 */
import { fmtCount } from '../../../data/ledger';

export interface TeamRowIn {
  name: string;
  /** 'h:mm' */
  hours: string;
  trees: number;
}

export type AvatarTint = 'fir' | 'sap' | 'bark' | 'sky';
const TINTS: AvatarTint[] = ['fir', 'sap', 'bark', 'sky'];

export interface TeamRow {
  name: string;
  initial: string;
  hours: string;
  trees: string;
  tint: AvatarTint;
}

export interface TeamModel {
  rows: TeamRow[];
  /** '3 people · 106:29 h · 3,557 trees' */
  total: string;
}

/** Minutes in an 'h:mm' duration. */
export function parseHM(hm: string): number {
  const m = /^(\d+):([0-5]\d)$/.exec(hm);
  if (!m) throw new Error(`Not an h:mm duration: ${hm}`);
  return Number(m[1]) * 60 + Number(m[2]);
}

const fmtMinutes = (m: number) => `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`;

export function teamTab(rows: ReadonlyArray<TeamRowIn>): TeamModel {
  const minutes = rows.reduce((s, r) => s + parseHM(r.hours), 0);
  const trees = rows.reduce((s, r) => s + r.trees, 0);
  const people = `${rows.length} ${rows.length === 1 ? 'person' : 'people'}`;
  return {
    rows: rows.map((r, i) => ({
      name: r.name,
      initial: r.name.slice(0, 1).toUpperCase(),
      hours: r.hours,
      trees: fmtCount(r.trees),
      tint: TINTS[i % TINTS.length]!,
    })),
    total: `${people} · ${fmtMinutes(minutes)} h · ${fmtCount(trees)} trees`,
  };
}
