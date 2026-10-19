/**
 * The Time Card app icon as SVG geometry, ported from tools/make_icon.swift so the page,
 * the favicon and the Open Graph image all draw the same icon as the app.
 * Coordinates are in the icon's 1024 × 1024 design space, y down.
 */

export interface Pt {
  x: number;
  y: number;
}

export const ICON = {
  size: 1024,
  /** Corner radius for the rounded-square mask used on the web (iOS masks the app icon itself). */
  corner: 230,
  center: { x: 512, y: 520 },
  ringR: 352,
  ringW: 30,
  colors: {
    bgTop: '#2B7D52',
    bgBottom: '#154A2E',
    ring: '#E2A644',
    ticks: '#F5E6C6',
    ticksOpacity: 0.9,
    tree: '#F7F2E4',
    treeShade: '#E9E0C8',
    trunk: '#B57A12',
  },
  trunk: { x: 476, y: 700, w: 72, h: 112, r: 12 },
  /** Bottom tier first, so upper tiers overlap, as in the app icon. */
  tiers: [
    { apexY: 430, baseY: 730, half: 250 },
    { apexY: 330, baseY: 590, half: 200 },
    { apexY: 228, baseY: 450, half: 148 },
  ],
  tierCorner: 30,
} as const;

const r2 = (n: number) => Math.round(n * 100) / 100;
const sub = (a: Pt, b: Pt): Pt => ({ x: a.x - b.x, y: a.y - b.y });
const len = (a: Pt) => Math.hypot(a.x, a.y);
const unit = (a: Pt): Pt => ({ x: a.x / len(a), y: a.y / len(a) });

/** A triangle with rounded corners, like CGPath addArc(tangent1End:tangent2End:radius:). */
export function roundedTrianglePath(apex: Pt, left: Pt, right: Pt, radius: number): string {
  const mid = { x: (left.x + right.x) / 2, y: left.y };
  const corners: Array<[Pt, Pt, Pt]> = [
    [mid, right, apex],
    [right, apex, left],
    [apex, left, right],
  ];
  let d = `M${r2(mid.x)} ${r2(mid.y)}`;
  for (const [prev, c, next] of corners) {
    const u1 = unit(sub(prev, c));
    const u2 = unit(sub(next, c));
    const theta = Math.acos(Math.max(-1, Math.min(1, u1.x * u2.x + u1.y * u2.y)));
    const dist = radius / Math.tan(theta / 2);
    const t1 = { x: c.x + u1.x * dist, y: c.y + u1.y * dist };
    const t2 = { x: c.x + u2.x * dist, y: c.y + u2.y * dist };
    const cross = (c.x - prev.x) * (next.y - c.y) - (c.y - prev.y) * (next.x - c.x);
    d += `L${r2(t1.x)} ${r2(t1.y)}A${radius} ${radius} 0 0 ${cross > 0 ? 1 : 0} ${r2(t2.x)} ${r2(t2.y)}`;
  }
  return `${d}Z`;
}

/** The three fir tiers, bottom first, with their fills. */
export function firTiers(): Array<{ d: string; fill: string }> {
  const { center } = ICON;
  return ICON.tiers.map((t, i) => ({
    d: roundedTrianglePath(
      { x: center.x, y: t.apexY },
      { x: center.x - t.half, y: t.baseY },
      { x: center.x + t.half, y: t.baseY },
      ICON.tierCorner,
    ),
    fill: i % 2 === 0 ? ICON.colors.tree : ICON.colors.treeShade,
  }));
}

/** The ten tick marks (12 and 6 o'clock are left out: the tree points at 12, the trunk stands at 6). */
export function ticks(): Array<{ x1: number; y1: number; x2: number; y2: number; w: number; hour: number }> {
  const { center: c, ringR: r } = ICON;
  const out = [];
  for (let i = 0; i < 12; i += 1) {
    if (i === 0 || i === 6) continue;
    const a = (i / 12) * Math.PI * 2 - Math.PI / 2;
    const major = i % 3 === 0;
    const r0 = r - (major ? 74 : 54);
    const r1 = r - 34;
    out.push({
      x1: r2(c.x + Math.cos(a) * r0),
      y1: r2(c.y + Math.sin(a) * r0),
      x2: r2(c.x + Math.cos(a) * r1),
      y2: r2(c.y + Math.sin(a) * r1),
      w: major ? 20 : 12,
      hour: i,
    });
  }
  return out;
}

/** A standalone SVG of the icon (favicon.svg, the OG template). */
export function appIconSVG({ rounded = true, title = 'Time Card' } = {}): string {
  const { size, colors, center, ringR, ringW, trunk } = ICON;
  const tiers = firTiers()
    .map((t) => `<path d="${t.d}" fill="${t.fill}"/>`)
    .join('');
  const tickLines = ticks()
    .map((t) => `<line x1="${t.x1}" y1="${t.y1}" x2="${t.x2}" y2="${t.y2}" stroke-width="${t.w}"/>`)
    .join('');
  return [
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" role="img" aria-label="${title}">`,
    `<title>${title}</title>`,
    `<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${colors.bgTop}"/><stop offset="1" stop-color="${colors.bgBottom}"/></linearGradient></defs>`,
    `<rect width="${size}" height="${size}" rx="${rounded ? ICON.corner : 0}" fill="url(#g)"/>`,
    `<circle cx="${center.x}" cy="${center.y}" r="${ringR}" fill="none" stroke="${colors.ring}" stroke-width="${ringW}"/>`,
    `<g stroke="${colors.ticks}" stroke-opacity="${colors.ticksOpacity}" stroke-linecap="round">${tickLines}</g>`,
    `<rect x="${trunk.x}" y="${trunk.y}" width="${trunk.w}" height="${trunk.h}" rx="${trunk.r}" fill="${colors.trunk}"/>`,
    tiers,
    `</svg>`,
  ].join('');
}
