/**
 * LOCK-SCREEN WALLPAPERS: fir rows at first light (and a dusk twin), drawn as one small SVG.
 *
 * Each wallpaper is a 393 × 852 pt scene: a sky gradient, a low sun and its glow, a far
 * ridge, then six rows of the app icon's three-tier fir standing in evenly spaced farm
 * rows, nearer rows larger and darker, with warm haze between them. Rows are SVG patterns,
 * so the whole file stays under Vite's 4 KB inline limit and lands in the page CSS as a
 * data URI: one copy per page however many lock screens use it, and no extra request.
 *
 * The .svg files beside this module are generated from it (see make-wallpapers.ts) and
 * wallpaper.test.ts checks they are current. Pure string building: safe in Vitest.
 */
import { firTiers, ICON } from '../../../data/icon.ts';

export const WALLPAPERS = ['dawn-rows', 'dusk-rows'] as const;
export type WallpaperId = (typeof WALLPAPERS)[number];

/** The screen the wallpaper is drawn for, in points. */
export const WP = { w: 393, h: 852 } as const;

interface Band {
  /** y of the ground line the trees stand on. */
  base: number;
  /** Height of the tallest tree in the row; trees sit about h / 1.55 apart. */
  h: number;
  /** Row x offset, so rows do not line up. */
  dx: number;
  color: string;
  /** Opacity of the warm haze that rises off this row's ground. */
  haze: number;
}

interface Palette {
  sky: ReadonlyArray<readonly [number, string]>;
  glow: { cx: number; cy: number; r: number; color: string; opacity: number };
  sun: { cx: number; cy: number; r: number; color: string; opacity: number };
  ridge: { color: string; opacity: number };
  haze: string;
  /** Farthest row first. */
  bands: readonly Band[];
  /** Two tall trees framing the bottom corners. */
  near: string;
}

/** Rows recede toward the horizon: nearer rows stand lower, taller and darker. */
const ROWS = [
  { base: 561, h: 12, dx: -3 },
  { base: 577, h: 18, dx: -7 },
  { base: 601, h: 28, dx: -2 },
  { base: 640, h: 44, dx: -19 },
  { base: 700, h: 68, dx: -8 },
  { base: 792, h: 108, dx: -40 },
] as const;

const rows = (colors: readonly string[], haze: readonly number[]): Band[] =>
  ROWS.map((r, i) => ({ ...r, color: colors[i]!, haze: haze[i]! }));

const PALETTES: Record<WallpaperId, Palette> = {
  // brief.designSystem: SVG fir rows on #0D2418 → #29483A → #C79A5E.
  'dawn-rows': {
    sky: [
      [0, '#0D2418'],
      [0.34, '#14301F'],
      [0.5, '#29483A'],
      [0.585, '#6E6B4B'],
      [0.65, '#C79A5E'],
    ],
    glow: { cx: 246, cy: 524, r: 250, color: '#F4C47C', opacity: 0.66 },
    sun: { cx: 246, cy: 520, r: 8, color: '#FFF1CC', opacity: 1 },
    ridge: { color: '#857B57', opacity: 1 },
    haze: '#F2C27A',
    bands: rows(['#68694A', '#56603F', '#435239', '#314431', '#213325', '#142219'], [0.4, 0.32, 0.24, 0.16, 0.1, 0.06]),
    near: '#0A150F',
  },
  // The clock-out hour: the same rows against a dusk sky (brief tint 'dusk').
  'dusk-rows': {
    sky: [
      [0, '#16131C'],
      [0.36, '#241A24'],
      [0.5, '#3A2418'],
      [0.59, '#8A4E33'],
      [0.65, '#E08A4E'],
    ],
    glow: { cx: 150, cy: 530, r: 240, color: '#F0955A', opacity: 0.6 },
    sun: { cx: 150, cy: 527, r: 9, color: '#FFDDB4', opacity: 1 },
    ridge: { color: '#7A4A39', opacity: 1 },
    haze: '#F0955A',
    bands: rows(['#6A4335', '#56382F', '#422C28', '#30211F', '#211618', '#150E10'], [0.36, 0.28, 0.2, 0.13, 0.08, 0.05]),
    near: '#0C0809',
  },
};

/** Shortest decimal form: 0.4 → '.4', -0.5 → '-.5', 12.0 → '12'. */
const n = (v: number) => String(Math.round(v * 10) / 10).replace(/^(-?)0\./, '$1.');

/** The fir in the icon's 1024 space (tiers and a short trunk), for <symbol viewBox>. */
function firPath(): { d: string; viewBox: string } {
  const tiers = firTiers().map((t) => t.d.replace(/\d+\.\d+/g, (v) => String(Math.round(Number(v)))));
  const { y } = ICON.trunk;
  // A sheared farm tree shows a short, slim stem, not the icon's long, wide trunk.
  const w = 44;
  const x = ICON.center.x - w / 2;
  const bottom = 756;
  const trunk = `M${x} ${y}h${w}V${bottom}H${x}z`;
  const left = ICON.center.x - ICON.tiers[0].half;
  const top = ICON.tiers[2].apexY;
  return { d: tiers.join('') + trunk, viewBox: `${left} ${top} ${ICON.tiers[0].half * 2} ${bottom - top}` };
}

/**
 * One planted row as a symbol: ten slots, 10 units each, one tree per slot with a little
 * variation in height and place. A band draws it with fill (inherited through <use>) and
 * stretches it to its own size, so every row shares these bytes.
 */
const SLOTS = [1, 0.88, 0.95, 0.85, 0.98, 0.9, 0.86, 1, 0.92, 0.87] as const;
const JITTER = [0.2, -0.4, 0.3, 0, -0.3, 0.4, -0.1, 0.2, -0.4, 0.1] as const;
const ROW_W = SLOTS.length * 10;

function rowSymbol(): string {
  const trees = SLOTS.map((k, i) => {
    const h = 10 * k;
    const w = 9.4 * k;
    return `<use href="#f" x="${n(i * 10 + (10 - w) / 2 + JITTER[i]!)}" y="${n(10 - h)}" width="${n(w)}" height="${n(h)}"/>`;
  }).join('');
  return `<symbol id="w" viewBox="0 0 ${ROW_W} 10" preserveAspectRatio="none">${trees}</symbol>`;
}

/** A row: the row symbol tiled across the screen (a pattern when it repeats), then its ground and haze. */
function band(b: Band, i: number): { def: string; draw: string } {
  const gap = b.h / 1.55;
  const width = gap * SLOTS.length;
  const y = b.base - b.h;
  const h = b.h + 0.4;
  const tiled = b.dx + width < WP.w;
  const def = tiled
    ? `<pattern id="p${i}" x="${n(b.dx)}" y="${n(y)}" width="${n(width)}" height="${n(h)}" patternUnits="userSpaceOnUse" fill="${b.color}"><use href="#w" width="${n(width)}" height="${n(h)}"/></pattern>`
    : '';
  const trees = tiled
    ? `<rect y="${n(y)}" width="${WP.w}" height="${n(h)}" fill="url(#p${i})"/>`
    : `<use href="#w" x="${n(b.dx)}" y="${n(y)}" width="${n(width)}" height="${n(h)}" fill="${b.color}"/>`;
  const draw =
    trees +
    `<rect y="${n(b.base)}" width="${WP.w}" height="${n(WP.h - b.base)}" fill="${b.color}"/>` +
    `<rect y="${n(b.base - 2)}" width="${WP.w}" height="${n(Math.max(10, b.h * 0.42))}" fill="url(#m)" opacity="${n(b.haze)}"/>`;
  return { def, draw };
}

/** The far ridge: a soft, low line of hills along the horizon. */
function ridge(p: Palette): string {
  const y = 548;
  return `<path d="M0 ${y - 9}C58 ${y - 22} 104 ${y - 6} 160 ${y - 13}S262 ${y - 27} 316 ${y - 15}S376 ${y - 8} 393 ${y - 12}V${y + 20}H0z" fill="${p.ridge.color}" opacity="${n(p.ridge.opacity)}"/>`;
}

/** The wallpaper as a standalone SVG document. */
export function wallpaperSVG(id: WallpaperId): string {
  const p = PALETTES[id];
  const fir = firPath();
  const bands = p.bands.map(band);
  const sky = p.sky.map(([o, c]) => `<stop offset="${n(o)}" stop-color="${c}"/>`).join('');
  const nearH = 300;
  const nearW = nearH * 0.6;
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${WP.w} ${WP.h}">`,
    '<defs>',
    `<linearGradient id="s" x2="0" y2="1">${sky}</linearGradient>`,
    `<radialGradient id="g"><stop offset="0" stop-color="${p.glow.color}" stop-opacity="${n(p.glow.opacity)}"/><stop offset=".45" stop-color="${p.glow.color}" stop-opacity="${n(p.glow.opacity * 0.32)}"/><stop offset="1" stop-color="${p.glow.color}" stop-opacity="0"/></radialGradient>`,
    `<linearGradient id="m" x2="0" y2="1"><stop offset="0" stop-color="${p.haze}"/><stop offset="1" stop-color="${p.haze}" stop-opacity="0"/></linearGradient>`,
    `<symbol id="f" viewBox="${fir.viewBox}" preserveAspectRatio="none"><path d="${fir.d}"/></symbol>`,
    rowSymbol(),
    ...bands.map((b) => b.def),
    '</defs>',
    `<rect width="${WP.w}" height="${WP.h}" fill="url(#s)"/>`,
    `<ellipse cx="${p.glow.cx}" cy="${p.glow.cy}" rx="${p.glow.r}" ry="${n(p.glow.r * 0.6)}" fill="url(#g)"/>`,
    `<circle cx="${p.sun.cx}" cy="${p.sun.cy}" r="${p.sun.r}" fill="${p.sun.color}" opacity="${n(p.sun.opacity)}"/>`,
    ridge(p),
    ...bands.map((b) => b.draw),
    `<g fill="${p.near}">`,
    `<use href="#f" x="${n(-nearW * 0.46)}" y="${WP.h - nearH + 70}" width="${n(nearW)}" height="${nearH}"/>`,
    `<use href="#f" x="${n(WP.w - nearW * 0.5)}" y="${n(WP.h - nearH * 0.9 + 66)}" width="${n(nearW * 0.9)}" height="${n(nearH * 0.9)}"/>`,
    '</g>',
    '</svg>',
  ].join('');
}

/** The color under the Live Activity once the wallpaper is blurred (fallback for the twin). */
export const TWIN_FALLBACK: Record<WallpaperId, string> = {
  'dawn-rows': 'linear-gradient(180deg, #4b5a3f, #1d2e22 30%, #142219)',
  'dusk-rows': 'linear-gradient(180deg, #5a3a30, #2a1c1c 30%, #170f12)',
};
