/**
 * The crew chapter's second phone and its wires, as plain math (no DOM).
 *
 * A pose places the second phone relative to the phone it sits behind: x and y are fractions
 * of that phone's width and height, rotate is degrees, scale is about the phone's centre,
 * exactly as GSAP applies xPercent/yPercent/rotation/scale with a centred transform origin.
 *
 * The second phone peeks out on the LEFT (the brief has it on the right): its row-number
 * gutter and first trees are on its left edge, so Sam's tap on row 12 and the row filling
 * gold stay in view instead of hiding behind your phone.
 */
export interface Pose {
  x: number;
  y: number;
  rotate: number;
  scale: number;
}
export interface Pt {
  x: number;
  y: number;
}
export interface Box {
  w: number;
  h: number;
}

export const POSES = {
  /** Desktop: behind the stage phone. */
  desk: {
    hidden: { x: 0, y: 0, rotate: 0, scale: 0.86 },
    rest: { x: -0.36, y: -0.04, rotate: -4, scale: 0.86 },
    /** Sam's tap: further out, so his row 12 filling gold reads (still clear of the copy at 1024). */
    swing: { x: -0.48, y: -0.04, rotate: -5, scale: 0.86 },
    front: { x: -0.2, y: 0, rotate: -1.5, scale: 1 },
  },
  /** Mobile: behind the section phone. */
  mob: {
    hidden: { x: 0, y: 0, rotate: 0, scale: 0.84 },
    rest: { x: -0.34, y: -0.03, rotate: -3, scale: 0.84 },
    swing: { x: -0.42, y: -0.03, rotate: -3.5, scale: 0.84 },
    front: { x: -0.08, y: 0.01, rotate: -1, scale: 1 },
  },
} satisfies Record<string, Record<'hidden' | 'rest' | 'swing' | 'front', Pose>>;

/** Desktop camera: the stage phone (and the rig the second phone hangs on) during the chapter. */
export const PULL = { scale: 0.88, y: 0.035 } as const;

/** Where the point (u·w, v·h) of a box lands once the pose is applied (box coordinates). */
export function posePoint(box: Box, pose: Pose, u: number, v: number): Pt {
  const cx = box.w / 2;
  const cy = box.h / 2;
  const dx = (u * box.w - cx) * pose.scale;
  const dy = (v * box.h - cy) * pose.scale;
  const a = (pose.rotate * Math.PI) / 180;
  const round = (n: number) => Math.round(n * 1000) / 1000;
  return {
    x: round(cx + pose.x * box.w + dx * Math.cos(a) - dy * Math.sin(a)),
    y: round(cy + pose.y * box.h + dx * Math.sin(a) + dy * Math.cos(a)),
  };
}

/** The axis-aligned bounds of a posed box, in box coordinates. */
export function poseBounds(box: Box, pose: Pose): { left: number; right: number; top: number; bottom: number } {
  const pts = [
    [0, 0],
    [1, 0],
    [0, 1],
    [1, 1],
  ].map(([u, v]) => posePoint(box, pose, u!, v!));
  return {
    left: Math.min(...pts.map((p) => p.x)),
    right: Math.max(...pts.map((p) => p.x)),
    top: Math.min(...pts.map((p) => p.y)),
    bottom: Math.max(...pts.map((p) => p.y)),
  };
}

const f = (n: number) => String(Math.round(n * 10) / 10);

/**
 * A wire from a phone (a) up to the server (b): it leaves the phone straight up and arrives
 * at the server level, so two wires meet the glyph like a soft roof.
 */
export function wirePath(a: Pt, b: Pt): string {
  const dy = b.y - a.y;
  return `M${f(a.x)} ${f(a.y)}C${f(a.x)} ${f(a.y + dy * 0.62)} ${f(b.x + (a.x - b.x) * 0.32)} ${f(b.y)} ${f(b.x)} ${f(b.y)}`;
}
