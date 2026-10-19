/**
 * LOCK SCREEN · 2:14 PM: the section's story and geometry as pure data.
 *
 * Everything the section shows comes from the ledger through liveActivityAt(); the geometry
 * follows the Live Activity's own (system/lockscreen/activity.ts: 361 pt wide, bottom at
 * y 760 pt in the 393 × 852 pt screen, 159 pt tall) inside the phone's 420 × 879 frame.
 * LockScreen.astro renders from here, the scene animates from here, and Vitest checks it.
 */
import {
  FIELD_TREES,
  fieldShapedAt,
  fmtCount,
  fmtSpokenDuration,
  fmtTime,
  liveActivityAt,
  MOMENTS,
  rowsAt,
  treesAt,
  workedAt,
} from '../../data/ledger.ts';
import { buttonWidth, cardHeight, LA } from '../../components/system/lockscreen/activity.ts';

// ---------------------------------------------------------------------------
// The story

/** 2:01 PM, where the voice chapter left the lock screen. */
export const BEFORE = {
  at: MOMENTS.status,
  rows: rowsAt(MOMENTS.status),
  trees: treesAt(MOMENTS.status),
  fieldPct: fieldShapedAt(MOMENTS.status) / FIELD_TREES,
} as const;

/** 2:14 PM, before the tap. */
export const WORKING = liveActivityAt(MOMENTS.lockScreen);

/** Under a second later: Row 36 tapped on the lock screen. */
export const TAPPED = liveActivityAt(MOMENTS.tapped);

/** The island opens 10 seconds after 2:16 PM (6:29:10). */
export const ISLAND_AT = MOMENTS.island + 10 / 60;

/** The phone's aria-label: the brief's sentence, built from the ledger. */
export function phoneLabel(): string {
  const v = TAPPED;
  return (
    `iPhone lock screen at ${fmtTime(MOMENTS.lockScreen)}. The Time Card Live Activity shows ${v.pill}, ` +
    `${fmtSpokenDuration(workedAt(MOMENTS.tapped))} worked, ${v.field}, ${v.block}, ${fmtCount(v.trees)} trees this shift, ` +
    `Row ${v.undoRow} marked with Undo, and buttons for row ${v.rows.join(', row ')} and Break. There is no clock-out button.`
  );
}

// ---------------------------------------------------------------------------
// Geometry (screen pt unless noted)

/** The phone frame in u (1/420 of its width) and the screen's inset in it. */
export const FRAME = { w: 420, h: 879, inset: 13.5 } as const;

/** The Live Activity card on the 393 × 852 pt screen. */
export const CARD = { x: LA.left, y: LA.bottomY - cardHeight, w: LA.width, h: cardHeight };
export const CARD_CENTER = { x: CARD.x + CARD.w / 2, y: CARD.y + CARD.h / 2 };

/** The zoom's transform-origin: the card's centre as fractions of the phone frame. */
export const ORIGIN = {
  x: (FRAME.inset + CARD_CENTER.x) / FRAME.w,
  y: (FRAME.inset + CARD_CENTER.y) / FRAME.h,
};

/** The centre line of each of the card's four rows. */
export const ROWS = (() => {
  let y = CARD.y + LA.padY;
  const pill = y + LA.rows.pill / 2;
  y += LA.rows.pill + LA.gaps.timer;
  const timer = y + LA.rows.timer / 2;
  y += LA.rows.timer + LA.gaps.trees;
  const trees = y + LA.rows.trees / 2;
  y += LA.rows.trees + LA.gaps.buttons;
  const buttons = y + LA.rows.buttons / 2;
  return { pill, timer, trees, buttons };
})();

export const ZOOM = { desk: 1.7, mob: 1.4, min: 1.2 } as const;
/** Mobile: the card's centre lands this far down the phone (clear of the copy cards). */
export const MOB_TARGET = 0.38;
/** Mobile pins: 22px circles after the zoom, or 33 pt on phones too small for that. */
export const PIN_PX = 22;
export const PIN_PT = 33;

export type Side = 'left' | 'right';

export interface Callout {
  n: 1 | 2 | 3 | 4 | 5 | 6;
  side: Side;
  /** The bold words. */
  label: string;
  /** Extra words in a lighter weight (callout 6). */
  sub?: string;
  /** Where the leader line's dot sits, in the card's side padding beside the feature. */
  target: { x: number; y: number };
  /** Desktop: the label level with its dot ('row'), lifted above it, or dropped below it. */
  place: 'row' | 'above' | 'below' | 'ghost';
  /** Mobile and static: the numbered pin beside the feature (screen pt). */
  pin: { x: number; y: number };
}

const LEFT = CARD.x + 8; // in the card's 14 pt left padding
const RIGHT = CARD.x + CARD.w - 8;
/** Mobile pins sit beside their feature, clear of its text (see the unit test). */
const BTN0 = CARD.x + LA.padX + buttonWidth / 2; // the first row button's centre
const BREAK_R = CARD.x + CARD.w - LA.padX; // Break's right edge
const BTN_BOTTOM = ROWS.buttons + LA.btnH / 2;

export const CALLOUTS: readonly Callout[] = [
  { n: 1, side: 'left', label: 'Worked time. Ticks on its own.', target: { x: LEFT, y: ROWS.timer }, place: 'row', pin: { x: 195, y: ROWS.timer - 4 } },
  { n: 2, side: 'left', label: 'On the clock, on lunch or on break.', target: { x: LEFT, y: ROWS.pill }, place: 'above', pin: { x: 150, y: ROWS.pill } },
  { n: 3, side: 'right', label: 'Your field, your block, your trees.', target: { x: RIGHT, y: ROWS.pill }, place: 'above', pin: { x: 212, y: ROWS.pill - 6 } },
  { n: 4, side: 'left', label: 'Big buttons. One tap marks the whole row.', target: { x: LEFT, y: ROWS.buttons }, place: 'row', pin: { x: BTN0, y: BTN_BOTTOM + 4 } },
  { n: 5, side: 'right', label: 'Wrong row? Undo is right there.', target: { x: RIGHT, y: ROWS.trees }, place: 'row', pin: { x: 196, y: ROWS.trees + 1 } },
  {
    n: 6,
    side: 'right',
    label: 'No clock-out button. On purpose.',
    sub: 'A bump in your pocket can’t end your day.',
    target: { x: RIGHT, y: ROWS.buttons },
    place: 'ghost',
    pin: { x: BREAK_R, y: BTN_BOTTOM + 4 },
  },
];

/** `n` equal slots between `from` and `to`. */
export function slots(from: number, to: number, n: number): Array<[number, number]> {
  const w = (to - from) / n;
  return Array.from({ length: n }, (_, i) => [from + i * w, from + (i + 1) * w] as [number, number]);
}

// ---------------------------------------------------------------------------
// The scene's progress windows (brief: .sections[lock-screen].animation)

export const T = {
  step: [0, 0.08],
  zoomIn: [0.08, 0.2],
  callouts: [0.2, 0.5],
  tap: [0.5, 0.62],
  zoomOut: [0.62, 0.7],
  unlock: [0.7, 0.85],
  compact: [0.74, 0.78],
  expanded: [0.78, 0.85],
  collapse: [0.85, 0.95],
} as const;

// ---------------------------------------------------------------------------
// Desktop: the zoom and the callouts around it

export interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

/** Room kept on each side of the zoomed phone: a 260px label column, the gutter and the elbow. */
const SIDE_ROOM = 260 + 48;

/** 1.7, or less when the window is too narrow to keep the callouts' columns. */
export function deskZoom(phoneWidth: number, viewportWidth: number): number {
  const fit = (viewportWidth - 2 * SIDE_ROOM) / phoneWidth;
  return Math.min(ZOOM.desk, Math.max(ZOOM.min, Math.floor(fit * 1000) / 1000));
}

export interface LaidCallout {
  n: Callout['n'];
  side: Side;
  dot: { x: number; y: number };
  /** SVG path, viewport px, from the dot to the label (or the ghost). */
  path: string;
  /** Left labels: x is the right edge; right labels: the left edge. y is the centre ('middle') or the top ('top'). */
  label: { x: number; y: number; maxWidth: number; valign: 'middle' | 'top' };
}

export interface DeskLayout {
  zoom: number;
  /** Translation that puts the card's centre in the middle of the viewport under the header. */
  x: number;
  y: number;
  /** The card and the phone after the zoom (viewport px). */
  card: { x: number; y: number; width: number; height: number };
  phone: { x: number; y: number; width: number; height: number };
  callouts: LaidCallout[];
  /** The ghost 'Clock out' button: left edge and centre line. */
  ghost: { x: number; y: number };
}

const GHOST_H = 46;
const EDGE = 18; // elbow distance from the zoomed phone
const TO_LABEL = 14; // elbow to label
const MARGIN = 24;
const R = 10; // elbow corner radius
const LIFT = 74; // pt: labels above or below their dot
const f = (n: number) => n.toFixed(1);

function leader(dot: { x: number; y: number }, elbowX: number, ly: number, endX: number): string {
  if (Math.abs(ly - dot.y) < 0.5) return `M${f(dot.x)} ${f(dot.y)}H${f(endX)}`;
  const hx = Math.sign(elbowX - dot.x) || 1;
  const vy = Math.sign(ly - dot.y);
  const r = Math.min(R, Math.abs(ly - dot.y) / 2);
  return (
    `M${f(dot.x)} ${f(dot.y)}H${f(elbowX - hx * r)}` +
    `Q${f(elbowX)} ${f(dot.y)} ${f(elbowX)} ${f(dot.y + vy * r)}` +
    `V${f(ly - vy * r)}Q${f(elbowX)} ${f(ly)} ${f(elbowX + hx * r)} ${f(ly)}H${f(endX)}`
  );
}

/**
 * Lays the zoom and the callouts out for one viewport. `phone` is the stage phone's
 * untransformed box; `viewport.top` is the header's height (the card centres below it).
 */
/**
 * Stacks boxes (given by centre `y` and height `h`) so that neighbours are at least `gap`
 * apart and all stay within [min, max]: overlapping pairs push apart around their middle;
 * a `fixed` box never moves. Returns the new centres, in the input order.
 */
export function separate(items: ReadonlyArray<{ y: number; h: number; fixed?: boolean }>, min: number, max: number, gap: number): number[] {
  const it = items.map((b, i) => ({ ...b, i, y: b.y }));
  const order = [...it].sort((a, b) => a.y - b.y);
  for (let pass = 0; pass < 40; pass += 1) {
    let moved = false;
    for (let k = 1; k < order.length; k += 1) {
      const a = order[k - 1]!;
      const b = order[k]!;
      const overlap = a.y + a.h / 2 + gap - (b.y - b.h / 2);
      if (overlap <= 0.001) continue;
      moved = true;
      if (a.fixed && b.fixed) continue;
      if (a.fixed) b.y += overlap;
      else if (b.fixed) a.y -= overlap;
      else {
        a.y -= overlap / 2;
        b.y += overlap / 2;
      }
    }
    for (const b of order) {
      if (b.fixed) continue;
      b.y = Math.min(Math.max(b.y, min + b.h / 2), Math.max(min + b.h / 2, max - b.h / 2));
    }
    if (!moved) break;
  }
  return it.map((b) => b.y);
}

export type LabelSizes = Partial<Record<Callout['n'], number>>;

/**
 * `sizes` are the labels' measured heights (px); with them the labels on each side are
 * stacked clear of each other and of the ghost block (which stays level with the buttons).
 */
export function deskLayout({
  phone,
  viewport,
  zoom,
  sizes,
}: {
  phone: Box;
  viewport: { width: number; height: number; top: number };
  zoom?: number;
  sizes?: LabelSizes;
}): DeskLayout {
  const z = zoom ?? deskZoom(phone.width, viewport.width);
  const s = (phone.width / FRAME.w) * z; // px per pt, zoomed
  const cx = viewport.width / 2;
  const cy = viewport.top + (viewport.height - viewport.top) / 2;
  const map = (p: { x: number; y: number }) => ({ x: cx + (p.x - CARD_CENTER.x) * s, y: cy + (p.y - CARD_CENTER.y) * s });

  const pw = phone.width * z;
  const ph = phone.height * z;
  const zp = { x: cx - ORIGIN.x * pw, y: cy - ORIGIN.y * ph, width: pw, height: ph };
  const c0 = map({ x: CARD.x, y: CARD.y });
  const card = { x: c0.x, y: c0.y, width: CARD.w * s, height: CARD.h * s };

  const elbowL = zp.x - EDGE;
  const elbowR = zp.x + zp.width + EDGE;
  const labelL = elbowL - TO_LABEL;
  const labelR = elbowR + TO_LABEL;
  const maxL = Math.min(380, labelL - MARGIN);
  const maxR = Math.min(380, viewport.width - MARGIN - labelR);

  const sixDot = map(CALLOUTS[5]!.target);
  const ghost = { x: labelR, y: sixDot.y };

  // Where each label would like to sit, then stacked per side by measured height.
  const want = new Map<Callout['n'], number>();
  for (const c of CALLOUTS) {
    const dot = map(c.target);
    want.set(c.n, c.place === 'above' ? dot.y - LIFT * s : c.place === 'below' ? dot.y + LIFT * s : dot.y);
  }
  const H = (n: Callout['n']) => sizes?.[n] ?? 44;
  const placed = new Map<Callout['n'], number>(want);
  const top = viewport.top + 16;
  const bottom = viewport.height - 16;
  for (const side of ['left', 'right'] as const) {
    const cs = CALLOUTS.filter((c) => c.side === side);
    const items = cs.map((c) =>
      c.place === 'ghost'
        ? // The ghost and the label under it: one block that does not move.
          { y: (ghost.y - GHOST_H / 2 + ghost.y + GHOST_H / 2 + 14 + H(6)) / 2, h: GHOST_H + 14 + H(6), fixed: true }
        : { y: want.get(c.n)!, h: H(c.n) },
    );
    const ys = separate(items, top, bottom, 8);
    cs.forEach((c, i) => c.place !== 'ghost' && placed.set(c.n, ys[i]!));
  }

  const callouts = CALLOUTS.map((c): LaidCallout => {
    const dot = map(c.target);
    const left = c.side === 'left';
    const elbowX = left ? elbowL : elbowR;
    const lx = left ? labelL : labelR;
    const maxWidth = left ? maxL : maxR;
    if (c.place === 'ghost') {
      return {
        n: c.n,
        side: c.side,
        dot,
        path: leader(dot, elbowX, dot.y, ghost.x),
        label: { x: ghost.x, y: ghost.y + GHOST_H / 2 + 14, maxWidth, valign: 'top' },
      };
    }
    const ly = placed.get(c.n)!;
    return { n: c.n, side: c.side, dot, path: leader(dot, elbowX, ly, lx), label: { x: lx, y: ly, maxWidth, valign: 'middle' } };
  });

  return {
    zoom: z,
    x: cx - (phone.left + ORIGIN.x * phone.width),
    y: cy - (phone.top + ORIGIN.y * phone.height),
    card,
    phone: zp,
    callouts,
    ghost,
  };
}

// ---------------------------------------------------------------------------
// Mobile: the section's own phone zooms in place

/** Translation (px) and scale that lift the card to MOB_TARGET of a phone `height` px tall. */
export function mobZoom(height: number): { x: number; y: number; scale: number } {
  return { x: 0, y: (MOB_TARGET - ORIGIN.y) * height, scale: ZOOM.mob };
}
