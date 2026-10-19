/**
 * THE FIELD SECTION'S PAGE CHOREOGRAPHY (pure, unit-tested in plan.test.ts).
 *
 * The canvas follows sceneState(p) and BEATS from src/scripts/fieldstate.ts (the map team's
 * half of the brief's field.animation). This file times everything the page draws around it to
 * the same beats: the stage phone leaving and coming back, the tilt flattening, the counter
 * strip, the legend, the three cards, the season chip, the Undo chip and the final fade.
 * Every number comes from the ledger; nothing here touches the DOM.
 */
import { EARLIER_COUNT, FIELD_TREES, MOMENTS, fieldShapedAt, fmtCount, treesAt } from '../../data/ledger.ts';
import { FIELD } from '../../data/ledger.ts';
import { BEATS, revealCount, sceneState } from '../../scripts/fieldstate.ts';

export type Win = readonly [number, number];

/** The counter strip's final values at 2:15 PM. */
export const COUNTS = {
  trees: FIELD_TREES,
  earlier: EARLIER_COUNT,
  today: treesAt(MOMENTS.field),
  shaped: fieldShapedAt(MOMENTS.field),
} as const;

export interface Counts {
  trees: number;
  shaped: number;
  today: number;
}

/** '8,540 trees · 2,420 shaped · 230 today' (the strip, and its screen-reader text). */
export const stripText = (c: Counts) => `${fmtCount(c.trees)} trees · ${fmtCount(c.shaped)} shaped · ${fmtCount(c.today)} today`;

/** Progress windows of the page-level parts (brief: sections.field.animation). */
export const WIN = {
  /** The stage phone fades to 0 and scale .96 (desktop). */
  phoneOut: [0, 0.1],
  /** The heading block fades as it scrolls up, before the counter strip arrives under it (desktop). */
  headOut: [0.09, 0.19],
  /** The tilted field flattens to face the viewer. */
  flatten: [0.1, 0.3],
  /** The horizon haze over the far rows lifts. */
  haze: [0.1, 0.24],
  /** Trees 0 → 8,540 and shaped 0 → 2,190. */
  count: [0.1, 0.3],
  /** The counter strip, season chip and legend fade in. */
  chrome: [0.15, 0.28],
  /** The close-up's soft edges (a vignette over the dimmed context) follow the camera in and out. */
  edgesIn: [BEATS.zoomIn[0] + 0.02, BEATS.zoomIn[1]],
  edgesOut: [BEATS.zoomOut[0], BEATS.zoomOut[0] + 0.04],
  /** The Undo chip by row 37: in after the row fills, tapped, out as the row goes back to rings. */
  undoIn: [BEATS.demoIn[1] - 0.006, BEATS.undo[0] + 0.006],
  undoTap: (BEATS.undo[0] + BEATS.undo[1]) / 2,
  undoOut: [BEATS.demoOut[0] + 0.012, BEATS.demoOut[1] + 0.004],
  /** Phones: the season chip shows only around the season flip (in, then out once it rolls back). */
  seasonChip: [BEATS.seasonOut[0] - 0.03, BEATS.seasonIn[1] + 0.005],
  /** The map, strip and legend fade as the camera settles back on the overview. */
  mapOut: [0.95, 0.978],
  /** The stage phone comes back with the Trees tab once the map has mostly gone (at rest by 1). */
  phoneIn: [0.97, 1],
} as const satisfies Record<string, Win | number>;

export interface CardWindow {
  in: Win;
  out: Win;
}

/** Card 1 while today's rows flip to gold, card 2 through the zoom and the row 37 demo, card 3 for the season flip. */
export const CARDS: readonly CardWindow[] = [
  { in: [0.31, 0.345], out: [0.515, 0.54] },
  { in: [0.545, 0.585], out: [0.705, 0.735] },
  { in: [0.74, 0.78], out: [0.875, 0.9] },
];

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
const ramp = (p: number, w: Win) => clamp01((p - w[0]) / (w[1] - w[0]));
const easeOut = (t: number) => 1 - (1 - t) * (1 - t);

/** 0 = this season, 1 = next season (follows the canvas: out over seasonOut, back over seasonIn). */
export function seasonAt(p: number): number {
  const q = clamp01(p);
  return q < BEATS.seasonIn[0] ? ramp(q, BEATS.seasonOut) : 1 - ramp(q, BEATS.seasonIn);
}

/**
 * The counter strip at progress p. Trees and the earlier shaped count roll up while the field
 * flattens; today's trees count up ten at a time as each row flips to gold (in step with the
 * canvas); the row 37 demo adds its row while it is gold and Undo takes it back; next season
 * everything shaped goes back to zero, then returns.
 */
export function countsAt(p: number): Counts {
  const q = clamp01(p);
  const c = easeOut(ramp(q, WIN.count));
  const rows = revealCount();
  const per = COUNTS.today / rows;
  const flipped = Math.min(rows, Math.max(0, Math.ceil(rows * ramp(q, BEATS.reveal) - 1e-9)));
  const keep = 1 - seasonAt(q);
  const demo = sceneState(q).demo >= 0.5 ? FIELD.treesPerRow : 0;
  const today = (Math.round(flipped * keep) * per || 0) + demo;
  const earlier = Math.round(COUNTS.earlier * c * keep);
  return { trees: Math.round(COUNTS.trees * c), shaped: earlier + today, today };
}

/** Which card shows at p: 1–3, or 0 for none. */
export function cardAt(p: number): number {
  const i = CARDS.findIndex((c) => p >= c.in[0] && p < c.out[1]);
  return i + 1;
}
