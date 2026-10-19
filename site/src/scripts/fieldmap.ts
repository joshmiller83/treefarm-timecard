/**
 * THE FIELD MAP: 8,540 trees as dots on Canvas 2D (the lazy half; the pure half is fieldstate.ts).
 *
 *   1. Camera (pure). A View is the world point at the canvas centre, a scale (CSS px per pitch)
 *      and a turn. The landscape overview is the field turned a quarter turn anticlockwise; the
 *      close-up is always upright (row numbers on the left, like the app). lerpView moves between
 *      two views as one spiral similarity: scale and turn together about the one point that stays
 *      put, so the zoom swings the field upright onto block 2 rows 28–40.
 *   2. The renderer (DOM). Trees are drawn as runs (rectangles of same-state trees, about 40 for
 *      the whole field) filled with one-cell pattern tiles, so a frame costs a few dozen fills
 *      whatever the zoom: no per-dot loops, no cached bitmaps to rebuild, no sharpen pass. At rest
 *      the pitch is a whole number of device pixels and every block lands on the pixel grid, so
 *      the dots are as crisp as 1:1 sprites. Only overlays (popping rows, the demo row, labels,
 *      row numbers, flags, rings) are drawn one by one. Nothing redraws unless the state changes.
 *
 * FieldMap.astro loads this module lazily (IntersectionObserver, rootMargin 100%) and calls
 * ensureFieldMap(canvas). A scene drives the same instance:
 *
 *   import { ensureFieldMap } from '../fieldmap.ts';
 *   const map = ensureFieldMap(q1<HTMLCanvasElement>('canvas[data-fieldmap]')!);
 *   tl.eventCallback('onUpdate', () => map.setProgress(tl.progress()));   // or draw({...})
 *   map.pointAt(2, 37, 1);   // where row 37's first tree is now (CSS px in the canvas), for DOM overlays
 *
 * Pure parts are unit-tested in src/scripts/fieldmap.test.ts; nothing touches the DOM at import.
 */
import { FIELD, MOMENTS, type Minute, type Person, type TreeNote } from '../data/ledger.ts';
import {
  DEMO_ROW,
  DOT_R,
  EMPTY,
  FLAG_FOOT,
  FLAG_PATH,
  GRID_H,
  GRID_W,
  STAGE_THEME,
  TODAY,
  TODAY_SCALE,
  ZOOM_TARGET,
  blockRect,
  blockRuns,
  clamp01,
  dimAt,
  dotCenter,
  finalState,
  fromFrame,
  goldRows,
  notesAt,
  rectToFrame,
  runPieces,
  sceneState,
  statusOf,
  targetRect,
  treeIndex,
  treeStatus,
  type MapState,
  type Orientation,
  type Rect,
  type Run,
  type Theme,
  type ZoomTarget,
} from './fieldstate.ts';

// The pure API, re-exported so existing imports from fieldmap.ts keep working.
export {
  BEATS,
  DEMO_ROW,
  DIM_FLOOR,
  DOT_R,
  EARLIER_S,
  EMPTY,
  FLAG_PATH,
  GRID_H,
  GRID_W,
  GUTTER,
  STAGE_THEME,
  STRIP_GAP,
  TODAY,
  TODAY_SCALE,
  ZOOM_TARGET,
  blockOrigin,
  blockRect,
  blockRuns,
  countStatus,
  createTryIt,
  dimAt,
  dotCenter,
  fieldLayout,
  fieldRuns,
  fieldSummary,
  finalState,
  frameRect,
  fromFrame,
  goldRows,
  notesAt,
  rectToFrame,
  revealCount,
  runPieces,
  sceneState,
  statusOf,
  targetRect,
  toFrame,
  treeIndex,
  treeStatus,
  zoomSummary,
} from './fieldstate.ts';
export type { Dot, MapState, Orientation, Point, Rect, Run, StatusOptions, TapMode, Theme, TreeState, TryIt, ZoomTarget } from './fieldstate.ts';

const ACROSS = FIELD.treesPerRow;
const DOWN = FIELD.rowsPerBlock;
const PER_STRIP = FIELD.blocksPerGridRow;

// ---------------------------------------------------------------------------
// 1. Camera

/** The world (portrait) point at the canvas centre, the scale (CSS px per pitch) and the turn (radians, clockwise). */
export interface View {
  cx: number;
  cy: number;
  s: number;
  /** 0 = upright (portrait world), -π/2 = the landscape overview. */
  r?: number;
}

/** The landscape overview's turn: a quarter turn anticlockwise. */
export const LANDSCAPE_TURN = -Math.PI / 2;
const turnOf = (o: Orientation) => (o === 'landscape' ? LANDSCAPE_TURN : 0);

export interface Pad {
  l?: number;
  r?: number;
  t?: number;
  b?: number;
}

/**
 * Fits `r` (in screen-aligned frame units) into W × H minus padding (px), centred in the padded
 * box. `cap` limits the scale; with `dpr` the scale snaps down to whole device pixels per pitch.
 */
export function fitView(r: Rect, W: number, H: number, pad: Pad = {}, cap = Infinity, dpr = 0): View {
  const l = pad.l ?? 0;
  const rr = pad.r ?? 0;
  const tp = pad.t ?? 0;
  const b = pad.b ?? 0;
  let s = Math.max(0.0001, Math.min(cap, (W - l - rr) / r.w, (H - tp - b) / r.h));
  if (dpr > 0) s = Math.max(1, Math.floor(s * dpr + 1e-6)) / dpr;
  return { cx: r.x + r.w / 2 - (l - rr) / 2 / s, cy: r.y + r.h / 2 - (tp - b) / 2 / s, s, r: 0 };
}

/** Fits a frame rect for an orientation and returns the view in world terms (centre and turn). */
function fitFrame(frame: Rect, o: Orientation, W: number, H: number, pad: Pad = {}, cap = Infinity, dpr = 0): View {
  const f = fitView(frame, W, H, pad, cap, dpr);
  const c = fromFrame({ x: f.cx, y: f.cy }, o);
  return { cx: c.x, cy: c.y, s: f.s, r: turnOf(o) };
}

// Complex numbers for the spiral interpolation: [re, im].
type C = [number, number];
const cmul = (a: C, b: C): C => [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]];
const cdiv = (a: C, b: C): C => {
  const d = b[0] * b[0] + b[1] * b[1];
  return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d];
};
const cpolar = (k: number, phi: number): C => [k * Math.cos(phi), k * Math.sin(phi)];

/**
 * Moves between two views as one spiral similarity: the scale changes geometrically and the turn
 * linearly, about the one screen point that stays put (a plain zoom keeps its anchor still).
 */
export function lerpView(a: View, b: View, t: number): View {
  const ra = a.r ?? 0;
  const rb = b.r ?? 0;
  if (t <= 0) return { ...a, r: ra };
  if (t >= 1) return { ...b, r: rb };
  // Screen positions relative to the canvas centre: z = s·e^{iθ}·(w − c). B∘A⁻¹ is z ↦ m·z + n.
  const k = b.s / a.s;
  const phi = rb - ra;
  const m = cpolar(k, phi);
  const n = cmul(cpolar(b.s, rb), [a.cx - b.cx, a.cy - b.cy]);
  const s = a.s * Math.pow(k, t);
  const r = ra + phi * t;
  const sa = cpolar(a.s, ra);
  if (Math.hypot(m[0] - 1, m[1]) < 1e-9) {
    // A pure pan.
    const d = cdiv([n[0] * t, n[1] * t], sa);
    return { cx: a.cx - d[0], cy: a.cy - d[1], s, r };
  }
  const F = cdiv(n, [1 - m[0], -m[1]]);
  const mt = cpolar(Math.pow(k, t), phi * t);
  const d = cdiv(cmul(F, [1 - mt[0], -mt[1]]), cpolar(s, r));
  return { cx: a.cx - d[0], cy: a.cy - d[1], s, r };
}

/** Labels need this much room in CSS px around the dot grid. */
const LABEL_PX = { side: 64, sideShort: 22, top: 16, edge: 4 };
/** Below this width the landscape overview labels blocks by number only ('7', not 'Block 7'). */
const SHORT_LABELS_BELOW = 640;
/**
 * The block labels' text and size. Landscape: 'Block 7' at 11px beside each band, or '7' on a
 * narrow canvas. Portrait (over each block): 'Block 14' as large as fits its block and gutter with
 * a 5px gap, down to 8px; then 'B14'. Plex Mono's advance is 0.6em.
 */
export function blockLabelPx(orientation: Orientation, W: number, H = Infinity, dpr = 0): { px: number; short: boolean; text: (b: number) => string } {
  if (orientation === 'landscape') {
    const short = W < SHORT_LABELS_BELOW;
    return { px: 11, short, text: (b) => (short ? String(b) : `Block ${b}`) };
  }
  const s = overviewView('portrait', W, H, dpr).s;
  const room = (ACROSS + 1.5) * s - 5;
  const px = Math.min(11, room / (8 * 0.6));
  if (px >= 8) return { px, short: false, text: (b) => `Block ${b}` };
  return { px: Math.max(7, Math.min(11, room / (3 * 0.6))), short: true, text: (b) => `B${b}` };
}
/** Whether the block labels are abbreviated at this size. */
export const shortLabels = (orientation: Orientation, W: number) =>
  orientation === 'landscape' ? W < SHORT_LABELS_BELOW : blockLabelPx(orientation, W).short;
/** The close-up never gets bigger than this pitch (dots of radius ≈ 7px, brief: zoomed view). */
export const MAX_ZOOM_PITCH = 24;

/** The overview's view: the whole field, labels included. */
export function overviewView(orientation: Orientation, W: number, H: number, dpr = 0): View {
  const grid = rectToFrame({ x: -0.5, y: -0.5, w: GRID_W + 1, h: GRID_H + 1 }, orientation);
  if (orientation === 'portrait')
    return fitFrame(grid, orientation, W, H, { l: LABEL_PX.edge, r: LABEL_PX.edge, t: LABEL_PX.top, b: LABEL_PX.edge }, Infinity, dpr);
  const side = W < SHORT_LABELS_BELOW ? LABEL_PX.sideShort : LABEL_PX.side;
  return fitFrame(grid, orientation, W, H, { l: side, r: side, t: LABEL_PX.edge, b: LABEL_PX.edge }, Infinity, dpr);
}

/** The close-up's view: the target rows upright and centred, at most MAX_ZOOM_PITCH. */
export function zoomView(target: ZoomTarget, W: number, H: number, dpr = 0): View {
  return fitFrame(targetRect(target), 'portrait', W, H, {}, MAX_ZOOM_PITCH, dpr);
}

/** The camera at zoom progress t (0 overview → 1 close-up). */
export function cameraAt(t: number, orientation: Orientation, W: number, H: number, target: ZoomTarget = ZOOM_TARGET, dpr = 0): View {
  return lerpView(overviewView(orientation, W, H, dpr), zoomView(target, W, H, dpr), t);
}

/** A world point on screen (CSS px from the canvas's top-left). */
export function toScreen(v: View, W: number, H: number, x: number, y: number): { x: number; y: number } {
  const r = v.r ?? 0;
  const c = Math.cos(r);
  const s = Math.sin(r);
  const dx = (x - v.cx) * v.s;
  const dy = (y - v.cy) * v.s;
  return { x: c * dx - s * dy + W / 2, y: s * dx + c * dy + H / 2 };
}

export interface CellRange {
  block: number;
  row0: number;
  row1: number;
  tree0: number;
  tree1: number;
}

/** The trees inside the viewport, per block (the world box around the turned screen). */
export function visibleCells(v: View, W: number, H: number, margin = 1): CellRange[] {
  const r = v.r ?? 0;
  const c = Math.cos(r);
  const s = Math.sin(r);
  let x0 = Infinity;
  let x1 = -Infinity;
  let y0 = Infinity;
  let y1 = -Infinity;
  for (const [px, py] of [
    [-W / 2, -H / 2],
    [W / 2, -H / 2],
    [-W / 2, H / 2],
    [W / 2, H / 2],
  ] as const) {
    // Inverse turn: world = c + R(−θ)·z / s.
    const wx = v.cx + (c * px + s * py) / v.s;
    const wy = v.cy + (-s * px + c * py) / v.s;
    x0 = Math.min(x0, wx);
    x1 = Math.max(x1, wx);
    y0 = Math.min(y0, wy);
    y1 = Math.max(y1, wy);
  }
  x0 -= margin;
  x1 += margin;
  y0 -= margin;
  y1 += margin;
  const out: CellRange[] = [];
  for (let block = 1; block <= FIELD.blocks; block += 1) {
    const b = blockRect(block);
    const t0 = Math.max(0, Math.floor(x0 - b.x));
    const t1 = Math.min(ACROSS - 1, Math.ceil(x1 - b.x) - 1);
    const r0 = Math.max(0, Math.floor(y0 - b.y));
    const r1 = Math.min(DOWN - 1, Math.ceil(y1 - b.y) - 1);
    if (t0 > t1 || r0 > r1) continue;
    out.push({ block, tree0: t0 + 1, tree1: t1 + 1, row0: r0 + 1, row1: r1 + 1 });
  }
  return out;
}

// ---------------------------------------------------------------------------
// 2. The Canvas 2D renderer

export interface FieldMapOptions {
  view?: 'overview' | 'zoom';
  /** The close-up's rows. Default block 2 rows 28–40. */
  zoom?: ZoomTarget;
  /** Ledger minute. Default MOMENTS.field. */
  at?: Minute;
  who?: Person;
  /** The overview's orientation. 'auto' (default): landscape when the box is wider than tall. The close-up is always upright. */
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
  /** Draw now, synchronously (tests, labs), as a frame would; `sharp` keeps full resolution while the camera moves. */
  render(sharp?: boolean): void;
  /** Re-measure the box (also automatic through a ResizeObserver). */
  resize(): void;
  /** Where a tree's centre is drawn at the current state, in CSS px from the canvas's top-left. */
  pointAt(block: number, row: number, tree: number): { x: number; y: number };
  readonly state: Readonly<MapState>;
  readonly orientation: Orientation;
  /** Frames drawn so far (each state change draws exactly one). */
  readonly frames: number;
  destroy(): void;
}

/** Popping lasts this many reveal rows: gold grows in to 1.3×, then settles to 1. */
const POP = 1.5;
/**
 * While the camera is visibly moving (between these zoom amounts) a large canvas draws at 1×
 * backing resolution: a turned, scaled fill costs per pixel, and on a software rasterizer a 2×
 * desktop canvas would take ~35 ms a frame. Rest frames are always full resolution, and a paused
 * camera is sharpened after SHARPEN_MS.
 */
const LOW_RES_CAMERA: readonly [number, number] = [0.02, 0.98];
const LOW_RES_ABOVE = 1.5e6;
const SHARPEN_MS = 160;

interface Sprites {
  key: number;
  /** Device-pixel size of every sprite (square and even, so a snapped centre lands on whole pixels). */
  size: number;
  /** Gold at 1.3× for the pop; drawn scaled while it settles. */
  pop: HTMLCanvasElement;
}

interface Tiles {
  ring: CanvasPattern;
  earlier: CanvasPattern;
  today: CanvasPattern;
}

function makeCanvas(w: number, h: number): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = Math.max(1, Math.ceil(w));
  c.height = Math.max(1, Math.ceil(h));
  return c;
}

/** The ring's stroke in CSS px for a dot of radius r (CSS px): 1.5px at the close-up, never under .75px. */
const ringWidth = (r: number) => Math.min(1.5, Math.max(0.75, r * 0.5));

export function createFieldMap(canvas: HTMLCanvasElement, opts: FieldMapOptions = {}): FieldMapHandle {
  const ctx = canvas.getContext('2d');
  const box = canvas.parentElement ?? canvas;
  const theme: Theme = { ...STAGE_THEME, ...opts.theme };
  const view = opts.view ?? 'overview';
  const target = opts.zoom ?? ZOOM_TARGET;
  const at = opts.at ?? MOMENTS.field;
  const status = treeStatus({ at, who: opts.who });
  const gold = goldRows(status);
  const notes = opts.notes ?? notesAt(at);
  const flag = typeof Path2D === 'function' ? new Path2D(FLAG_PATH) : null;

  let state: MapState = { ...finalState(view, at), ...opts.state };
  let lastProgress = NaN;
  let W = 0;
  let H = 0;
  /** The device pixel ratio (capped at 2) and the backing store's current one (1 while moving on a big canvas). */
  let full = 1;
  let dpr = 1;
  let settle = 0;
  let orientation: Orientation = 'landscape';
  let v0: View = { cx: 0, cy: 0, s: 1, r: 0 };
  let v1: View = { cx: 0, cy: 0, s: 1, r: 0 };
  let current: View = v0;
  let font = "'IBM Plex Mono', ui-monospace, monospace";
  let raf = 0;
  let frames = 0;
  let destroyed = false;
  let sprites: Sprites | null = null;
  const tiles = new Map<number, Tiles>();

  // What the dots show: the ledger, minus gold rows that have not settled yet (they draw as rings
  // under their popping overlay). Runs are rebuilt per block only when one of its rows changes.
  const shown = status.slice();
  const shownGold = new Uint8Array(gold.length).fill(1);
  const settled = new Uint8Array(gold.length);
  const runs: Array<Run[] | null> = new Array(FIELD.blocks + 1).fill(null);
  const runsOf = (block: number) => (runs[block] ??= blockRuns(shown, block));

  /** Where gold row k starts flipping, in reveal units (row 0 at 0, the last ends at the total). */
  const startOf = (k: number) => (gold.length > 1 ? (k * (gold.length - POP)) / (gold.length - 1) : 0);
  /** -1 not yet (ring), 0–1 popping, 2 settled gold. */
  const phaseOf = (k: number) => {
    if (state.reveal === null) return 2;
    const x = state.reveal - startOf(k);
    return x <= 0 ? -1 : x >= POP ? 2 : x / POP;
  };

  function syncShown() {
    for (let k = 0; k < gold.length; k += 1) {
      settled[k] = phaseOf(k) === 2 ? 1 : 0;
      if (shownGold[k] === settled[k]) continue;
      shownGold[k] = settled[k]!;
      const g = gold[k]!;
      const i = treeIndex(g.block, g.row, 1);
      for (let t = 0; t < ACROSS; t += 1) shown[i + t] = settled[k] || status[i + t] !== TODAY ? status[i + t]! : EMPTY;
      runs[g.block] = null;
    }
  }

  /** One-cell pattern tiles at N device px per pitch (a dot centred in each). */
  function tilesFor(N: number): Tiles | null {
    const hit = tiles.get(N);
    if (hit) return hit;
    if (!ctx) return null;
    const mk = (draw: (g: CanvasRenderingContext2D) => void) => {
      const c = makeCanvas(N, N);
      const g = c.getContext('2d');
      if (g) {
        g.translate(N / 2, N / 2);
        draw(g);
      }
      return ctx.createPattern(c, 'repeat');
    };
    const disc = (radius: number, colour: string) => (g: CanvasRenderingContext2D) => {
      g.beginPath();
      g.arc(0, 0, radius, 0, Math.PI * 2);
      g.fillStyle = colour;
      g.fill();
    };
    const r = DOT_R * N;
    const lw = ringWidth(r / dpr) * dpr;
    const ring = mk((g) => {
      g.beginPath();
      g.arc(0, 0, Math.max(0.3 * dpr, r - lw / 2), 0, Math.PI * 2);
      g.lineWidth = lw;
      g.strokeStyle = theme.ring;
      g.stroke();
    });
    const earlier = mk(disc(r, theme.earlier));
    const today = mk(disc(r * TODAY_SCALE, theme.today));
    if (!ring || !earlier || !today) return null;
    const t = { ring, earlier, today };
    tiles.set(N, t);
    return t;
  }

  /** The gold pop sprite for the reveal and the demo row (1:1 device pixels). */
  const spritesFor = (r: number): Sprites => {
    const key = Math.round(r * dpr * 8);
    if (sprites && sprites.key === key) return sprites;
    let size = Math.ceil((r * TODAY_SCALE * 1.3 * 2 + 3) * dpr);
    size += size % 2;
    const pop = makeCanvas(size, size);
    const g = pop.getContext('2d');
    if (g) {
      g.setTransform(dpr, 0, 0, dpr, size / 2, size / 2);
      g.beginPath();
      g.arc(0, 0, r * TODAY_SCALE * 1.3, 0, Math.PI * 2);
      g.fillStyle = theme.today;
      g.fill();
    }
    sprites = { key, size, pop };
    return sprites;
  };

  const screenOf = (v: View, x: number, y: number) => toScreen(v, W, H, x, y);

  /** Every tree, as runs filled with pattern tiles: rings, fills fading for the season, the outside dimmed. */
  function paintDots(c: CanvasRenderingContext2D, v: View, season: number, dim: number) {
    const N = Math.max(3, Math.round(v.s * dpr));
    const t = tilesFor(N);
    if (!t) return;
    const k = (v.s * dpr) / N;
    const r = v.r ?? 0;
    let cos = Math.cos(r);
    let sin = Math.sin(r);
    // At rest (1:1 and a whole quarter turn) every block lands on whole device pixels and the
    // fills stay translate-only: the rects are turned instead of the pattern (a dot is symmetric),
    // which keeps the rasterizer on its fast, unfiltered path.
    const crisp = Math.abs(k - 1) < 1e-6 && Math.abs(sin * cos) < 1e-9;
    if (crisp) {
      cos = Math.round(cos);
      sin = Math.round(sin);
    }
    const fill = (x: number, y: number, w: number, h: number) => {
      if (!crisp) return c.fillRect(x, y, w, h);
      // (x, y) → (cos·x − sin·y, sin·x + cos·y), exact for a quarter turn.
      const ax = cos * x - sin * y;
      const ay = sin * x + cos * y;
      const bx = cos * (x + w) - sin * (y + h);
      const by = sin * (x + w) + cos * (y + h);
      c.fillRect(Math.min(ax, bx), Math.min(ay, by), Math.abs(bx - ax), Math.abs(by - ay));
    };
    for (let block = 1; block <= FIELD.blocks; block += 1) {
      const b = blockRect(block);
      // Cull blocks wholly off screen.
      let minX = Infinity;
      let maxX = -Infinity;
      let minY = Infinity;
      let maxY = -Infinity;
      for (const [x, y] of [
        [b.x, b.y],
        [b.x + b.w, b.y],
        [b.x, b.y + b.h],
        [b.x + b.w, b.y + b.h],
      ] as const) {
        const p = screenOf(v, x, y);
        minX = Math.min(minX, p.x);
        maxX = Math.max(maxX, p.x);
        minY = Math.min(minY, p.y);
        maxY = Math.max(maxY, p.y);
      }
      if (maxX < 0 || minX > W || maxY < 0 || minY > H) continue;
      const o = screenOf(v, b.x, b.y);
      if (crisp) c.setTransform(1, 0, 0, 1, Math.round(o.x * dpr), Math.round(o.y * dpr));
      else c.setTransform(k * cos, k * sin, -k * sin, k * cos, o.x * dpr, o.y * dpr);
      for (const run of runsOf(block)) {
        const x = (run.tree0 - 1) * N;
        const w = (run.tree1 - run.tree0 + 1) * N;
        for (const p of runPieces(run, target, dim)) {
          const y = (p.row0 - 1) * N;
          const h = (p.row1 - p.row0 + 1) * N;
          if (run.state === EMPTY || season > 0) {
            c.globalAlpha = p.alpha;
            c.fillStyle = t.ring;
            fill(x, y, w, h);
          }
          if (run.state !== EMPTY && season < 1) {
            c.globalAlpha = p.alpha * (1 - season);
            c.fillStyle = run.state === TODAY ? t.today : t.earlier;
            fill(x, y, w, h);
          }
        }
      }
    }
    c.globalAlpha = 1;
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  const inTarget = (block: number, row: number) => block === target.block && row >= target.from && row <= target.to;

  function drawOverlays(c: CanvasRenderingContext2D, v: View, cam: number, dim: number) {
    const sp = spritesFor(v.s * DOT_R);
    const d = sp.size / dpr;
    const snap = (q: number) => Math.round(q * dpr) / dpr;
    // Rows popping in (gold grows to 1.3× over its ring, then settles).
    if (state.season < 1)
      gold.forEach((g, k) => {
        const ph = phaseOf(k);
        if (ph < 0 || ph >= 2) return;
        const scale = ph < 0.25 ? 0.6 + (0.7 * ph) / 0.25 : 1.3 - 0.3 * (1 - Math.pow(1 - (ph - 0.25) / 0.75, 2));
        c.globalAlpha = Math.min(1, ph / 0.12) * (1 - state.season) * (inTarget(g.block, g.row) ? 1 : dim);
        const dd = (d * scale) / 1.3;
        for (let tree = 1; tree <= ACROSS; tree += 1) {
          if (statusOf(status, g.block, g.row, tree) !== TODAY) continue;
          const p = dotCenter(g.block, g.row, tree);
          const q = screenOf(v, p.x, p.y);
          c.drawImage(sp.pop, snap(q.x) - dd / 2, snap(q.y) - dd / 2, dd, dd);
        }
      });
    c.globalAlpha = 1;
    // The demo row (row 37 tapped, then undone).
    if (state.demo > 0) {
      c.globalAlpha = clamp01(state.demo);
      const dd = (d * (1 + 0.15 * Math.sin(Math.PI * clamp01(state.demo)))) / 1.3;
      for (let tree = 1; tree <= ACROSS; tree += 1) {
        const p = dotCenter(DEMO_ROW.block, DEMO_ROW.row, tree);
        const q = screenOf(v, p.x, p.y);
        c.drawImage(sp.pop, snap(q.x) - dd / 2, snap(q.y) - dd / 2, dd, dd);
      }
      c.globalAlpha = 1;
    }
    // Block labels ('Block 7'; just '7' where there is no room), fading as the camera moves in.
    const labelAlpha = view === 'zoom' ? 0 : clamp01(1 - cam * 2.5);
    if (labelAlpha > 0) {
      const lp = blockLabelPx(orientation, W, H, full);
      c.globalAlpha = labelAlpha;
      c.font = `500 ${lp.px.toFixed(1)}px ${font}`;
      c.fillStyle = theme.label;
      for (let b = 1; b <= FIELD.blocks; b += 1) {
        const text = lp.text(b);
        const r = blockRect(b);
        if (orientation === 'portrait') {
          const p = screenOf(v, r.x, r.y);
          c.textAlign = 'left';
          c.textBaseline = 'alphabetic';
          c.fillText(text, p.x, p.y - Math.max(4, v.s * 0.8));
        } else {
          // Landscape: blocks 1–7 labelled on the left of their band, 8–14 on the right.
          const left = b <= PER_STRIP;
          const p = screenOf(v, r.x + r.w / 2, left ? r.y : r.y + r.h);
          c.textAlign = left ? 'right' : 'left';
          c.textBaseline = 'middle';
          c.fillText(text, p.x + (left ? -1 : 1) * Math.max(8, v.s * 0.9), p.y);
        }
      }
      c.globalAlpha = 1;
      c.textBaseline = 'alphabetic';
    }
    // Row numbers of the close-up, on the left, and the touch ring on the demo row's number. They
    // shrink with the zoom so they never crowd (13px at full zoom, hidden below 7px), and on a
    // landscape canvas they wait until the field has nearly turned upright.
    const numPx = Math.min(13, v.s * 0.54);
    const upright = orientation === 'landscape' && view !== 'zoom' ? clamp01((cam - 0.6) / 0.35) : 1;
    const numAlpha = clamp01(state.labels) * upright;
    if (numAlpha > 0 && numPx >= 7) {
      c.font = `500 ${numPx.toFixed(1)}px ${font}`;
      c.textBaseline = 'middle';
      c.textAlign = 'right';
      const og = blockRect(target.block);
      for (let row = target.from; row <= target.to; row += 1) {
        const p = screenOf(v, og.x - 0.7, og.y + row - 0.5);
        const touching = state.touch > 0 && state.touch < 1;
        const hot = target.block === DEMO_ROW.block && row === DEMO_ROW.row && (touching || state.demo > 0);
        c.globalAlpha = numAlpha;
        c.fillStyle = hot ? theme.labelHot : theme.label;
        c.fillText(String(row), p.x, p.y);
        if (hot && touching) {
          const u = state.touch;
          c.globalAlpha = 0.35 * (1 - u) * upright;
          c.fillStyle = '#FFFFFF';
          c.beginPath();
          c.arc(p.x - numPx * 0.6, p.y, Math.min(22, v.s * 0.92) * (0.6 + 0.8 * u), 0, Math.PI * 2);
          c.fill();
        }
      }
      c.globalAlpha = 1;
      c.textBaseline = 'alphabetic';
    }
    // Note flags (they survive the season reset) and their pulse.
    if (flag)
      for (const n of notes) {
        const p = dotCenter(n.block, n.row, n.tree);
        const q = screenOf(v, p.x, p.y);
        if (q.x < -40 || q.x > W + 40 || q.y < -40 || q.y > H + 40) continue;
        const a = inTarget(n.block, n.row) ? 1 : dim;
        const size = Math.max(13, v.s * 0.95);
        const k = size / 24;
        if (state.pulse > 0 && state.pulse < 1) {
          const u = state.pulse;
          c.globalAlpha = 0.9 * (1 - u) * a;
          c.strokeStyle = theme.pulse;
          c.lineWidth = 1.5;
          c.beginPath();
          c.arc(q.x, q.y, size * (0.5 + 1.6 * u), 0, Math.PI * 2);
          c.stroke();
        }
        c.globalAlpha = a;
        c.save();
        c.translate(q.x - FLAG_FOOT.x * k, q.y - FLAG_FOOT.y * k);
        c.scale(k, k);
        c.lineJoin = 'round';
        c.lineWidth = 2.2 / k;
        c.strokeStyle = theme.noteEdge;
        c.stroke(flag);
        c.fillStyle = theme.note;
        c.fill(flag);
        c.restore();
        c.globalAlpha = 1;
      }
  }

  function setBacking(d: number) {
    if (d === dpr && canvas.width === Math.max(1, Math.round(W * d))) return;
    dpr = d;
    canvas.width = Math.max(1, Math.round(W * dpr));
    canvas.height = Math.max(1, Math.round(H * dpr));
    sprites = null;
    tiles.clear();
  }

  /** Draws the current state now. `sharp` keeps full resolution even while the camera moves. */
  function render(sharp = false) {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    clearTimeout(settle);
    if (destroyed || !ctx || W === 0 || H === 0) return;
    syncShown();
    const cam = view === 'zoom' ? 1 : clamp01(state.camera);
    const low = !sharp && full > 1 && cam > LOW_RES_CAMERA[0] && cam < LOW_RES_CAMERA[1] && W * H * full * full > LOW_RES_ABOVE;
    setBacking(low ? 1 : full);
    if (low) settle = window.setTimeout(() => render(true), SHARPEN_MS);
    const v = view === 'zoom' ? v1 : lerpView(v0, v1, cam);
    current = v;
    const dim = dimAt(cam);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    paintDots(ctx, v, clamp01(state.season), dim);
    drawOverlays(ctx, v, cam, dim);
    frames += 1;
    opts.onDraw?.();
  }

  const schedule = () => {
    if (!raf && !destroyed) raf = requestAnimationFrame(() => render());
  };

  function measure() {
    const w = box.clientWidth;
    const h = box.clientHeight;
    const d = Math.min(2, window.devicePixelRatio || 1);
    if (w === W && h === H && d === full) return false;
    W = w;
    H = h;
    full = d;
    setBacking(full);
    const o = opts.orientation ?? 'auto';
    orientation = view === 'zoom' ? 'portrait' : o !== 'auto' ? o : W >= H ? 'landscape' : 'portrait';
    // Rest views snap to whole device pixels per pitch at full resolution.
    v0 = view === 'zoom' ? zoomView(target, W, H, full) : overviewView(orientation, W, H, full);
    v1 = view === 'zoom' ? v0 : zoomView(target, W, H, full);
    current = v0;
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
    render,
    resize: () => {
      if (measure()) render(true);
    },
    pointAt(block, row, tree) {
      const p = dotCenter(block, row, tree);
      return screenOf(current, p.x, p.y);
    },
    get state() {
      return state;
    },
    get orientation() {
      return orientation;
    },
    get frames() {
      return frames;
    },
    destroy() {
      destroyed = true;
      cancelAnimationFrame(raf);
      clearTimeout(settle);
      ro?.disconnect();
      tiles.clear();
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
 * when the canvas comes within a viewport; a scene may call it earlier with its own options,
 * onDraw included). Marks the box `data-ready` after the first frame, which hides the SVG fallback.
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
      opts?.onDraw?.();
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
