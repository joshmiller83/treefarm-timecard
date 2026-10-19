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

/** One schedule: where each beat of the story sits, in progress units. */
export interface Schedule {
  /** Copy beats: where each card sits (--at): the heading, then lines 1–4. */
  beats: readonly number[];

  // 2:44 → 2:47: the second phone slides out, names, the server, the wires draw.
  enter: Win;
  /** Desktop: the camera pulls back a little so both phones and the server fit the frame. */
  pull: Win;
  peekIn: Win;
  chips: Win;
  server: Win;
  wires: Win;

  // 2:48: the bars fade out one by one, No Service, the key light dims.
  barsOut: Win;
  noService: Win;
  dim: Win;
  alexWireDim: Win;
  /** Block 3 → the offline layer (identical at this moment, so nothing jumps). */
  offlineLayer: number;

  // 2:49: Sam marks row 12 first; his change goes up to the server.
  tap: { sam: number; row11: number; row12: number };
  /** Sam's phone swings further out for his tap, so his row 12 reads, then settles back. */
  swingOut: Win;
  swingBack: Win;
  samFill: Win;
  packetSam: Win;
  pulseSam: Win;

  // 2:50 → 2:56: Alex marks rows 11 and 12 with no signal; both wait on the phone.
  fill11: Win;
  syncIn: Win;
  queue1: Win;
  fill12: Win;
  count: Win;
  queue2: Win;

  // 3:00: back in range. Two changes go up, Sam's row comes down, row 12 turns green.
  barsIn: Win;
  undim: Win;
  packetsUp: Win;
  pulseSync: Win;
  packetDown: Win;
  syncOut: Win;
  /** The offline layer → the synced layer (sync lines out of both, so nothing jumps). */
  swap: number;
  syncedIn: Win;
  green: Win;
  banner: Win;
  /** The banner goes. */
  bannerOut: Win;

  // The owner's phone: the same second phone, relabelled, comes forward with the Team tab.
  relabel: Win;
  /** Sam's map → the Team tab: a cut, like a real tab switch, while that phone is still behind. */
  teamCut: number;
  zSwap: number;
  forward: Win;
  wiresDim: Win;
  rows: Win;
  invite: Win;
  workers: Win;
  /** The owner's name tag makes way for the server (it sits right over it on short screens). */
  ownerOut: Win;
  serverLit: Win;

  // Everything back: the entrance in reverse. The owner's phone steps back to rest while
  // yours comes up to full strength, goes behind it, then recedes and fades out of sight.
  exit: Win;
  exitBack: Win;
  exitSwap: number;
  exitHide: Win;
  exitFade: Win;
  exitDecor: Win;
}

/** Desktop (≥900px): the brief's progress map, beats at 0, .2, .4, .66 and .86. */
export const AT: Schedule = {
  beats: [0, 0.2, 0.4, 0.66, 0.86],

  enter: [0, 0.08],
  pull: [0, 0.07],
  peekIn: [0.005, 0.07],
  chips: [0.03, 0.07],
  server: [0.02, 0.06],
  wires: [0.04, 0.08],

  barsOut: [0.088, 0.142],
  noService: [0.138, 0.156],
  dim: [0.09, 0.16],
  alexWireDim: [0.1, 0.15],
  offlineLayer: 0.16,

  tap: { sam: 0.17, row11: 0.275, row12: 0.345 },
  swingOut: [0.148, 0.168],
  swingBack: [0.266, 0.29],
  samFill: [0.188, 0.208],
  packetSam: [0.208, 0.246],
  pulseSam: [0.244, 0.268],

  fill11: [0.293, 0.31],
  syncIn: [0.304, 0.322],
  queue1: [0.306, 0.318],
  fill12: [0.363, 0.38],
  count: [0.378, 0.39],
  queue2: [0.376, 0.388],

  // A tight sync run so the banner lands early and holds (about 140px of scroll at 1440 × 900).
  barsIn: [0.425, 0.465],
  undim: [0.425, 0.48],
  packetsUp: [0.445, 0.475],
  pulseSync: [0.472, 0.49],
  packetDown: [0.48, 0.505],
  syncOut: [0.497, 0.507],
  swap: 0.507,
  syncedIn: [0.507, 0.522],
  green: [0.508, 0.53],
  banner: [0.512, 0.54],
  bannerOut: [0.624, 0.656],

  relabel: [0.662, 0.688],
  teamCut: 0.69,
  zSwap: 0.7,
  forward: [0.7, 0.78],
  wiresDim: [0.68, 0.72],
  rows: [0.712, 0.78],
  invite: [0.77, 0.792],
  workers: [0.8, 0.84],
  ownerOut: [0.824, 0.84],
  serverLit: [0.84, 0.88],

  exit: [0.9, 0.97],
  exitBack: [0.9, 0.93],
  exitSwap: 0.93,
  exitHide: [0.93, 0.97],
  exitFade: [0.935, 0.96],
  exitDecor: [0.9, 0.95],
};

/** The mobile track (below 900px). Longer than the chapter default: see AT_MOB. */
export const TRACK_MOB = '600vh';

/**
 * Mobile (<900px): the copy cards scroll up over the sticky phone, and each one hides it for
 * about .2 of progress. So the cards sit further apart than on desktop, and each event of the
 * story plays in a window where its part of the phone is clear (a card covers the bottom of
 * the phone first and the top last): Sam's tap and the lost bars before card 1 arrives, your
 * taps once it has passed, the sync with card 2 coming up under the banner, the owner's phone
 * as card 3 comes up, and the server once card 3 has gone. The last card comes to rest just
 * under your phone as the track ends, with the phone back at rest and the server still lit.
 * tests/sections/crew.spec.ts checks each event against the cards at 375 × 812 and 320 × 640.
 */
export const AT_MOB: Schedule = {
  beats: [0, 0.145, 0.505, 0.72, 1],

  enter: [0, 0.06],
  pull: [0, 0.05],
  peekIn: [0, 0.05],
  chips: [0.02, 0.05],
  server: [0.015, 0.045],
  wires: [0.03, 0.06],

  barsOut: [0.062, 0.095],
  noService: [0.093, 0.105],
  dim: [0.065, 0.105],
  alexWireDim: [0.07, 0.1],
  offlineLayer: 0.105,

  tap: { sam: 0.115, row11: 0.232, row12: 0.285 },
  swingOut: [0.098, 0.112],
  swingBack: [0.17, 0.19],
  samFill: [0.12, 0.135],
  packetSam: [0.135, 0.158],
  pulseSam: [0.156, 0.17],

  fill11: [0.236, 0.25],
  syncIn: [0.258, 0.27],
  queue1: [0.258, 0.268],
  fill12: [0.289, 0.303],
  count: [0.303, 0.313],
  queue2: [0.302, 0.312],

  barsIn: [0.325, 0.35],
  undim: [0.325, 0.36],
  packetsUp: [0.34, 0.37],
  pulseSync: [0.367, 0.382],
  packetDown: [0.375, 0.4],
  syncOut: [0.392, 0.4],
  swap: 0.4,
  syncedIn: [0.4, 0.415],
  green: [0.401, 0.423],
  banner: [0.405, 0.43],
  bannerOut: [0.53, 0.56],

  relabel: [0.63, 0.655],
  teamCut: 0.605,
  zSwap: 0.615,
  forward: [0.615, 0.665],
  wiresDim: [0.6, 0.63],
  rows: [0.64, 0.69],
  invite: [0.685, 0.7],
  workers: [0.7, 0.72],
  ownerOut: [0.9, 0.915],
  serverLit: [0.915, 0.945],

  exit: [0.95, 1],
  exitBack: [0.95, 0.965],
  exitSwap: 0.965,
  exitHide: [0.965, 1],
  exitFade: [0.97, 0.995],
  exitDecor: [0.95, 0.975],
};

type DayTrack = ReadonlyArray<{ start: number; end: number; min: Minute }>;

/** DayClock tweens: the minute reached at `end`, from the previous one. */
export const DAY_TRACK: DayTrack = [
  { start: 0, end: 0.08, min: MOMENTS.crew }, // 2:44 → 2:47
  { start: 0.08, end: 0.088, min: OFFLINE.lost }, // 2:48: the bars start to go
  { start: 0.15, end: AT.tap.sam, min: CONFLICT.at }, // 2:49: Sam taps
  { start: 0.26, end: AT.tap.row11, min: kept.at }, // 2:50: Alex taps row 11
  { start: 0.29, end: AT.tap.row12, min: REJECTED.at }, // 2:56: Alex taps row 12
  { start: 0.39, end: AT.barsIn[0], min: OFFLINE.back }, // 3:00: back in range
];

/** The same minutes on the mobile schedule. */
export const DAY_TRACK_MOB: DayTrack = [
  { start: 0, end: AT_MOB.enter[1], min: MOMENTS.crew },
  { start: AT_MOB.enter[1], end: AT_MOB.barsOut[0], min: OFFLINE.lost },
  { start: 0.1, end: AT_MOB.tap.sam, min: CONFLICT.at },
  { start: 0.2, end: AT_MOB.tap.row11, min: kept.at },
  { start: 0.26, end: AT_MOB.tap.row12, min: REJECTED.at },
  { start: AT_MOB.count[1], end: AT_MOB.barsIn[0], min: OFFLINE.back },
];

/** The DayClock minute at progress p (piecewise linear, like the scrubbed tweens). */
export function dayAt(p: number, track: DayTrack = DAY_TRACK): Minute {
  let min = DAY_FROM;
  for (const d of track) {
    if (p <= d.start) return min;
    if (p < d.end) return min + ((d.min - min) * (p - d.start)) / (d.end - d.start);
    min = d.min;
  }
  return min;
}

/** Every window in a schedule, for range checks. */
export function windows(at: Schedule = AT): Array<[string, Win]> {
  const out: Array<[string, Win]> = [];
  for (const [k, v] of Object.entries(at)) {
    if (Array.isArray(v) && v.length === 2 && k !== 'beats') out.push([k, v as unknown as Win]);
  }
  return out;
}
