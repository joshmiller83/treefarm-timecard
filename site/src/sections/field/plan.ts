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
import {
  BEATS,
  DOT_R,
  TODAY_SCALE,
  ZOOM_TARGET,
  blockRect,
  dotCenter,
  revealCount,
  sceneState,
  targetRect,
  type ZoomTarget,
} from '../../scripts/fieldstate.ts';

export type Win = readonly [number, number];

/** The counter strip's final values at 2:16 PM. */
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
  /** Desktop: the tilted field fades in under the leaving phone (no rows showing through its screen). */
  camIn: [0.04, 0.12],
  /**
   * Desktop: whatever is left of the heading (a tall one, on a short screen) fades before the
   * flattening field reaches it. Its lines already fade by position as they near the strip.
   */
  headOut: [0.15, 0.22],
  /** The tilted field flattens to face the viewer. */
  flatten: [0.1, 0.3],
  /** The horizon haze over the far rows lifts. */
  haze: [0.1, 0.24],
  /** Trees 0 → 8,540 and shaped 0 → 2,190. */
  count: [0.1, 0.3],
  /** The counter strip, season chip and legend fade in. */
  chrome: [0.15, 0.28],
  /**
   * The close-up's soft edges (a vignette over the dimmed context). They are up before the camera
   * has really moved and stay until it is back on the overview, so the turning field is never cut
   * by the canvas box's hard edges.
   */
  edgesIn: [BEATS.zoomIn[0], BEATS.zoomIn[0] + 0.025],
  edgesOut: [BEATS.zoomOut[1] - 0.02, BEATS.zoomOut[1]],
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

/** Phones: the scrim under the card sheet is up from card 1 in to card 3 out. */
export const SHEET: CardWindow = { in: CARDS[0]!.in, out: CARDS[2]!.out };
/** Phones: the close-up eases from clearing card 2 to clearing card 3 (shorter) while they swap. */
export const SETTLE: Win = [CARDS[1]!.out[0], CARDS[2]!.in[0] + 0.01];

/**
 * The heading's fade (both layouts). Its lines are gone at `line`, the top of the field frame's own
 * content (the counter strip; on phones the sticky frame's top, under the header and its chip), and
 * whole again `fade` px below it (Field.astro's mask uses the same 64px), so no line ever runs under the header, the rail or the strip.
 * Returns the mask's --cut: px from the heading's top down to where it is fully opaque (0 = whole).
 * `headTop` is the heading's top in the viewport.
 */
export const HEAD_FADE = 64;
export function headCut(line: number, headTop: number, fade: number = HEAD_FADE): number {
  return Math.max(0, line + fade - headTop);
}

/** The phone close-up's layout, in px from the top of the field figure (camera at rest on the close-up). */
export interface CloseUpBox {
  /** Top of row 28's dots and bottom of row 40's, before any rise. */
  targetTop: number;
  targetBottom: number;
  /** Bottom of the counter strip. */
  stripBottom: number;
  /** Tops of card 2 (the demo) and card 3 (the season flip). */
  cardTops: readonly [number, number];
  /** The season chip's height. */
  chipH: number;
}
/** Space kept between the rows and a card, and around the season chip. */
export const CLEAR = 12;

/**
 * Phones: how far the close-up rises (px) so rows 28–40 sit centred between the counter strip and
 * card 2, then card 3, and always clear of the card when there is room; never sliding under the
 * strip. And where the season chip sits: just above row 28 at the season beat (card 3's rise),
 * but never over the strip.
 */
export function phoneCloseUp(g: CloseUpBox): { dz: readonly [number, number]; chipTop: number } {
  const most = Math.max(0, g.targetTop - (g.stripBottom + CLEAR));
  const mid = (g.targetTop + g.targetBottom) / 2;
  const rise = (cardTop: number) => {
    const clear = g.targetBottom + CLEAR - cardTop;
    const centred = mid - (g.stripBottom + cardTop) / 2;
    return Math.min(most, Math.max(0, clear, centred));
  };
  const dz = [rise(g.cardTops[0]), rise(g.cardTops[1])] as const;
  const chipTop = Math.max(g.stripBottom + 4, g.targetTop - dz[1] - g.chipH - 8);
  return { dz, chipTop };
}

/**
 * The static close-up's soft edges, in pitches in from each side of its rect: the mask is clear at
 * `clear` and opaque from `solid`. Only the dimmed context fades (block 1's last column on the
 * left, rows 27 and 41); the row numbers and every dot of rows 28–40 stay whole. The row numbers
 * are 13px Plex Mono at a 24px pitch (0.54 pitch, two digits at 0.6em), right-aligned 0.7 pitch
 * left of the block.
 */
export function zoomEdgeFade(t: ZoomTarget = ZOOM_TARGET) {
  const r = targetRect(t);
  const gold = DOT_R * TODAY_SCALE;
  const first = dotCenter(t.block, t.from, 1);
  const last = dotCenter(t.block, t.to, FIELD.treesPerRow);
  const numbersLeft = blockRect(t.block).x - 0.7 - 2 * 0.6 * 0.54;
  const m = 0.05;
  return {
    w: r.w,
    h: r.h,
    left: { clear: 0.25, solid: numbersLeft - r.x - m },
    right: { solid: r.x + r.w - (last.x + gold) - m, clear: -0.3 },
    top: { clear: 0.1, solid: first.y - gold - r.y - m },
    bottom: { solid: r.y + r.h - (last.y + gold) - m, clear: 0.1 },
  };
}

/**
 * Phones: the top of the scrim under the card sheet at progress p, following the card that shows
 * (each card's top, px): card 1's until it hands over to card 2, then card 2's, then card 3's.
 */
export function sheetTopAt(p: number, tops: readonly [number, number, number]): number {
  const smooth = (k: number) => k * k * (3 - 2 * k);
  const a = smooth(ramp(clamp01(p), [CARDS[0]!.out[0], CARDS[1]!.in[1]]));
  const b = smooth(ramp(clamp01(p), SETTLE));
  return tops[0] + (tops[1] - tops[0]) * a + (tops[2] - tops[1]) * b;
}

/** The close-up's rise at progress p for the camera's zoom amount (0 overview → 1 close-up). */
export function riseAt(p: number, camera: number, dz: readonly [number, number]): number {
  const k = ramp(clamp01(p), SETTLE);
  return clamp01(camera) * (dz[0] + (dz[1] - dz[0]) * (k * k * (3 - 2 * k)));
}

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
