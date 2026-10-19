/**
 * THE FIELD MAP'S PURE HALF: geometry, tree states from the ledger, the map in words, the
 * static SVG, the field scene's choreography and the Try it model. No DOM and no side effects,
 * so the Try it strip can import it on first load (only what it uses is bundled) while the
 * canvas renderer (src/scripts/fieldmap.ts) stays in its own lazy chunk.
 *
 *   import { createTryIt } from '../fieldstate.ts';          // Try it: first-load safe
 *   import { ensureFieldMap } from '../fieldmap.ts';          // the canvas: lazy
 *
 * GEOMETRY. North field is 14 blocks in 2 strips of 7; a block is 10 trees wide and 61 rows
 * tall. Units are dot pitches. Gutters are 1.5 pitches between blocks and 3 between the strips.
 * World coordinates are the app's portrait layout: blocks 1–7 across the top, row 1 at the top
 * of each block, tree 1 on its left. 'landscape' is that field turned a quarter turn
 * anticlockwise (the desktop overview, about 1.58:1): rows run left to right, block 1 sits
 * bottom left, blocks 8–14 on the right. Because it is a true rotation, the field scene's camera
 * can turn it back upright while it zooms, so the close-up reads like the app on every screen.
 *
 * Unit tests: src/scripts/fieldmap.test.ts.
 */
import {
  CREW_MARKS,
  EARLIER,
  FIELD,
  FIELD_TREES,
  MARKS,
  MOMENTS,
  OFFLINE,
  OLD_NOTE,
  TREE_NOTE,
  WORKER,
  fmtCount,
  fmtTime,
  type Mark,
  type Minute,
  type Person,
  type TreeNote,
} from '../data/ledger.ts';

/** The zoomed close-up: block 2, rows 28–40 (brief: field visuals). */
export const ZOOM_TARGET = { block: 2, from: 28, to: 40 } as const;
/** The row the demo taps and undoes in the zoomed view (still to do at 2:16). */
export const DEMO_ROW = { block: 2, row: 37 } as const;

export interface ZoomTarget {
  block: number;
  from: number;
  to: number;
}

// ---------------------------------------------------------------------------
// Geometry

export type Orientation = 'portrait' | 'landscape';

const ACROSS = FIELD.treesPerRow; // 10
const DOWN = FIELD.rowsPerBlock; // 61
const PER_STRIP = FIELD.blocksPerGridRow; // 7
/** Between blocks in a strip, in pitches. */
export const GUTTER = 1.5;
/** Between the two strips, in pitches. */
export const STRIP_GAP = 3;
/** The world (portrait) grid: 79 × 125 pitches. */
export const GRID_W = PER_STRIP * ACROSS + (PER_STRIP - 1) * GUTTER;
export const GRID_H = FIELD.gridRows * DOWN + (FIELD.gridRows - 1) * STRIP_GAP;

/** Dot radius (green and ring) as a fraction of the pitch; today's gold dot is 20% larger. */
export const DOT_R = 0.3;
export const TODAY_SCALE = 1.2;

export interface Point {
  x: number;
  y: number;
}

export interface Dot {
  /** Cell origin (top-left), in pitches. */
  x: number;
  y: number;
  block: number;
  row: number;
  tree: number;
}

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 0-based index of a tree in every per-tree array: block by block, row by row. */
export const treeIndex = (block: number, row: number, tree: number) => ((block - 1) * DOWN + (row - 1)) * ACROSS + (tree - 1);

/** A world (portrait) point in an orientation's frame. Landscape turns the field a quarter turn anticlockwise. */
export const toFrame = (p: Point, o: Orientation): Point => (o === 'portrait' ? { x: p.x, y: p.y } : { x: p.y, y: GRID_W - p.x });
/** A frame point back in world (portrait) coordinates. */
export const fromFrame = (p: Point, o: Orientation): Point => (o === 'portrait' ? { x: p.x, y: p.y } : { x: GRID_W - p.y, y: p.x });
/** A world rect in an orientation's frame. */
export const rectToFrame = (r: Rect, o: Orientation): Rect =>
  o === 'portrait' ? { ...r } : { x: r.y, y: GRID_W - r.x - r.w, w: r.h, h: r.w };

/** Top-left of a block's dot grid, in the orientation's frame (pitches). */
export function blockOrigin(block: number, orientation: Orientation = 'portrait'): Point {
  const r = blockRect(block, orientation);
  return { x: r.x, y: r.y };
}

/** A block's dot grid as a rect, in the orientation's frame (pitches). */
export function blockRect(block: number, orientation: Orientation = 'portrait'): Rect {
  const b = block - 1;
  const world = { x: (b % PER_STRIP) * (ACROSS + GUTTER), y: Math.floor(b / PER_STRIP) * (DOWN + STRIP_GAP), w: ACROSS, h: DOWN };
  return rectToFrame(world, orientation);
}

/** Centre of one tree's cell, in the orientation's frame (pitches). */
export function dotCenter(block: number, row: number, tree: number, orientation: Orientation = 'portrait'): Point {
  const o = blockRect(block, 'portrait');
  return toFrame({ x: o.x + tree - 0.5, y: o.y + row - 0.5 }, orientation);
}

/** Every dot's cell, in pitches: blocks 10 wide × 61 tall, 1.5-pitch gutters, 3 between grid rows. */
export function fieldLayout(orientation: Orientation = 'portrait'): { width: number; height: number; dots: Dot[] } {
  const dots: Dot[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1)
    for (let row = 1; row <= DOWN; row += 1)
      for (let tree = 1; tree <= ACROSS; tree += 1) {
        const c = dotCenter(block, row, tree, orientation);
        dots.push({ x: c.x - 0.5, y: c.y - 0.5, block, row, tree });
      }
  if (dots.length !== FIELD_TREES) throw new Error('field layout does not add up');
  const [width, height] = orientation === 'portrait' ? [GRID_W, GRID_H] : [GRID_H, GRID_W];
  return { width, height, dots };
}

/**
 * The whole map with room for the 'Block n' labels, in the frame: above each strip in portrait,
 * beside the outer blocks in landscape. Sets the CSS aspect ratio and the SVG fallback's viewBox.
 */
export function frameRect(orientation: Orientation): Rect {
  return orientation === 'portrait'
    ? { x: -0.5, y: -STRIP_GAP, w: GRID_W + 1, h: GRID_H + STRIP_GAP + 0.5 }
    : { x: -7.5, y: -1, w: GRID_H + 15, h: GRID_W + 2 };
}

/**
 * The close-up's rect (world/portrait): the rows, a gutter on the left for their numbers that
 * shows the neighbouring block's last column whole, and the rows just above and below whole
 * (both dimmed as context). No dot is cut by the edge.
 */
export function targetRect(t: ZoomTarget, orientation: Orientation = 'portrait'): Rect {
  const o = blockRect(t.block, 'portrait');
  const n = t.to - t.from + 1;
  return rectToFrame({ x: o.x - 2.6, y: o.y + t.from - 1 - 0.85, w: ACROSS + 2.6 + 0.75, h: n + 1.7 }, orientation);
}

// ---------------------------------------------------------------------------
// Tree states from the ledger

export const EMPTY = 0;
export const EARLIER_S = 1;
export const TODAY = 2;
export type TreeState = typeof EMPTY | typeof EARLIER_S | typeof TODAY;

export interface StatusOptions {
  /** Ledger minute. Default MOMENTS.field (2:16 PM). */
  at?: Minute;
  /** Whose phone: their own current shift is gold, everyone else's marks are green. Default 'Alex'. */
  who?: Person;
  /** Rows forced gold (offline marks shown before sync). */
  pending?: ReadonlyArray<{ block: number; row: number }>;
}

/**
 * Every tree's state at a minute, as seen on `who`'s phone (Uint8Array of EMPTY | EARLIER_S | TODAY).
 *
 * - EARLIER rows are green. Marks fill a row from tree 1 in the order they were made.
 * - Your own marks are gold, including offline ones before they sync. A rejected mark (someone
 *   marked the tree first) stays gold until the sync at OFFLINE.back, then shows the winner's.
 * - Other people's marks are green once this phone has them: not while it is offline, and not
 *   an offline mark before it syncs.
 */
export function treeStatus(opts: StatusOptions = {}): Uint8Array {
  const at = opts.at ?? MOMENTS.field;
  const who = opts.who ?? WORKER;
  const s = new Uint8Array(FIELD_TREES);
  for (const r of EARLIER)
    for (let row = r.from; row <= r.to; row += 1) s.fill(EARLIER_S, treeIndex(r.block, row, 1), treeIndex(r.block, row, ACROSS) + 1);

  const viewerOffline = who === WORKER && at >= OFFLINE.lost && at < OFFLINE.back;
  const synced = at >= OFFLINE.back;
  const cursor = new Map<string, number>();
  const marks: Mark[] = [...MARKS, ...CREW_MARKS].filter((m) => m.at <= at).sort((a, b) => a.at - b.at);
  for (const m of marks) {
    const key = `${m.block}-${m.row}`;
    let from = 1;
    if (!m.rejected) {
      from = (cursor.get(key) ?? 0) + 1;
      cursor.set(key, Math.min(ACROSS, from + m.trees - 1));
    }
    const to = Math.min(ACROSS, from + m.trees - 1);
    const mine = m.by === who;
    let state: TreeState | null = null;
    if (mine) state = m.rejected && synced ? null : TODAY;
    else if (!m.rejected && !(m.offline && !synced) && !(viewerOffline && m.at >= OFFLINE.lost)) state = EARLIER_S;
    if (state === null) continue;
    for (let tree = from; tree <= to; tree += 1) {
      const i = treeIndex(m.block, m.row, tree);
      if (state === TODAY || s[i] !== TODAY) s[i] = state;
    }
  }
  for (const p of opts.pending ?? []) s.fill(TODAY, treeIndex(p.block, p.row, 1), treeIndex(p.block, p.row, ACROSS) + 1);
  return s;
}

export const statusOf = (s: Uint8Array, block: number, row: number, tree: number) => (s[treeIndex(block, row, tree)] ?? EMPTY) as TreeState;

export function countStatus(s: Uint8Array): { empty: number; earlier: number; today: number } {
  const c = { empty: 0, earlier: 0, today: 0 };
  for (const v of s) {
    if (v === TODAY) c.today += 1;
    else if (v === EARLIER_S) c.earlier += 1;
    else c.empty += 1;
  }
  return c;
}

/** Tree notes that exist at a minute (the old Replant note always; Alex's from 2:33 PM). */
export function notesAt(at: Minute): TreeNote[] {
  return at >= MOMENTS.treeNote ? [OLD_NOTE, TREE_NOTE] : [OLD_NOTE];
}

/** Rows with any gold tree, in the order they were first marked (the reveal order). */
export function goldRows(s: Uint8Array): Array<{ block: number; row: number }> {
  const first = new Map<string, number>();
  for (const m of [...MARKS, ...CREW_MARKS]) {
    const key = `${m.block}-${m.row}`;
    first.set(key, Math.min(first.get(key) ?? Infinity, m.at));
  }
  const rows: Array<{ block: number; row: number; t: number }> = [];
  for (let block = 1; block <= FIELD.blocks; block += 1)
    for (let row = 1; row <= DOWN; row += 1) {
      const i = treeIndex(block, row, 1);
      if (s.subarray(i, i + ACROSS).includes(TODAY)) rows.push({ block, row, t: first.get(`${block}-${row}`) ?? Infinity });
    }
  rows.sort((a, b) => a.t - b.t || a.block - b.block || a.row - b.row);
  return rows.map(({ block, row }) => ({ block, row }));
}

export interface Run {
  block: number;
  row0: number;
  row1: number;
  tree0: number;
  tree1: number;
  state: TreeState;
}

/** One block as rectangles of same-state trees: consecutive rows with the same pattern merge. */
export function blockRuns(s: Uint8Array, block: number): Run[] {
  const runs: Run[] = [];
  let open: Run[] = [];
  let prev = -1;
  for (let row = 1; row <= DOWN; row += 1) {
    const i = treeIndex(block, row, 1);
    let same = prev >= 0;
    for (let t = 0; same && t < ACROSS; t += 1) same = s[i + t] === s[prev + t];
    if (same) {
      for (const r of open) r.row1 = row;
    } else {
      open = [];
      for (let t = 0; t < ACROSS; t += 1) {
        const v = (s[i + t] ?? EMPTY) as TreeState;
        const last = open[open.length - 1];
        if (last && last.state === v) last.tree1 = t + 1;
        else open.push({ block, row0: row, row1: row, tree0: t + 1, tree1: t + 1, state: v });
      }
      runs.push(...open);
    }
    prev = i;
  }
  return runs;
}

/** The whole map as runs, block by block. */
export function fieldRuns(s: Uint8Array): Run[] {
  const runs: Run[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) runs.push(...blockRuns(s, block));
  return runs;
}

/** How bright trees outside the close-up's rows are once the camera is in (the target stays at 1). */
export const DIM_FLOOR = 0.22;
/** The outside-the-target alpha at camera c (0 overview → 1 close-up). */
export const dimAt = (camera: number) => {
  const c = Math.min(1, Math.max(0, camera));
  return DIM_FLOOR * c + (1 - c);
};

/** A run cut at the target rows: the part inside keeps alpha 1, the rest gets `dim`. */
export function runPieces(run: Run, target: ZoomTarget, dim: number): Array<{ row0: number; row1: number; alpha: number }> {
  if (dim >= 1) return [{ row0: run.row0, row1: run.row1, alpha: 1 }];
  if (run.block !== target.block || run.row1 < target.from || run.row0 > target.to) return [{ row0: run.row0, row1: run.row1, alpha: dim }];
  const out: Array<{ row0: number; row1: number; alpha: number }> = [];
  if (run.row0 < target.from) out.push({ row0: run.row0, row1: target.from - 1, alpha: dim });
  out.push({ row0: Math.max(run.row0, target.from), row1: Math.min(run.row1, target.to), alpha: 1 });
  if (run.row1 > target.to) out.push({ row0: target.to + 1, row1: run.row1, alpha: dim });
  return out;
}

// ---------------------------------------------------------------------------
// The map in words (the canvases' aria-labels)

/** 'a', 'a and b', 'a, b and c' (the brief's inner lists). */
const listOf = (items: string[]) => (items.length < 2 ? (items[0] ?? '') : `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`);
/** 'a', 'a and b', 'a, b, and c' (the brief's outer list). */
const listOxford = (items: string[]) =>
  items.length < 3 ? listOf(items) : `${items.slice(0, -1).join(', ')}, and ${items[items.length - 1]}`;
const cap = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);
/** Consecutive numbers as runs: [1, 8, 9] → [[1, 1], [8, 9]]. */
function spans(ns: number[]): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  for (const n of ns) {
    const last = out[out.length - 1];
    if (last && last[1] === n - 1) last[1] = n;
    else out.push([n, n]);
  }
  return out;
}
const rowsText = ([a, b]: [number, number]) => (a === b ? `row ${a}` : `rows ${a} to ${b}`);
const blocksText = ([a, b]: [number, number]) => (a === b ? `block ${a}` : b === a + 1 ? `blocks ${a} and ${b}` : `blocks ${a} to ${b}`);

/**
 * The whole field in words, built from the ledger at `at` (the overview canvas's aria-label). At
 * 2:16 PM it is exactly the brief's sentence.
 */
export function fieldSummary(at: Minute = MOMENTS.field, who: Person = WORKER): string {
  const s = treeStatus({ at, who });
  const rowKind = (block: number, row: number, v: TreeState) => {
    const i = treeIndex(block, row, 1);
    const r = s.subarray(i, i + ACROSS);
    return r.every((x) => x === v) ? 'all' : r.includes(v) ? 'part' : 'none';
  };
  // Gold: per block, its full rows as ranges and any part rows.
  const gold: string[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    const full: number[] = [];
    const parts: string[] = [];
    for (let row = 1; row <= DOWN; row += 1) {
      const k = rowKind(block, row, TODAY);
      if (k === 'all') full.push(row);
      else if (k === 'part') parts.push(`part of row ${row}`);
    }
    const items = [...spans(full).map(rowsText), ...parts];
    if (items.length) gold.push(`${listOf(items)} of block ${block}`);
  }
  // Green: whole blocks, the first rows of blocks, then any other green rows.
  const whole: number[] = [];
  const firstRows: number[] = [];
  const other: string[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    const green = Array.from({ length: DOWN }, (_, r) => rowKind(block, r + 1, EARLIER_S));
    if (green.every((k) => k === 'all')) {
      whole.push(block);
      continue;
    }
    let prefix = 0;
    while (prefix < DOWN && green[prefix] === 'all') prefix += 1;
    if (prefix > 0) firstRows.push(block);
    const rest: number[] = [];
    const parts: string[] = [];
    for (let r = prefix; r < DOWN; r += 1) {
      if (green[r] === 'all') rest.push(r + 1);
      else if (green[r] === 'part') parts.push(`part of row ${r + 1}`);
    }
    const items = [...spans(rest).map(rowsText), ...parts];
    if (items.length) other.push(`${listOf(items)} of block ${block}`);
  }
  const greenItems = [
    ...spans(whole).map(blocksText),
    ...(firstRows.length ? [`the first rows of ${firstRows.length === 1 ? 'block' : 'blocks'} ${listOf(firstRows.map(String))}`] : []),
    ...other,
  ];
  const head = `Map of ${FIELD.name}: ${FIELD.blocks} blocks of ${DOWN} rows, ${ACROSS} trees a row, ${fmtCount(FIELD_TREES)} trees.`;
  const today = gold.length ? ` ${cap(listOxford(gold))} shaped today in gold.` : ' Nothing shaped today yet.';
  const earlier = greenItems.length ? ` ${cap(listOxford(greenItems))} shaped earlier in green.` : '';
  return `${head}${today}${earlier} The rest not yet shaped.`;
}

/** The close-up in words, from the ledger: the zoomed canvas's aria-label. */
export function zoomSummary(t: ZoomTarget = ZOOM_TARGET, at: Minute = MOMENTS.field, notes: readonly TreeNote[] = notesAt(at)): string {
  const s = treeStatus({ at });
  const kind = (row: number) => {
    const i = treeIndex(t.block, row, 1);
    const r = s.subarray(i, i + ACROSS);
    if (r.every((v) => v === TODAY)) return 'shaped today in gold';
    if (r.every((v) => v === EARLIER_S)) return 'shaped earlier in green';
    if (r.every((v) => v === EMPTY)) return 'not yet shaped';
    return 'partly shaped';
  };
  const parts: string[] = [];
  let from = t.from;
  for (let row = t.from; row <= t.to; row += 1) {
    if (row < t.to && kind(row + 1) === kind(row)) continue;
    parts.push(`${from === row ? `row ${row}` : `rows ${from} to ${row}`} ${kind(row)}`);
    from = row + 1;
  }
  const flags = notes
    .filter((n) => n.block === t.block && n.row >= t.from && n.row <= t.to)
    .map((n) => ` A flag marks a tree note on row ${n.row}, tree ${n.tree}: ${n.flag}.`)
    .join('');
  return `Close-up of block ${t.block}, rows ${t.from} to ${t.to}, ${ACROSS} trees a row: ${cap(parts.join(', '))}.${flags}`;
}

// ---------------------------------------------------------------------------
// Static SVG (server-rendered first paint, no-JS fallback)

/** The rust flag (the app's flag.fill glyph, 24 × 24). The pole's foot is at (5.6, 21.2). */
export const FLAG_PATH =
  'M5.6 2.8c.5 0 .9.4.9.9v.1h10.9c.7 0 1.1.7.8 1.3l-2.4 3.9 2.4 3.9c.4.6 0 1.3-.8 1.3H6.5v7c0 .5-.4.9-.9.9s-.9-.4-.9-.9V3.7c0-.5.4-.9.9-.9Z';
export const FLAG_FOOT = { x: 5.6, y: 21.2 } as const;

export interface Theme {
  ring: string;
  earlier: string;
  today: string;
  note: string;
  noteEdge: string;
  label: string;
  labelHot: string;
  pulse: string;
}

/** Page map colours on the dark stage (brief: designSystem, PAGE MAP DOTS). */
export const STAGE_THEME: Theme = {
  ring: '#6F8F7A',
  earlier: '#2E7A4E',
  today: '#E2A644',
  note: '#C2462A',
  noteEdge: '#F2F5EF',
  label: '#A8BBAE',
  labelHot: '#E2A644',
  pulse: '#E2A644',
};

const n2 = (v: number) => String(Math.round(v * 1000) / 1000);

export interface SvgOptions {
  orientation: Orientation;
  at?: Minute;
  who?: Person;
  /** Draw the close-up of these rows (portrait, row numbers on the left) instead of the whole field. */
  zoom?: ZoomTarget;
  notes?: readonly TreeNote[];
  /** Unique per page: pattern ids must not collide between instances. */
  id?: string;
  theme?: Theme;
  class?: string;
}

/**
 * The map as an inline SVG string: one patterned rect per run, so the whole field is a few KB.
 * Rendered by FieldMap.astro under the canvas for first paint and for visitors without JS. It
 * matches the canvas's final state, including the close-up's dimmed surroundings.
 */
export function fieldSVG(o: SvgOptions): string {
  const t = o.theme ?? STAGE_THEME;
  const id = o.id ?? 'fm';
  const at = o.at ?? MOMENTS.field;
  const s = treeStatus({ at, who: o.who });
  const notes = o.notes ?? notesAt(at);
  const z = o.zoom;
  // The close-up is always upright; the overview follows the orientation.
  const frame: Orientation = z ? 'portrait' : o.orientation;
  const vb = z ? targetRect(z) : frameRect(frame);
  const fills = [`url(#${id}-r)`, `url(#${id}-e)`, `url(#${id}-t)`];
  const out: string[] = [];
  out.push(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${n2(vb.x)} ${n2(vb.y)} ${n2(vb.w)} ${n2(vb.h)}" preserveAspectRatio="xMidYMid meet" aria-hidden="true" focusable="false"${o.class ? ` class="${o.class}"` : ''}>`,
    '<defs>',
    // The ring's stroke is ~1.5px at either scale (the overview's pitch is ~9px, the close-up's ~24px).
    `<pattern id="${id}-r" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r="${n2(DOT_R - (z ? 0.035 : 0.07))}" fill="none" stroke="${t.ring}" stroke-width="${z ? '.07' : '.14'}"/></pattern>`,
    `<pattern id="${id}-e" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r="${DOT_R}" fill="${t.earlier}"/></pattern>`,
    `<pattern id="${id}-t" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r="${n2(DOT_R * TODAY_SCALE)}" fill="${t.today}"/></pattern>`,
    '</defs>',
  );
  // Dots in world (portrait) coordinates, turned into the landscape frame by one transform.
  out.push(frame === 'landscape' ? `<g transform="matrix(0 -1 1 0 0 ${n2(GRID_W)})">` : '<g>');
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    const og = blockOrigin(block);
    if (z) {
      // Only the blocks the close-up can see.
      const r = blockRect(block);
      if (r.x > vb.x + vb.w || r.x + r.w < vb.x) continue;
    }
    out.push(`<g transform="translate(${n2(og.x)} ${n2(og.y)})">`);
    for (const r of blockRuns(s, block)) {
      if (z && (r.row1 < z.from - 1 || r.row0 > z.to + 1)) continue;
      for (const p of z ? runPieces(r, z, DIM_FLOOR) : [{ row0: r.row0, row1: r.row1, alpha: 1 }]) {
        const [row0, row1] = z ? [Math.max(p.row0, z.from - 1), Math.min(p.row1, z.to + 1)] : [p.row0, p.row1];
        if (row1 < row0) continue;
        out.push(
          `<rect x="${r.tree0 - 1}" y="${row0 - 1}" width="${r.tree1 - r.tree0 + 1}" height="${row1 - row0 + 1}" fill="${fills[r.state]}"${p.alpha < 1 ? ` opacity="${p.alpha}"` : ''}/>`,
        );
      }
    }
    out.push('</g>');
  }
  out.push('</g>');

  // Block labels.
  if (!z) {
    const fs = frame === 'portrait' ? 1.7 : 1.35;
    out.push(`<g fill="${t.label}" font-size="${fs}" class="fm-svg-label">`);
    for (let b = 1; b <= FIELD.blocks; b += 1) {
      const r = blockRect(b, frame);
      if (frame === 'portrait') out.push(`<text x="${n2(r.x)}" y="${n2(r.y - 0.8)}">Block ${b}</text>`);
      else if (b <= PER_STRIP) out.push(`<text x="${n2(r.x - 0.9)}" y="${n2(r.y + r.h / 2 + fs * 0.35)}" text-anchor="end">Block ${b}</text>`);
      else out.push(`<text x="${n2(r.x + r.w + 0.9)}" y="${n2(r.y + r.h / 2 + fs * 0.35)}">Block ${b}</text>`);
    }
    out.push('</g>');
  }

  // Row numbers in the close-up, on the left.
  if (z) {
    const og = blockOrigin(z.block);
    out.push(`<g fill="${t.label}" font-size=".54" class="fm-svg-label">`);
    for (let row = z.from; row <= z.to; row += 1)
      out.push(`<text x="${n2(og.x - 0.7)}" y="${n2(og.y + row - 0.5 + 0.19)}" text-anchor="end">${row}</text>`);
    out.push('</g>');
  }

  // Note flags: the pole's foot on the tree, the flag up and to the right.
  const fsz = z ? 0.9 : 1.7;
  for (const n of notes) {
    const c = dotCenter(n.block, n.row, n.tree, frame);
    const k = fsz / 24;
    const dim = z && !(n.block === z.block && n.row >= z.from && n.row <= z.to) ? ` opacity="${DIM_FLOOR}"` : '';
    out.push(
      `<path data-note="${n.block}-${n.row}-${n.tree}" d="${FLAG_PATH}" transform="translate(${n2(c.x - FLAG_FOOT.x * k)} ${n2(c.y - FLAG_FOOT.y * k)}) scale(${n2(k)})" fill="${t.note}" stroke="${t.noteEdge}" stroke-width="1.6" stroke-linejoin="round" paint-order="stroke"${dim}/>`,
    );
  }
  out.push('</svg>');
  return out.join('');
}

// ---------------------------------------------------------------------------
// The field scene's choreography (brief: sections.field.animation)

/** Progress windows of the field section's scrubbed timeline. */
export const BEATS = {
  /** Block 2 rows 14→36 flip ring → gold, one row per 1/23 of the window, each with a pop. */
  reveal: [0.3, 0.52],
  /** The camera zooms to block 2 rows 28–40 (and, on a landscape canvas, turns the field upright). */
  zoomIn: [0.52, 0.58],
  labelsIn: [0.55, 0.59],
  /** Row 37's number pulses with a touch ring. */
  touch: [0.59, 0.625],
  /** Row 37 fills gold… */
  demoIn: [0.61, 0.64],
  /** …the Undo chip pulses (a DOM overlay the scene owns)… */
  undo: [0.64, 0.67],
  /** …and row 37 goes back to rings: the ledger still has it to do at 2:16. */
  demoOut: [0.67, 0.7],
  /** Season flip: gold and green fade to rings; the note stays. */
  seasonOut: [0.73, 0.81],
  pulse: [0.79, 0.87],
  /** Back to this season, then out to the overview. */
  seasonIn: [0.88, 0.92],
  labelsOut: [0.88, 0.9],
  zoomOut: [0.9, 0.98],
} as const satisfies Record<string, readonly [number, number]>;

export interface MapState {
  /** Ledger minute for every tree's state. */
  at: Minute;
  /** Gold rows revealed so far, in mark order (fractional = the next row popping); null = all. */
  reveal: number | null;
  /** 0 = overview, 1 = zoomed to the target. */
  camera: number;
  /** Row-number alpha in the zoomed view. */
  labels: number;
  /** Alpha of the demo row's gold fill. */
  demo: number;
  /** 0 = this season, 1 = next season (every fill faded to rings; notes stay). */
  season: number;
  /** 0–1 progress of the note markers' pulse ring (0 and 1 draw nothing). */
  pulse: number;
  /** 0–1 progress of the touch ring on the demo row's number. */
  touch: number;
  /** 0–1 progress of the Undo chip's pulse (for the scene's DOM chip; the canvas ignores it). */
  undo: number;
}

export const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
const ramp = (p: number, w: readonly [number, number]) => clamp01((p - w[0]) / (w[1] - w[0]));
const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
/** Lingers on a value until `w2` starts, then returns: in over w1, out over w2. */
const inOut = (p: number, w1: readonly [number, number], w2: readonly [number, number], ease = (t: number) => t) =>
  p < w2[0] ? ease(ramp(p, w1)) : 1 - ease(ramp(p, w2));

let revealRows: number | null = null;
/** How many gold rows the reveal walks through at 2:16 PM (23). */
export function revealCount(): number {
  revealRows ??= goldRows(treeStatus({ at: MOMENTS.field })).length;
  return revealRows;
}

/** What the field canvas shows at section progress p (0–1). Pure. */
export function sceneState(p: number): MapState {
  const q = clamp01(p);
  return {
    at: MOMENTS.field,
    reveal: revealCount() * ramp(q, BEATS.reveal),
    camera: inOut(q, BEATS.zoomIn, BEATS.zoomOut, easeInOut),
    labels: inOut(q, BEATS.labelsIn, BEATS.labelsOut),
    demo: inOut(q, BEATS.demoIn, BEATS.demoOut),
    season: inOut(q, BEATS.seasonOut, BEATS.seasonIn),
    pulse: ramp(q, BEATS.pulse),
    touch: ramp(q, BEATS.touch),
    undo: ramp(q, BEATS.undo),
  };
}

/** The static final state (reduced motion, no scene yet). */
export function finalState(view: 'overview' | 'zoom' = 'overview', at: Minute = MOMENTS.field): MapState {
  const z = view === 'zoom' ? 1 : 0;
  return { at, reveal: null, camera: z, labels: z, demo: 0, season: 0, pulse: 0, touch: 0, undo: 0 };
}

// ---------------------------------------------------------------------------
// Try it (pure): the page's small interactive copy of block 2 rows 28–40

export type TapMode = 'one' | 'fill' | 'erase';

export interface TryIt {
  /** The rows shown, inclusive. */
  readonly rows: [number, number];
  /** Fill mode's first tree, waiting for the second tap. */
  readonly anchor: { row: number; tree: number } | null;
  readonly canUndo: boolean;
  get(row: number, tree: number): TreeState;
  /** A row number: marks the row's free trees, or clears yours when none are free (always in erase). */
  rowTap(row: number, mode?: TapMode): string;
  treeTap(row: number, tree: number, mode: TapMode): string;
  undo(): string;
  /** Back to the ledger state. */
  reset(): string;
}

/**
 * The Try it strip's model: starts from the ledger at `at`, never changes trees someone else
 * shaped (green), and returns the sentence for the polite live region after every action.
 * Nothing is saved anywhere.
 */
export function createTryIt(target: ZoomTarget = ZOOM_TARGET, at: Minute = MOMENTS.field): TryIt {
  const n = target.to - target.from + 1;
  const start = new Uint8Array(n * ACROSS);
  const ledger = treeStatus({ at });
  for (let r = 0; r < n; r += 1)
    for (let t = 0; t < ACROSS; t += 1) start[r * ACROSS + t] = statusOf(ledger, target.block, target.from + r, t + 1);
  let cells: Uint8Array = start.slice();
  const history: Uint8Array[] = [];
  let anchor: { row: number; tree: number } | null = null;
  const at0 = (row: number, tree: number) => (row - target.from) * ACROSS + tree - 1;
  const trees = (k: number) => `${k} tree${k === 1 ? '' : 's'}`;
  const spot = (row: number, tree: number) => `row ${row}, tree ${tree}`;
  const Spot = (row: number, tree: number) => `Row ${row}, tree ${tree}`;
  const commit = (next: Uint8Array) => {
    history.push(cells);
    cells = next;
  };
  return {
    rows: [target.from, target.to],
    get anchor() {
      return anchor;
    },
    get canUndo() {
      return history.length > 0;
    },
    get: (row, tree) => (cells[at0(row, tree)] ?? EMPTY) as TreeState,
    rowTap(row, mode = 'one') {
      anchor = null;
      const idx = Array.from({ length: ACROSS }, (_, t) => at0(row, t + 1));
      const free = idx.filter((i) => cells[i] === EMPTY);
      const mine = idx.filter((i) => cells[i] === TODAY);
      const next = cells.slice();
      if (mode === 'erase' || (free.length === 0 && mine.length > 0)) {
        if (mine.length === 0) return `Nothing in row ${row} is marked`;
        for (const i of mine) next[i] = EMPTY;
        commit(next);
        return `Row ${row} cleared, ${trees(mine.length)}`;
      }
      if (free.length === 0) return `Every tree in row ${row} was shaped earlier`;
      for (const i of free) next[i] = TODAY;
      commit(next);
      return `Row ${row} marked, ${trees(free.length)}`;
    },
    treeTap(row, tree, mode) {
      const i = at0(row, tree);
      const v = cells[i];
      if (v === EARLIER_S) return `${Spot(row, tree)} was shaped earlier`;
      const next = cells.slice();
      if (mode === 'fill') {
        if (!anchor) {
          anchor = { row, tree };
          return `${Spot(row, tree)}. Now tap the last tree`;
        }
        if (anchor.row === row && anchor.tree === tree) {
          anchor = null;
          return 'Start over: tap the first tree';
        }
        const [a, b] = [at0(anchor.row, anchor.tree), i].sort((x, y) => x - y) as [number, number];
        anchor = null;
        let k = 0;
        for (let j = a; j <= b; j += 1)
          if (next[j] === EMPTY) {
            next[j] = TODAY;
            k += 1;
          }
        const from = { row: target.from + Math.floor(a / ACROSS), tree: (a % ACROSS) + 1 };
        const to = { row: target.from + Math.floor(b / ACROSS), tree: (b % ACROSS) + 1 };
        if (k === 0) return 'Nothing new to mark there';
        commit(next);
        return `Marked ${trees(k)}, from ${spot(from.row, from.tree)} to ${spot(to.row, to.tree)}`;
      }
      anchor = null;
      if (mode === 'erase' && v !== TODAY) return `${Spot(row, tree)} isn’t marked`;
      next[i] = v === TODAY ? EMPTY : TODAY;
      commit(next);
      return `${Spot(row, tree)} ${v === TODAY ? 'unmarked' : 'marked'}`;
    },
    undo() {
      anchor = null;
      const prev = history.pop();
      if (!prev) return 'Nothing to undo';
      cells = prev;
      return 'Undid your last change';
    },
    reset() {
      anchor = null;
      cells = start.slice();
      history.length = 0;
      return `Back to the map at ${fmtTime(at)}`;
    },
  };
}
