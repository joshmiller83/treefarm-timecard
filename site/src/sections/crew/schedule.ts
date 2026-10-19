/**
 * THE CREW SCENE'S SCHEDULE in progress units (0–1 of the section's scrubbed track).
 * brief: sections[crew].animation. The DayClock minutes come from the ledger, and each tap
 * lands exactly on its mark's minute (crew.test.ts checks it), so the status bars read
 * 2:49 when Sam taps, 2:50 and 2:56 when Alex does, and 3:00 when the bars come back.
 *
 * Pure data and math: imported by the scene and by Vitest.
 */
import { MOMENTS, OFFLINE, type Minute } from '../../data/ledger.ts';
import { CONFLICT, KEPT, REJECTED } from './story.ts';

type Win = readonly [number, number];

/** The DayClock at progress 0: the end of the 2:30 break (the notes chapter ends there). */
export const DAY_FROM: Minute = MOMENTS.backFromBreak;

const kept = KEPT[0];
if (!kept) throw new Error('crew schedule: no kept offline mark');

/** Progress of each beat of the story. */
export const AT = {
  /** Copy beats (brief layout: 0, .2, .4, .66, .86). */
  beats: [0, 0.2, 0.4, 0.66, 0.86] as const,

  // [0, .08] 2:44 → 2:47: the second phone slides out, names, the server, the wires draw.
  enter: [0, 0.08] as Win,
  peekIn: [0.005, 0.07] as Win,
  chips: [0.03, 0.07] as Win,
  server: [0.02, 0.06] as Win,
  wires: [0.04, 0.08] as Win,

  // [.08, .16] 2:48: the bars fade out one by one, No Service, the key light dims.
  barsOut: [0.088, 0.142] as Win,
  noService: [0.138, 0.156] as Win,
  dim: [0.09, 0.16] as Win,
  alexWireDim: [0.1, 0.15] as Win,
  /** Block 3 → the offline layer (identical at this moment, so nothing jumps). */
  offlineLayer: 0.16,

  // [.16, .26] 2:49: Sam marks row 12 first; his change goes up to the server.
  tap: {
    sam: 0.17,
    row11: 0.275,
    row12: 0.345,
  },
  samFill: [0.188, 0.208] as Win,
  packetSam: [0.208, 0.246] as Win,
  pulseSam: [0.244, 0.268] as Win,

  // [.26, .42] 2:50 → 2:56: Alex marks rows 11 and 12 with no signal; both wait on the phone.
  fill11: [0.293, 0.31] as Win,
  syncIn: [0.304, 0.322] as Win,
  queue1: [0.306, 0.318] as Win,
  fill12: [0.363, 0.38] as Win,
  count: [0.378, 0.39] as Win,
  queue2: [0.376, 0.388] as Win,

  // [.42, .6] 3:00: back in range. Two changes go up, Sam's row comes down, row 12 turns green.
  barsIn: [0.44, 0.49] as Win,
  undim: [0.44, 0.5] as Win,
  packetsUp: [0.468, 0.528] as Win,
  pulseSync: [0.524, 0.548] as Win,
  packetDown: [0.53, 0.566] as Win,
  syncOut: [0.552, 0.566] as Win,
  /** The offline layer → the synced layer (sync lines out of both, so nothing jumps). */
  swap: 0.566,
  syncedIn: [0.566, 0.584] as Win,
  green: [0.568, 0.592] as Win,
  banner: [0.578, 0.618] as Win,

  // [.6, .66] the banner goes.
  bannerOut: [0.624, 0.656] as Win,

  // [.66, .9] the owner's phone: same second phone, relabelled, comes forward with the Team tab.
  relabel: [0.662, 0.688] as Win,
  team: [0.668, 0.708] as Win,
  zSwap: 0.7,
  forward: [0.7, 0.78] as Win,
  wiresDim: [0.68, 0.72] as Win,
  rows: [0.738, 0.8] as Win,
  invite: [0.79, 0.81] as Win,
  workers: [0.8, 0.84] as Win,
  serverLit: [0.84, 0.88] as Win,

  // [.9, 1] everything back: the second phone recedes and fades, the stage phone rests.
  exit: [0.9, 0.97] as Win,
  exitDecor: [0.9, 0.95] as Win,
};

/** DayClock tweens: the minute reached at `end`, from the previous one. */
export const DAY_TRACK: ReadonlyArray<{ start: number; end: number; min: Minute }> = [
  { start: 0, end: 0.08, min: MOMENTS.crew }, // 2:44 → 2:47
  { start: 0.08, end: 0.088, min: OFFLINE.lost }, // 2:48: the bars start to go
  { start: 0.15, end: AT.tap.sam, min: CONFLICT.at }, // 2:49: Sam taps
  { start: 0.26, end: AT.tap.row11, min: kept.at }, // 2:50: Alex taps row 11
  { start: 0.29, end: AT.tap.row12, min: REJECTED.at }, // 2:56: Alex taps row 12
  { start: 0.4, end: AT.barsIn[0], min: OFFLINE.back }, // 3:00: back in range
];

/** The DayClock minute at progress p (piecewise linear, like the scrubbed tweens). */
export function dayAt(p: number): Minute {
  let min = DAY_FROM;
  for (const d of DAY_TRACK) {
    if (p <= d.start) return min;
    if (p < d.end) return min + ((d.min - min) * (p - d.start)) / (d.end - d.start);
    min = d.min;
  }
  return min;
}

/** Every window in AT, for range checks. */
export function windows(): Array<[string, Win]> {
  const out: Array<[string, Win]> = [];
  for (const [k, v] of Object.entries(AT)) {
    if (Array.isArray(v) && v.length === 2 && k !== 'beats') out.push([k, v as unknown as Win]);
  }
  return out;
}
