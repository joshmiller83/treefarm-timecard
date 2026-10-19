/**
 * HERO · 7:02 Clock in: the section's data and choreography as plain values, so Vitest can
 * check them against the brief and the ledger (hero.test.ts), and Hero.astro and the scene
 * (src/scripts/scenes/hero.ts) share one source.
 *
 *   heroPhoneLabel()      the phone's aria-label, built from the ledger and the Siri lines
 *   spokenWords(text)     “Clock in with Time Card.” as word spans (quotes on the ends)
 *   INTRO, cue(), …       the on-load sequence, in seconds (mobile plays it at 70%)
 *   SCROLL                the scrubbed scene's windows, in progress units (0–1)
 *   BANDS, bandTrees()…   the three fir-row silhouettes, as tiling SVG pattern geometry
 *   STARS                 four faint dawn stars
 *
 * Pure: no DOM, no GSAP. Safe in Astro frontmatter, the scene bundle and Vitest.
 */
import { MOMENTS, fmtTime } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { activityView } from '../../components/system/lockscreen/activity.ts';

export const REPO = 'https://github.com/joshmiller83/treefarm-timecard';

// ---------------------------------------------------------------------------
// Words

/**
 * The phone's aria-label, as the brief words it:
 * 'iPhone lock screen at 7:02 AM. Siri says: Clocked in at 7:02. You’re on block 2, row 14.
 *  The Time Card Live Activity shows On the clock, North field, Block 2, 0 trees this shift,
 *  and buttons for row 14, row 15, row 16 and Break.'
 */
export function heroPhoneLabel(): string {
  const v = activityView({ at: MOMENTS.clockIn });
  return (
    `iPhone lock screen at ${fmtTime(MOMENTS.clockIn)}. Siri says: ${SIRI.clockIn.reply} ` +
    `The Time Card Live Activity shows ${v.pill}, ${v.field}, ${v.block}, ${v.treesText} trees this shift, ` +
    `and buttons for row ${v.rows.join(', row ')} and Break.`
  );
}

export interface SpokenWord {
  text: string;
  /** Carries the opening curly quote. */
  open: boolean;
  /** Carries the closing curly quote. */
  close: boolean;
  /** Joined to the next word with a no-break space (keeps 'Time Card' on one line). */
  glue: boolean;
}

/** A spoken line as word spans for the karaoke-style reveal. The quotes ride the end words. */
export function spokenWords(text: string): SpokenWord[] {
  const parts = text.trim().split(/\s+/);
  return parts.map((w, i) => ({
    text: w,
    open: i === 0,
    close: i === parts.length - 1,
    glue: w === 'Time' && parts[i + 1]?.startsWith('Card') === true,
  }));
}

// ---------------------------------------------------------------------------
// The load sequence (seconds). Runs once, under html.motion only; never touches the H1.

export interface Cue {
  at: number;
  dur: number;
  /** Seconds between items. */
  stagger?: number;
  /** How many items the stagger runs over (for the end time). */
  n?: number;
  /** Extra plays (yoyo breathing). */
  repeat?: number;
}

export const INTRO = {
  /** The tint layers fade up from #050B08. */
  tint: { at: 0, dur: 0.6 },
  /** The fir bands rise y 24 → 0, far to near. */
  bands: { at: 0.1, dur: 0.9, stagger: 0.1, n: 3 },
  /** The phone fades up y 40 → 0, its screen still dark. */
  phone: { at: 0.3, dur: 0.9 },
  /** Eyebrow, body, pill, buttons, fine print: y 16 → 0 and fade. */
  copy: { at: 0.35, dur: 0.5, stagger: 0.06, n: 5 },
  /** The spoken line, word by word (the 'You' label first). */
  words: { at: 0.9, dur: 0.4, stagger: 0.06, n: 6 },
  /** The Siri glow fades in… */
  glow: { at: 1.3, dur: 0.4 },
  /** …and breathes twice: scale 1 → 1.02, yoyo, four .3 s halves. */
  breathe: { at: 1.3, dur: 0.3, repeat: 3 },
  /** The screen wakes (the black overlay lifts). */
  wake: { at: 1.5, dur: 0.4 },
  /** Siri's card drops in (y -16 → 0) and its words appear. */
  snippet: { at: 1.8, dur: 0.45 },
  /** The card and the glow fade out; the lock-screen clock comes back. */
  siriOut: { at: 2.5, dur: 0.3 },
  /** The Live Activity rises (y 48 → 0, scale .96 → 1, fade); the timer starts ticking. */
  activity: { at: 2.6, dur: 0.5 },
  /** Its four buttons, one after another. */
  buttons: { at: 2.65, dur: 0.3, stagger: 0.05, n: 4 },
  /** The field bar fills to the field's share shaped so far (2,190 of 8,540 trees). */
  fieldbar: { at: 2.7, dur: 0.4 },
} as const satisfies Record<string, Cue>;

export type CueKey = keyof typeof INTRO;

/** Mobile plays the same sequence at 70% durations. */
export const MOBILE_SCALE = 0.7;

/** A cue scaled for a breakpoint. */
export function cue(c: Cue, scale = 1): { at: number; dur: number; stagger: number } {
  return { at: c.at * scale, dur: c.dur * scale, stagger: (c.stagger ?? 0) * scale };
}

const cueEnd = (c: Cue) => c.at + (c.stagger ?? 0) * Math.max(0, (c.n ?? 1) - 1) + c.dur * ((c.repeat ?? 0) + 1);

/** When the whole sequence has settled (seconds). The brief allows 3.1. */
export const INTRO_END = Math.max(...Object.values(INTRO).map(cueEnd));

export const introEnd = (scale = 1) => INTRO_END * scale;

// ---------------------------------------------------------------------------
// The scrubbed scene (progress 0–1 of the 160vh desktop track)

export const SCROLL = {
  /** The spoken line fades and lifts 20px. */
  said: [0, 0.3],
  /** The copy lifts 60px and fades. */
  copy: [0.15, 0.6],
  /** The fir bands sink (parallax) and the far band thins .6 → .3. */
  bands: [0, 1],
  /** The header's shift ribbon and its '7:02 AM · Clock in' tag fade in. */
  ribbon: [0.5, 0.7],
} as const satisfies Record<string, readonly [number, number]>;

// ---------------------------------------------------------------------------
// Fir-row silhouettes: three bands of the app icon's fir (<use href="#fir">), each an SVG
// pattern tile that repeats across any width. Rows on a tree farm are planted evenly, so
// the trees are evenly spaced with a little variety in height, on gently rolling ground.

export interface Band {
  id: 'far' | 'mid' | 'near';
  color: string;
  /** Band opacity (the far band sits in the haze). */
  opacity: number;
  /** Nominal tree height, px. */
  tree: number;
  /** Pattern tile width, px (the ground's wave repeats exactly once per tile). */
  tile: number;
  /** Trees per tile. */
  count: number;
  /** Ground wave amplitude, px. */
  wave: number;
  /** Wave phase, radians. */
  phase: number;
  seed: number;
  /** Desktop parallax: how far the band sinks over the track, vh. */
  sink: number;
  /** Mobile parallax, vh. */
  sinkMob: number;
}

export const BANDS: readonly Band[] = [
  { id: 'far', color: '#173229', opacity: 0.6, tree: 42, tile: 624, count: 24, wave: 6, phase: 0.6, seed: 7, sink: 3, sinkMob: 1.5 },
  { id: 'mid', color: '#10261B', opacity: 1, tree: 72, tile: 768, count: 16, wave: 4, phase: 2.2, seed: 19, sink: 5.5, sinkMob: 2.75 },
  { id: 'near', color: '#0A1C13', opacity: 1, tree: 120, tile: 920, count: 10, wave: 3, phase: 4.1, seed: 41, sink: 8, sinkMob: 4 },
];

/** The fir symbol's aspect (viewBox 500 × 600) and how much of it is empty under the trunk. */
const FIR_ASPECT = 500 / 600;
const FIR_FOOT = 14 / 600; // empty space under the trunk plus a little planting depth
const H_MIN = 0.8;
const H_SPAN = 0.3;

const r2 = (n: number) => Math.round(n * 100) / 100;

/** Seeded PRNG (mulberry32): the same trees on every build. */
function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The ground line's height at the top of the tallest possible tree, so nothing clips. */
const groundBase = (b: Band) => Math.ceil(b.tree * (H_MIN + H_SPAN) + b.wave + 1);

/** y of the ground at x (periodic over the tile, so tiles meet without a step). */
export function groundAt(b: Band, x: number): number {
  return groundBase(b) + b.wave * Math.sin((2 * Math.PI * x) / b.tile + b.phase);
}

/** The pattern tile's height: trees, the ground's dip and a strip of ground under it. */
export function bandHeight(b: Band): number {
  return groundBase(b) + b.wave + Math.ceil(b.tree * 0.1) + 2;
}

export interface Tree {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** The trees in one tile (plus twins one tile over for any tree crossing an edge). */
export function bandTrees(b: Band): Tree[] {
  const rand = rng(b.seed);
  const step = b.tile / b.count;
  const out: Tree[] = [];
  for (let i = 0; i < b.count; i += 1) {
    const h = r2(b.tree * (H_MIN + rand() * H_SPAN));
    const w = (h * 500) / 600;
    const cx = (i + 0.5) * step + (rand() - 0.5) * step * 0.24;
    const y = r2(groundAt(b, cx) - h + h * FIR_FOOT);
    const x = r2(cx - w / 2);
    out.push({ x, y, w, h });
    if (x < 0) out.push({ x: r2(x + b.tile), y, w, h });
    if (x + w > b.tile) out.push({ x: r2(x - b.tile), y, w, h });
  }
  return out;
}

/** The ground under the trees: the wave across the tile, then down to the tile's bottom. */
export function bandGround(b: Band): string {
  const h = bandHeight(b);
  const pts: string[] = [];
  const n = Math.ceil(b.tile / 16);
  for (let i = 0; i <= n; i += 1) {
    const x = (b.tile * i) / n;
    pts.push(`${r2(x)} ${r2(groundAt(b, x))}`);
  }
  return `M${pts[0]}L${pts.slice(1).join('L')}L${b.tile} ${h}L0 ${h}Z`;
}

export { FIR_ASPECT };

// ---------------------------------------------------------------------------
// Stars: 2px #F2F5EF at 35%. x/y place them in the desktop frame (percent of the
// viewport), mx/my in the mobile section, away from the copy and the phone.

export const STARS: ReadonlyArray<{ x: number; y: number; mx: number; my: number }> = [
  { x: 4.6, y: 21, mx: 7, my: 63 },
  { x: 45.5, y: 11.5, mx: 88, my: 58 },
  { x: 91, y: 17, mx: 93, my: 71 },
  { x: 53, y: 56, mx: 5, my: 76 },
];
