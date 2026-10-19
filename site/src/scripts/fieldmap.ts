/**
 * THE FIELD MAP: 8,540 trees as dots.
 *
 * One module for everything the map needs, in four layers:
 *
 *   1. Geometry (pure). North field is 14 blocks in 2 strips of 7; a block is 10 trees wide
 *      and 61 rows tall. Units are dot pitches. Gutters are 1.5 pitches between blocks and
 *      3 between the strips. 'portrait' is the app's layout (blocks 1–7 across the top);
 *      'landscape' is the same field transposed, so the desktop overview is wide
 *      (rows run down the screen, 125 × 79 pitches, about 1.58:1).
 *   2. State from the ledger (pure). treeStatus({ at, who }) gives every tree's state at a
 *      minute: gold = this person's current shift, green = shaped earlier by anyone,
 *      ring = not yet (decisions.md #4), with offline marks and first-mark-wins.
 *   3. The field scene's choreography (pure). sceneState(p) maps section progress 0–1 to
 *      what the canvas shows (brief: field.animation), so a scene only calls setProgress.
 *   4. The Canvas 2D renderer (DOM). Sprites are pre-rendered per dot size, the overview is
 *      cached in one offscreen bitmap and only changed rows are redrawn into it, zoomed views
 *      cull to the viewport, and nothing redraws unless the state changes.
 *
 * FieldMap.astro loads this module lazily (IntersectionObserver, rootMargin 100%) and calls
 * ensureFieldMap(canvas). A scene drives the same instance:
 *
 *   import { ensureFieldMap } from '../fieldmap.ts';
 *   const map = ensureFieldMap(q1<HTMLCanvasElement>('canvas[data-fieldmap]')!);
 *   tl.eventCallback('onUpdate', () => map.setProgress(tl.progress()));   // or draw({...})
 *
 * Pure parts are unit-tested in tests/unit/fieldmap.test.ts; nothing touches the DOM at import.
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
  type Mark,
  type Minute,
  type Person,
  type TreeNote,
} from '../data/ledger.ts';

/** The canvas's accessible summary, from the ledger (brief: FieldMap ACCESSIBILITY). */
export const FIELD_SUMMARY =
  'Map of North field: 14 blocks of 61 rows, 10 trees a row, 8,540 trees. Rows 14 to 36 of block 2 shaped today in gold. Block 1, blocks 8 and 9, and the first rows of blocks 2, 3 and 4 shaped earlier in green. The rest not yet shaped.';

/** The zoomed close-up: block 2, rows 28–40 (brief: field visuals). */
export const ZOOM_TARGET = { block: 2, from: 28, to: 40 } as const;
/** The row the demo taps and undoes in the zoomed view (still to do at 2:15). */
export const DEMO_ROW = { block: 2, row: 37 } as const;

export interface ZoomTarget {
  block: number;
  from: number;
  to: number;
}

// ---------------------------------------------------------------------------
// 1. Geometry

export type Orientation = 'portrait' | 'landscape';

const ACROSS = FIELD.treesPerRow; // 10
const DOWN = FIELD.rowsPerBlock; // 61
const PER_STRIP = FIELD.blocksPerGridRow; // 7
/** Between blocks in a strip, in pitches. */
export const GUTTER = 1.5;
/** Between the two strips, in pitches. */
export const STRIP_GAP = 3;
/** Grid size in portrait: 79 × 125 pitches. */
const GRID_W = PER_STRIP * ACROSS + (PER_STRIP - 1) * GUTTER;
const GRID_H = FIELD.gridRows * DOWN + (FIELD.gridRows - 1) * STRIP_GAP;

/** Dot radius (green and ring) as a fraction of the pitch; today's gold dot is 20% larger. */
export const DOT_R = 0.3;
export const TODAY_SCALE = 1.2;

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

/** Top-left of a block's dot grid, in pitches. */
export function blockOrigin(block: number, orientation: Orientation = 'portrait'): { x: number; y: number } {
  const b = block - 1;
  const across = (b % PER_STRIP) * (ACROSS + GUTTER);
  const down = Math.floor(b / PER_STRIP) * (DOWN + STRIP_GAP);
  return orientation === 'portrait' ? { x: across, y: down } : { x: down, y: across };
}

/** A block's dot grid as a rect, in pitches. */
export function blockRect(block: number, orientation: Orientation = 'portrait'): Rect {
  const o = blockOrigin(block, orientation);
  return orientation === 'portrait' ? { x: o.x, y: o.y, w: ACROSS, h: DOWN } : { x: o.x, y: o.y, w: DOWN, h: ACROSS };
}

/** Centre of one tree's cell, in pitches. */
export function dotCenter(block: number, row: number, tree: number, orientation: Orientation = 'portrait') {
  const o = blockOrigin(block, orientation);
  return orientation === 'portrait'
    ? { x: o.x + tree - 0.5, y: o.y + row - 0.5 }
    : { x: o.x + row - 0.5, y: o.y + tree - 0.5 };
}

/** Every dot's cell, in pitches: blocks 10 wide × 61 tall, 1.5-pitch gutters, 3 between grid rows. */
export function fieldLayout(orientation: Orientation = 'portrait'): { width: number; height: number; dots: Dot[] } {
  const dots: Dot[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    const o = blockOrigin(block, orientation);
    for (let row = 1; row <= DOWN; row += 1)
      for (let tree = 1; tree <= ACROSS; tree += 1)
        dots.push(
          orientation === 'portrait'
            ? { x: o.x + tree - 1, y: o.y + row - 1, block, row, tree }
            : { x: o.x + row - 1, y: o.y + tree - 1, block, row, tree },
        );
  }
  if (dots.length !== FIELD_TREES) throw new Error('field layout does not add up');
  const [width, height] = orientation === 'portrait' ? [GRID_W, GRID_H] : [GRID_H, GRID_W];
  return { width, height, dots };
}

/**
 * The whole map with room for the 'Block n' labels, in pitches: above each strip in portrait,
 * beside the outer blocks in landscape. Sets the CSS aspect ratio and the SVG fallback's viewBox.
 */
export function frameRect(orientation: Orientation): Rect {
  return orientation === 'portrait'
    ? { x: -0.5, y: -STRIP_GAP, w: GRID_W + 1, h: GRID_H + STRIP_GAP + 0.5 }
    : { x: -7.5, y: -1, w: GRID_H + 15, h: GRID_W + 2 };
}

/** The zoomed close-up's rect: the rows plus a gutter for their numbers (left in portrait, above in landscape). */
export function targetRect(t: ZoomTarget, orientation: Orientation): Rect {
  const o = blockOrigin(t.block, orientation);
  const n = t.to - t.from + 1;
  return orientation === 'portrait'
    ? { x: o.x - 3, y: o.y + t.from - 1 - 0.75, w: ACROSS + 3.75, h: n + 1.5 }
    : { x: o.x + t.from - 1 - 0.75, y: o.y - 2.5, w: n + 1.5, h: ACROSS + 3.25 };
}

// ---------------------------------------------------------------------------
// 2. Tree states from the ledger

export const EMPTY = 0;
export const EARLIER_S = 1;
export const TODAY = 2;
export type TreeState = typeof EMPTY | typeof EARLIER_S | typeof TODAY;

export interface StatusOptions {
  /** Ledger minute. Default MOMENTS.field (2:15 PM). */
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

/** The map as rectangles of same-state trees: consecutive rows with the same pattern merge. */
export function fieldRuns(s: Uint8Array): Run[] {
  const runs: Run[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    let open: Run[] = [];
    let openSig = '';
    for (let row = 1; row <= DOWN; row += 1) {
      const segs: Array<[number, number, TreeState]> = [];
      for (let tree = 1; tree <= ACROSS; tree += 1) {
        const v = statusOf(s, block, row, tree);
        const last = segs[segs.length - 1];
        if (last && last[2] === v) last[1] = tree;
        else segs.push([tree, tree, v]);
      }
      const sig = segs.map((g) => g.join(':')).join('|');
      if (sig === openSig) {
        for (const r of open) r.row1 = row;
      } else {
        open = segs.map(([tree0, tree1, state]) => ({ block, row0: row, row1: row, tree0, tree1, state }));
        runs.push(...open);
        openSig = sig;
      }
    }
  }
  return runs;
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
  const text = parts.join(', ');
  return `Close-up of block ${t.block}, rows ${t.from} to ${t.to}, 10 trees a row: ${text.charAt(0).toUpperCase()}${text.slice(1)}.${flags}`;
}

// ---------------------------------------------------------------------------
// Static SVG (server-rendered first paint, no-JS fallback)

/** The rust flag (the app's flag.fill glyph, 24 × 24). The pole's foot is at (5.6, 21.2). */
export const FLAG_PATH =
  'M5.6 2.8c.5 0 .9.4.9.9v.1h10.9c.7 0 1.1.7.8 1.3l-2.4 3.9 2.4 3.9c.4.6 0 1.3-.8 1.3H6.5v7c0 .5-.4.9-.9.9s-.9-.4-.9-.9V3.7c0-.5.4-.9.9-.9Z';
const FLAG_FOOT = { x: 5.6, y: 21.2 };

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
  /** Draw the close-up of these rows (with row numbers) instead of the whole field. */
  zoom?: ZoomTarget;
  notes?: readonly TreeNote[];
  /** Unique per page: pattern ids must not collide between instances. */
  id?: string;
  theme?: Theme;
  class?: string;
}

/**
 * The map as an inline SVG string: one patterned rect per run, so the whole field is a few KB.
 * Rendered by FieldMap.astro under the canvas for first paint and for visitors without JS.
 */
export function fieldSVG(o: SvgOptions): string {
  const t = o.theme ?? STAGE_THEME;
  const id = o.id ?? 'fm';
  const at = o.at ?? MOMENTS.field;
  const s = treeStatus({ at, who: o.who });
  const notes = o.notes ?? notesAt(at);
  const vb = o.zoom ? targetRect(o.zoom, o.orientation) : frameRect(o.orientation);
  const fills = [`url(#${id}-r)`, `url(#${id}-e)`, `url(#${id}-t)`];
  const out: string[] = [];
  out.push(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${n2(vb.x)} ${n2(vb.y)} ${n2(vb.w)} ${n2(vb.h)}" preserveAspectRatio="xMidYMid meet" aria-hidden="true" focusable="false"${o.class ? ` class="${o.class}"` : ''}>`,
    '<defs>',
    `<pattern id="${id}-r" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r="${n2(DOT_R - 0.07)}" fill="none" stroke="${t.ring}" stroke-width=".14"/></pattern>`,
    `<pattern id="${id}-e" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r="${DOT_R}" fill="${t.earlier}"/></pattern>`,
    `<pattern id="${id}-t" width="1" height="1" patternUnits="userSpaceOnUse"><circle cx=".5" cy=".5" r="${n2(DOT_R * TODAY_SCALE)}" fill="${t.today}"/></pattern>`,
    '</defs>',
  );
  const z = o.zoom;
  const runs = z
    ? fieldRuns(s)
        .filter((r) => r.block === z.block && r.row1 >= z.from && r.row0 <= z.to)
        .map((r) => ({ ...r, row0: Math.max(r.row0, z.from), row1: Math.min(r.row1, z.to) }))
    : fieldRuns(s);
  let block = 0;
  for (const r of runs) {
    if (r.block !== block) {
      if (block) out.push('</g>');
      block = r.block;
      const og = blockOrigin(block, o.orientation);
      out.push(`<g transform="translate(${n2(og.x)} ${n2(og.y)})">`);
    }
    const [x, y, w, h] =
      o.orientation === 'portrait'
        ? [r.tree0 - 1, r.row0 - 1, r.tree1 - r.tree0 + 1, r.row1 - r.row0 + 1]
        : [r.row0 - 1, r.tree0 - 1, r.row1 - r.row0 + 1, r.tree1 - r.tree0 + 1];
    out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fills[r.state]}"/>`);
  }
  if (block) out.push('</g>');

  // Block labels.
  const fs = o.orientation === 'portrait' ? 1.7 : 1.35;
  out.push(`<g fill="${t.label}" font-size="${fs}" class="fm-svg-label">`);
  for (let b = 1; b <= FIELD.blocks && !o.zoom; b += 1) {
    const r = blockRect(b, o.orientation);
    if (o.orientation === 'portrait') out.push(`<text x="${n2(r.x)}" y="${n2(r.y - 0.8)}">Block ${b}</text>`);
    else if (b <= PER_STRIP) out.push(`<text x="${n2(r.x - 0.9)}" y="${n2(r.y + r.h / 2 + fs * 0.35)}" text-anchor="end">Block ${b}</text>`);
    else out.push(`<text x="${n2(r.x + r.w + 0.9)}" y="${n2(r.y + r.h / 2 + fs * 0.35)}">Block ${b}</text>`);
  }
  out.push('</g>');

  // Row numbers in the close-up.
  if (o.zoom) {
    const og = blockOrigin(o.zoom.block, o.orientation);
    out.push(`<g fill="${t.label}" font-size=".62" class="fm-svg-label">`);
    for (let row = o.zoom.from; row <= o.zoom.to; row += 1) {
      if (o.orientation === 'portrait') out.push(`<text x="${n2(og.x - 0.7)}" y="${n2(og.y + row - 0.5 + 0.22)}" text-anchor="end">${row}</text>`);
      else out.push(`<text x="${n2(og.x + row - 0.5)}" y="${n2(og.y - 0.55)}" text-anchor="middle">${row}</text>`);
    }
    out.push('</g>');
  }

  // Note flags: the pole's foot on the tree, the flag up and to the right.
  const fsz = o.zoom ? 0.9 : 1.7;
  for (const n of notes) {
    const c = dotCenter(n.block, n.row, n.tree, o.orientation);
    const k = fsz / 24;
    out.push(
      `<path data-note="${n.block}-${n.row}-${n.tree}" d="${FLAG_PATH}" transform="translate(${n2(c.x - FLAG_FOOT.x * k)} ${n2(c.y - FLAG_FOOT.y * k)}) scale(${n2(k)})" fill="${t.note}" stroke="${t.noteEdge}" stroke-width="1.6" stroke-linejoin="round" paint-order="stroke"/>`,
    );
  }
  out.push('</svg>');
  return out.join('');
}

// ---------------------------------------------------------------------------
// 3. The field scene's choreography (brief: sections.field.animation)

/** Progress windows of the field section's scrubbed timeline. */
export const BEATS = {
  /** Block 2 rows 14→36 flip ring → gold, one row per 1/23 of the window, each with a pop. */
  reveal: [0.3, 0.52],
  /** The camera zooms to block 2 rows 28–40. */
  zoomIn: [0.52, 0.58],
  labelsIn: [0.55, 0.59],
  /** Row 37's number pulses with a touch ring. */
  touch: [0.59, 0.625],
  /** Row 37 fills gold… */
  demoIn: [0.61, 0.64],
  /** …the Undo chip pulses (a DOM overlay the scene owns)… */
  undo: [0.64, 0.67],
  /** …and row 37 goes back to rings: the ledger still has it to do at 2:15. */
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

const clamp01 = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
const ramp = (p: number, w: readonly [number, number]) => clamp01((p - w[0]) / (w[1] - w[0]));
const easeInOut = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
/** Lingers on a value until `w2` starts, then returns: in over w1, out over w2. */
const inOut = (p: number, w1: readonly [number, number], w2: readonly [number, number], ease = (t: number) => t) =>
  p < w2[0] ? ease(ramp(p, w1)) : 1 - ease(ramp(p, w2));

let revealRows: number | null = null;
/** How many gold rows the reveal walks through at 2:15 PM (23). */
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
// Camera

/** Content point at the canvas centre and the scale (CSS px per pitch). */
export interface View {
  cx: number;
  cy: number;
  s: number;
}

/** Fits `r` into W × H minus padding (px), centred in the padded box. */
export function fitView(r: Rect, W: number, H: number, pad: { l?: number; r?: number; t?: number; b?: number } = {}): View {
  const l = pad.l ?? 0;
  const rr = pad.r ?? 0;
  const tp = pad.t ?? 0;
  const b = pad.b ?? 0;
  const s = Math.max(0.0001, Math.min((W - l - rr) / r.w, (H - tp - b) / r.h));
  return { cx: r.x + r.w / 2 - (l - rr) / 2 / s, cy: r.y + r.h / 2 - (tp - b) / 2 / s, s };
}

/** Zoom between two views: scale geometrically, about the one point that stays put on screen. */
export function lerpView(a: View, b: View, t: number): View {
  if (t <= 0) return { ...a };
  if (t >= 1) return { ...b };
  const s = Math.pow(a.s, 1 - t) * Math.pow(b.s, t);
  const k = a.s === b.s ? t : (1 / a.s - 1 / s) / (1 / a.s - 1 / b.s);
  return { cx: a.cx + (b.cx - a.cx) * k, cy: a.cy + (b.cy - a.cy) * k, s };
}

/** Labels need this much room in CSS px around the dot grid. */
const LABEL_PX = { side: 64, top: 16, edge: 4 };
/** The close-up never gets bigger than this pitch (≈ 7 px dots, brief: zoomed view). */
export const MAX_ZOOM_PITCH = 24;

/** The overview's view: the whole field, labels included. */
export function overviewView(orientation: Orientation, W: number, H: number): View {
  const grid: Rect = orientation === 'portrait' ? { x: -0.5, y: -0.5, w: GRID_W + 1, h: GRID_H + 1 } : { x: -0.5, y: -0.5, w: GRID_H + 1, h: GRID_W + 1 };
  return orientation === 'portrait'
    ? fitView(grid, W, H, { l: LABEL_PX.edge, r: LABEL_PX.edge, t: LABEL_PX.top, b: LABEL_PX.edge })
    : fitView(grid, W, H, { l: LABEL_PX.side, r: LABEL_PX.side, t: LABEL_PX.edge, b: LABEL_PX.edge });
}

/** The close-up's view: the target rows centred, at most MAX_ZOOM_PITCH. */
export function zoomView(target: ZoomTarget, orientation: Orientation, W: number, H: number): View {
  const v = fitView(targetRect(target, orientation), W, H);
  return { ...v, s: Math.min(v.s, MAX_ZOOM_PITCH) };
}

/** The camera at zoom progress t (0 overview → 1 close-up). */
export function cameraAt(t: number, orientation: Orientation, W: number, H: number, target: ZoomTarget = ZOOM_TARGET): View {
  return lerpView(overviewView(orientation, W, H), zoomView(target, orientation, W, H), t);
}

export interface CellRange {
  block: number;
  row0: number;
  row1: number;
  tree0: number;
  tree1: number;
}

/** The trees inside the viewport, per block (culling for the zoomed views). */
export function visibleCells(v: View, orientation: Orientation, W: number, H: number, margin = 1): CellRange[] {
  const x0 = v.cx - W / 2 / v.s - margin;
  const x1 = v.cx + W / 2 / v.s + margin;
  const y0 = v.cy - H / 2 / v.s - margin;
  const y1 = v.cy + H / 2 / v.s + margin;
  const out: CellRange[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    const r = blockRect(block, orientation);
    const ix0 = Math.max(0, Math.floor(x0 - r.x));
    const ix1 = Math.min(r.w - 1, Math.ceil(x1 - r.x) - 1);
    const iy0 = Math.max(0, Math.floor(y0 - r.y));
    const iy1 = Math.min(r.h - 1, Math.ceil(y1 - r.y) - 1);
    if (ix0 > ix1 || iy0 > iy1) continue;
    out.push(
      orientation === 'portrait'
        ? { block, tree0: ix0 + 1, tree1: ix1 + 1, row0: iy0 + 1, row1: iy1 + 1 }
        : { block, row0: ix0 + 1, row1: ix1 + 1, tree0: iy0 + 1, tree1: iy1 + 1 },
    );
  }
  return out;
}

const cellCount = (cells: CellRange[]) => cells.reduce((n, c) => n + (c.row1 - c.row0 + 1) * (c.tree1 - c.tree0 + 1), 0);

// ---------------------------------------------------------------------------
// 4. The Canvas 2D renderer

export interface FieldMapOptions {
  view?: 'overview' | 'zoom';
  /** The close-up's rows. Default block 2 rows 28–40. */
  zoom?: ZoomTarget;
  /** Ledger minute. Default MOMENTS.field. */
  at?: Minute;
  who?: Person;
  /** 'auto' (default): landscape when the box is wider than tall. The close-up defaults to portrait. */
  orientation?: Orientation | 'auto';
  notes?: readonly TreeNote[];
  theme?: Partial<Theme>;
  /** Initial state (default: the static final state). */
  state?: Partial<MapState>;
  /** Called after each frame is drawn. */
  onDraw?: () => void;
}

export interface FieldMapHandle {
  /** Draw the field scene's choreography at progress p (no-op when p has not changed). */
  setProgress(p: number): void;
  /** Merge a state and redraw on the next frame (no-op when nothing changed). */
  draw(state: Partial<MapState>): void;
  /** Draw now (tests, labs). */
  render(): void;
  /** Re-measure the box (also automatic through a ResizeObserver). */
  resize(): void;
  readonly state: Readonly<MapState>;
  readonly orientation: Orientation;
  destroy(): void;
}

/** Popping lasts this many reveal rows: gold grows in to 1.3×, then settles to 1. */
const POP = 1.5;
/** Above this many visible dots a moving camera blits the cached overview instead. */
const BLIT_LIMIT = 2600;

interface Sprites {
  key: number;
  r: number;
  size: number;
  ring: HTMLCanvasElement;
  earlier: HTMLCanvasElement;
  today: HTMLCanvasElement;
}

function makeCanvas(w: number, h: number): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.ceil(w));
  c.height = Math.max(1, Math.ceil(h));
  return c;
}

export function createFieldMap(canvas: HTMLCanvasElement, opts: FieldMapOptions = {}): FieldMapHandle {
  const ctx = canvas.getContext('2d');
  const box = canvas.parentElement ?? canvas;
  const theme: Theme = { ...STAGE_THEME, ...opts.theme };
  const view = opts.view ?? 'overview';
  const target = opts.zoom ?? ZOOM_TARGET;
  const at = opts.at ?? MOMENTS.field;
  const status = treeStatus({ at, who: opts.who });
  const gold = goldRows(status);
  const goldIndex = new Map(gold.map((g, k) => [`${g.block}-${g.row}`, k] as const));
  const notes = opts.notes ?? notesAt(at);
  const flag = typeof Path2D === 'function' ? new Path2D(FLAG_PATH) : null;

  let state: MapState = { ...finalState(view, at), ...opts.state };
  let lastProgress = NaN;
  let W = 0;
  let H = 0;
  let dpr = 1;
  let orientation: Orientation = 'landscape';
  let v0: View = { cx: 0, cy: 0, s: 1 };
  let v1: View = { cx: 0, cy: 0, s: 1 };
  let font = "'IBM Plex Mono', ui-monospace, monospace";
  let raf = 0;
  let settle = 0;
  let destroyed = false;
  let sprites: Sprites | null = null;
  // The cached overview (CSS px drawn at dpr) and which gold rows it shows settled.
  let base: HTMLCanvasElement | null = null;
  let baseOk = false;
  const baseRows = new Int8Array(gold.length).fill(-1);

  /** Where gold row k starts flipping, in reveal units (row 0 at 0, the last ends at the total). */
  const startOf = (k: number) => (gold.length > 1 ? (k * (gold.length - POP)) / (gold.length - 1) : 0);
  /** -1 not yet (ring), 0–1 popping, 2 settled gold. */
  const phaseOf = (k: number) => {
    if (state.reveal === null) return 2;
    const x = state.reveal - startOf(k);
    return x <= 0 ? -1 : x >= POP ? 2 : x / POP;
  };

  const spritesFor = (r: number): Sprites => {
    const key = Math.round(r * dpr * 8);
    if (sprites && sprites.key === key) return sprites;
    const rt = r * TODAY_SCALE;
    const size = Math.ceil((rt * 1.35 * 2 + 4) * dpr);
    const mk = (draw: (c: CanvasRenderingContext2D) => void) => {
      const c = makeCanvas(size, size);
      const g = c.getContext('2d');
      if (g) {
        g.setTransform(dpr, 0, 0, dpr, size / 2, size / 2);
        draw(g);
      }
      return c;
    };
    const lw = Math.min(1.5, Math.max(0.75, r * 0.5));
    // The pop scales the gold sprite up to 1.3×, so draw it at that size and scale down.
    sprites = {
      key,
      r,
      size,
      ring: mk((g) => {
        g.beginPath();
        g.arc(0, 0, Math.max(0.3, r - lw / 2), 0, Math.PI * 2);
        g.lineWidth = lw;
        g.strokeStyle = theme.ring;
        g.stroke();
      }),
      earlier: mk((g) => {
        g.beginPath();
        g.arc(0, 0, r, 0, Math.PI * 2);
        g.fillStyle = theme.earlier;
        g.fill();
      }),
      today: mk((g) => {
        g.beginPath();
        g.arc(0, 0, rt * 1.3, 0, Math.PI * 2);
        g.fillStyle = theme.today;
        g.fill();
      }),
    };
    return sprites;
  };

  const toScreen = (v: View, x: number, y: number) => ({ x: (x - v.cx) * v.s + W / 2, y: (y - v.cy) * v.s + H / 2 });

  function stamp(c: CanvasRenderingContext2D, sp: HTMLCanvasElement, x: number, y: number, scale = 1) {
    const d = (sp.width / dpr) * scale;
    c.drawImage(sp, x - d / 2, y - d / 2, d, d);
  }
  /** The gold sprite is drawn at 1.3×; `scale` 1 means the settled size. */
  const stampToday = (c: CanvasRenderingContext2D, sp: Sprites, x: number, y: number, scale = 1) => stamp(c, sp.today, x, y, scale / 1.3);

  /** The state a dot is drawn in (a gold row not yet revealed is still a ring). */
  function drawnState(block: number, row: number, tree: number): TreeState {
    const v = statusOf(status, block, row, tree);
    if (v !== TODAY || state.reveal === null) return v;
    const k = goldIndex.get(`${block}-${row}`);
    return k === undefined || phaseOf(k) === 2 ? TODAY : EMPTY;
  }

  function drawDots(c: CanvasRenderingContext2D, v: View, cells: CellRange[], season: number) {
    const sp = spritesFor(v.s * DOT_R);
    for (const cr of cells)
      for (let row = cr.row0; row <= cr.row1; row += 1)
        for (let tree = cr.tree0; tree <= cr.tree1; tree += 1) {
          const st = drawnState(cr.block, row, tree);
          const p = dotCenter(cr.block, row, tree, orientation);
          const x = (p.x - v.cx) * v.s + W / 2;
          const y = (p.y - v.cy) * v.s + H / 2;
          if (st === EMPTY) {
            stamp(c, sp.ring, x, y);
            continue;
          }
          if (season > 0) {
            c.globalAlpha = season;
            stamp(c, sp.ring, x, y);
            c.globalAlpha = 1 - season;
          }
          if (season < 1) {
            if (st === TODAY) stampToday(c, sp, x, y);
            else stamp(c, sp.earlier, x, y);
          }
          c.globalAlpha = 1;
        }
  }

  function rowBand(block: number, row: number, v: View): [number, number, number, number] {
    const p = dotCenter(block, row, 1, orientation);
    const q = dotCenter(block, row, ACROSS, orientation);
    const a = toScreen(v, p.x, p.y);
    const b = toScreen(v, q.x, q.y);
    const h = v.s * 0.5;
    return [Math.min(a.x, b.x) - h, Math.min(a.y, b.y) - h, Math.abs(b.x - a.x) + 2 * h, Math.abs(b.y - a.y) + 2 * h];
  }

  function ensureBase() {
    if (!base || base.width !== Math.round(W * dpr) || base.height !== Math.round(H * dpr)) {
      base = makeCanvas(W * dpr, H * dpr);
      baseOk = false;
    }
    const b = base.getContext('2d');
    if (!b) return;
    b.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (!baseOk) {
      b.clearRect(0, 0, W, H);
      drawDots(b, v0, visibleCells(v0, orientation, W, H), 0);
      gold.forEach((_, k) => (baseRows[k] = phaseOf(k) === 2 ? 1 : 0));
      baseOk = true;
      return;
    }
    gold.forEach((g, k) => {
      const want = phaseOf(k) === 2 ? 1 : 0;
      if (baseRows[k] === want) return;
      baseRows[k] = want;
      b.clearRect(...rowBand(g.block, g.row, v0));
      drawDots(b, v0, [{ block: g.block, row0: g.row, row1: g.row, tree0: 1, tree1: ACROSS }], 0);
    });
  }

  function drawOverlays(c: CanvasRenderingContext2D, v: View) {
    const sp = spritesFor(v.s * DOT_R);
    // Rows popping in (gold grows to 1.3× over its ring, then settles).
    if (state.season < 1)
      gold.forEach((g, k) => {
        const ph = phaseOf(k);
        if (ph < 0 || ph >= 2) return;
        const scale = ph < 0.25 ? 0.6 + (0.7 * ph) / 0.25 : 1.3 - 0.3 * (1 - Math.pow(1 - (ph - 0.25) / 0.75, 2));
        c.globalAlpha = Math.min(1, ph / 0.12) * (1 - state.season);
        for (let tree = 1; tree <= ACROSS; tree += 1) {
          if (statusOf(status, g.block, g.row, tree) !== TODAY) continue;
          const p = dotCenter(g.block, g.row, tree, orientation);
          const s = toScreen(v, p.x, p.y);
          stampToday(c, sp, s.x, s.y, scale);
        }
        c.globalAlpha = 1;
      });
    // The demo row (row 37 tapped, then undone).
    if (state.demo > 0) {
      c.globalAlpha = clamp01(state.demo);
      for (let tree = 1; tree <= ACROSS; tree += 1) {
        const p = dotCenter(DEMO_ROW.block, DEMO_ROW.row, tree, orientation);
        const s = toScreen(v, p.x, p.y);
        stampToday(c, sp, s.x, s.y, 1 + 0.15 * Math.sin(Math.PI * clamp01(state.demo)));
      }
      c.globalAlpha = 1;
    }
    // Block labels ('Block 7'; just '7' where a portrait block is narrower than its name).
    c.font = `500 11px ${font}`;
    c.fillStyle = theme.label;
    c.textBaseline = 'alphabetic';
    const short = orientation === 'portrait' && c.measureText('Block 14').width > ACROSS * v.s - 4;
    for (let b = 1; b <= FIELD.blocks && view !== 'zoom'; b += 1) {
      const r = blockRect(b, orientation);
      if (orientation === 'portrait') {
        const p = toScreen(v, r.x, r.y);
        c.textAlign = 'left';
        c.fillText(short ? String(b) : `Block ${b}`, p.x, p.y - Math.max(4, v.s * 0.8));
      } else {
        const left = b <= PER_STRIP;
        const p = toScreen(v, left ? r.x : r.x + r.w, r.y + r.h / 2);
        c.textAlign = left ? 'right' : 'left';
        c.textBaseline = 'middle';
        c.fillText(`Block ${b}`, p.x + (left ? -1 : 1) * Math.max(8, v.s * 0.9), p.y);
        c.textBaseline = 'alphabetic';
      }
    }
    // Row numbers of the close-up, and the touch ring on the demo row's number.
    // Numbers shrink with the zoom so they never crowd (13px at full zoom, hidden below 7px).
    const numPx = Math.min(13, v.s * 0.62);
    if (state.labels > 0 && numPx >= 7) {
      c.font = `500 ${numPx.toFixed(1)}px ${font}`;
      c.textBaseline = 'middle';
      const og = blockOrigin(target.block, orientation);
      for (let row = target.from; row <= target.to; row += 1) {
        const p =
          orientation === 'portrait'
            ? toScreen(v, og.x - 0.7, og.y + row - 0.5)
            : toScreen(v, og.x + row - 0.5, og.y - 0.75);
        c.textAlign = orientation === 'portrait' ? 'right' : 'center';
        const hot = target.block === DEMO_ROW.block && row === DEMO_ROW.row && (state.touch > 0 && state.touch < 1 ? true : state.demo > 0);
        c.globalAlpha = clamp01(state.labels);
        c.fillStyle = hot ? theme.labelHot : theme.label;
        c.fillText(String(row), p.x, p.y);
        if (hot && state.touch > 0 && state.touch < 1) {
          const u = state.touch;
          const cx = orientation === 'portrait' ? p.x - numPx * 0.6 : p.x;
          c.globalAlpha = 0.35 * (1 - u);
          c.fillStyle = '#FFFFFF';
          c.beginPath();
          c.arc(cx, p.y, Math.min(22, v.s * 0.92) * (0.6 + 0.8 * u), 0, Math.PI * 2);
          c.fill();
        }
      }
      c.globalAlpha = 1;
      c.textBaseline = 'alphabetic';
    }
    // Note flags (they survive the season reset) and their pulse.
    if (flag)
      for (const n of notes) {
        const p = dotCenter(n.block, n.row, n.tree, orientation);
        const s = toScreen(v, p.x, p.y);
        const size = Math.max(13, v.s * 0.95);
        const k = size / 24;
        if (state.pulse > 0 && state.pulse < 1) {
          const u = state.pulse;
          c.globalAlpha = 0.9 * (1 - u);
          c.strokeStyle = theme.pulse;
          c.lineWidth = 1.5;
          c.beginPath();
          c.arc(s.x, s.y, size * (0.5 + 1.6 * u), 0, Math.PI * 2);
          c.stroke();
          c.globalAlpha = 1;
        }
        c.save();
        c.translate(s.x - FLAG_FOOT.x * k, s.y - FLAG_FOOT.y * k);
        c.scale(k, k);
        c.lineJoin = 'round';
        c.lineWidth = 2.2 / k;
        c.strokeStyle = theme.noteEdge;
        c.stroke(flag);
        c.fillStyle = theme.note;
        c.fill(flag);
        c.restore();
      }
  }

  function render(crisp = false) {
    raf = 0;
    if (destroyed || !ctx || W === 0 || H === 0) return;
    const v = view === 'zoom' ? v1 : lerpView(v0, v1, state.camera);
    // The close-up shows only its own rows: no neighbouring blocks or rows at the edges.
    const cells =
      view === 'zoom'
        ? [{ block: target.block, row0: target.from, row1: target.to, tree0: 1, tree1: ACROSS }]
        : visibleCells(v, orientation, W, H);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const still = state.season === 0;
    if (view === 'overview' && still && state.camera === 0) {
      ensureBase();
      if (base) ctx.drawImage(base, 0, 0, W, H);
    } else if (view === 'overview' && still && !crisp && cellCount(cells) > BLIT_LIMIT) {
      // A moving camera over most of the field: scale the cached overview, then sharpen when it stops.
      ensureBase();
      const k = v.s / v0.s;
      ctx.save();
      ctx.translate(W / 2 + (v0.cx - v.cx) * v.s, H / 2 + (v0.cy - v.cy) * v.s);
      ctx.scale(k, k);
      ctx.translate(-W / 2, -H / 2);
      if (base) ctx.drawImage(base, 0, 0, W, H);
      ctx.restore();
      clearTimeout(settle);
      settle = window.setTimeout(() => render(true), 140);
    } else {
      drawDots(ctx, v, cells, clamp01(state.season));
    }
    drawOverlays(ctx, v);
    opts.onDraw?.();
  }

  const schedule = () => {
    if (!raf && !destroyed) raf = requestAnimationFrame(() => render());
  };

  function measure() {
    const w = box.clientWidth;
    const h = box.clientHeight;
    const d = Math.min(2, window.devicePixelRatio || 1);
    if (w === W && h === H && d === dpr) return false;
    W = w;
    H = h;
    dpr = d;
    canvas.width = Math.max(1, Math.round(W * dpr));
    canvas.height = Math.max(1, Math.round(H * dpr));
    const o = opts.orientation ?? 'auto';
    orientation = o !== 'auto' ? o : view === 'zoom' ? 'portrait' : W >= H ? 'landscape' : 'portrait';
    v0 = view === 'zoom' ? fitView(targetRect(target, orientation), W, H) : overviewView(orientation, W, H);
    v1 = view === 'zoom' ? v0 : zoomView(target, orientation, W, H);
    sprites = null;
    baseOk = false;
    return true;
  }

  const fam = getComputedStyle(canvas).getPropertyValue('--font-mono').trim();
  if (fam) font = fam;
  measure();
  render();
  document.fonts?.load(`500 13px ${font}`).then(() => schedule(), () => {});

  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(() => measure() && schedule()) : null;
  ro?.observe(box);

  const same = (a: MapState, b: Partial<MapState>) => (Object.keys(b) as Array<keyof MapState>).every((k) => a[k] === b[k]);
  const draw = (next: Partial<MapState>) => {
    if (same(state, next)) return;
    state = { ...state, ...next };
    schedule();
  };

  return {
    setProgress(p) {
      if (p === lastProgress) return;
      lastProgress = p;
      draw(sceneState(p));
    },
    draw,
    render: () => render(true),
    resize: () => {
      if (measure()) render(true);
    },
    get state() {
      return state;
    },
    get orientation() {
      return orientation;
    },
    destroy() {
      destroyed = true;
      cancelAnimationFrame(raf);
      clearTimeout(settle);
      ro?.disconnect();
    },
  };
}

// ---------------------------------------------------------------------------
// Instances for FieldMap.astro and the scenes

const instances = new WeakMap<HTMLCanvasElement, FieldMapHandle>();

/** Options from a FieldMap canvas's data attributes. */
function optionsFrom(canvas: HTMLCanvasElement): FieldMapOptions {
  const d = canvas.dataset;
  const zoom = d.zoom?.split(':').map(Number);
  const o: FieldMapOptions = {
    view: d.view === 'zoom' ? 'zoom' : 'overview',
    at: d.at ? Number(d.at) : undefined,
    zoom: zoom && zoom.length === 3 ? { block: zoom[0]!, from: zoom[1]!, to: zoom[2]! } : undefined,
    orientation: d.orientation === 'portrait' || d.orientation === 'landscape' ? d.orientation : 'auto',
  };
  if (d.progress) o.state = sceneState(Number(d.progress));
  return o;
}

/**
 * The one renderer for a FieldMap canvas, created on first call (FieldMap.astro calls this
 * when the canvas comes within a viewport; a scene may call it earlier). Marks the box
 * `data-ready` after the first frame, which hides the SVG fallback.
 */
export function ensureFieldMap(canvas: HTMLCanvasElement, opts?: FieldMapOptions): FieldMapHandle {
  let h = instances.get(canvas);
  if (h) return h;
  const box = canvas.parentElement;
  let first = true;
  h = createFieldMap(canvas, {
    ...optionsFrom(canvas),
    ...opts,
    onDraw: () => {
      if (!first) return;
      first = false;
      box?.setAttribute('data-ready', '');
      canvas.dispatchEvent(new CustomEvent('fieldmap:ready', { bubbles: true }));
    },
  });
  instances.set(canvas, h);
  (canvas as HTMLCanvasElement & { fieldMap?: FieldMapHandle }).fieldMap = h;
  return h;
}
