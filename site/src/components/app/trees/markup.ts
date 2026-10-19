/**
 * The Trees tab's map, as HTML strings (server-side only; TreesTab.astro injects them with
 * set:html so hundreds of dots carry no scoping attributes). Geometry follows the app's
 * FieldLayout (TreeFarmKit/Trees/FieldLayout.swift): blocks sit in strips, row numbers in a
 * 26 pt gutter left of each block, a 6 pt inset inside the block's rounded border, 14 pt
 * between blocks, alternating row stripes. Cell sizes are tuned so one block fills the
 * 393 pt screen at L.
 *
 * Hooks (CONTRACT.md, map): [data-map-row="37"] (a row of 10 dots, target block only),
 * [data-block-row="2-37"] (every rendered row), [data-tree="2-37-4"] (one dot),
 * [data-row-label="37"], [data-note-marker="2-36-7"] (> [data-note-ripple]).
 *
 * A dot is <i data-tree data-s="ring|earlier|today">. Its fills are pseudo-elements whose
 * opacity reads the custom properties --e (green) and --g (gold), so a scene fills a row with
 *   gsap.to(q('[data-map-row="37"] [data-tree]'), { '--g': 1, stagger: 0.01 })
 * and crossfades gold → green with { '--g': 0, '--e': 1 }. Pops are transforms on the dot.
 */
import { FIELD, type TreeNote } from '../../../data/ledger.ts';
import { fieldRuns, statusOf, type TreeState } from '../../../scripts/fieldmap.ts';

export type AppZoom = 'XS' | 'S' | 'M' | 'L';

/** Cell width (along a row), row height, dot diameter, ring width, row-number size: all in pt. */
export const APP_ZOOM: Record<AppZoom, { cw: number; ch: number; dot: number; ring: number; label: number }> = {
  XS: { cw: 12, ch: 8, dot: 6.5, ring: 1, label: 8.5 },
  S: { cw: 18, ch: 12, dot: 9.5, ring: 1.25, label: 10.5 },
  M: { cw: 26, ch: 18, dot: 13.5, ring: 1.5, label: 12 },
  L: { cw: 32, ch: 28, dot: 18, ring: 1.75, label: 13 },
};

/** Screen-level geometry in pt. */
export const APP_MAP = {
  /** The screen's side margin: the target block's gutter starts here. */
  left: 16,
  /** Row numbers left of each block. */
  gutter: 26,
  /** Between a block's border and its trees. */
  inset: 6,
  /** Between blocks in a strip. */
  gap: 14,
  /** Pinned block header: name and tree numbers. */
  header: 40,
  screen: 393,
} as const;

const ACROSS = FIELD.treesPerRow;
const DOWN = FIELD.rowsPerBlock;
const PER_STRIP = FIELD.blocksPerGridRow;

export interface WindowBlock {
  block: number;
  /** Left edge of the block's frame (gutter included), pt from the screen's left. */
  x: number;
  /** Frame width: gutter + inset + 10 cells + inset. */
  width: number;
  /** Rows drawn, inclusive. */
  rows: [number, number];
}

let seq = 0;
/** A page-unique id for SVG pattern definitions. */
export const nextId = (prefix = 'tm') => `${prefix}${(seq += 1)}`;

/** Which blocks and rows the map viewport shows: the target block at the left margin, its strip-mates beside it. */
export function appMapWindow(o: { block: number; first: number; zoom: AppZoom; height: number; width?: number }): {
  blocks: WindowBlock[];
} {
  const z = APP_ZOOM[o.zoom];
  const width = APP_MAP.gutter + 2 * APP_MAP.inset + ACROSS * z.cw;
  const screen = o.width ?? APP_MAP.screen;
  const first = Math.max(1, Math.min(DOWN, o.first));
  const last = Math.min(DOWN, first + Math.ceil((o.height - APP_MAP.header) / z.ch));
  const strip = Math.floor((o.block - 1) / PER_STRIP);
  const blocks: WindowBlock[] = [];
  for (let b = strip * PER_STRIP + 1; b <= (strip + 1) * PER_STRIP; b += 1) {
    const x = APP_MAP.left + (b - o.block) * (width + APP_MAP.gap);
    // A neighbour showing only a sliver of its border reads as a glitch, not a block.
    if (x + width < 12 || x + APP_MAP.gutter >= screen) continue;
    blocks.push({ block: b, x, width, rows: [first, last] });
  }
  return { blocks };
}

const STATE_NAME: Record<TreeState, string> = { 0: 'ring', 1: 'earlier', 2: 'today' };

export interface AppMapOptions {
  status: Uint8Array;
  block: number;
  first: number;
  zoom: AppZoom;
  /** Viewport height in pt (rows are drawn to the bottom of the screen, under the tab bar). */
  height: number;
  notes?: readonly TreeNote[];
  /** The row the worker is on (its number gets the fir capsule). */
  currentRow?: number | null;
  /** The tree a sheet is open on (fir selection ring). */
  selected?: { block: number; row: number; tree: number } | null;
}

/** The zoomed map: blocks with headers, borders, stripes, row numbers, dots and note markers. */
export function appTreeMarkup(o: AppMapOptions): string {
  const z = APP_ZOOM[o.zoom];
  const { blocks } = appMapWindow(o);
  const out: string[] = [];
  const notesBy = new Map<string, TreeNote[]>();
  for (const n of o.notes ?? []) {
    const k = `${n.block}-${n.row}`;
    notesBy.set(k, [...(notesBy.get(k) ?? []), n]);
  }
  const numFs = Math.min(10, z.cw * 0.62);
  // At XS the rows are 8 pt apart: number every fifth row (and row 1), like a ruler.
  const labelled = (row: number) => o.zoom !== 'XS' || row === 1 || row % 5 === 0;
  for (const w of blocks) {
    const target = w.block === o.block;
    const [r0, r1] = w.rows;
    const n = r1 - r0 + 1;
    // The border runs on above the window when the block continues there (the header hides it).
    const top = r0 === 1 ? -APP_MAP.inset : -APP_MAP.inset - 40;
    const bottom = r1 === DOWN ? n * z.ch + APP_MAP.inset : n * z.ch + 400;
    out.push(
      `<div class="tm-b${target ? ' tm-target' : ''}" data-block="${w.block}" style="--x:${w.x};--w:${w.width}">`,
      `<div class="tm-sheet${r0 === 1 ? '' : ' tm-open-top'}${r1 === DOWN ? '' : ' tm-open-bottom'}" style="--top:${top};--bot:${bottom}"></div>`,
    );
    for (let row = r0; row <= r1; row += 1) {
      const cur = target && o.currentRow === row;
      out.push(
        `<div class="tm-row${row % 2 === 0 ? ' tm-even' : ''}"${target ? ` data-map-row="${row}"` : ''} data-block-row="${w.block}-${row}" style="--r:${row - r0}">`,
        `<span class="tm-rl${cur ? ' tm-cur' : ''}"${target ? ` data-row-label="${row}"` : ''}>${labelled(row) || cur ? row : ''}</span>`,
      );
      for (let tree = 1; tree <= ACROSS; tree += 1) {
        const s = statusOf(o.status, w.block, row, tree);
        const sel = o.selected && o.selected.block === w.block && o.selected.row === row && o.selected.tree === tree;
        out.push(`<i data-tree="${w.block}-${row}-${tree}" data-s="${STATE_NAME[s]}"${sel ? ' data-selected' : ''}></i>`);
      }
      for (const note of notesBy.get(`${w.block}-${row}`) ?? [])
        out.push(
          `<span class="tm-note" data-note-marker="${note.block}-${note.row}-${note.tree}" data-flag="${note.flag}" style="--t:${note.tree - 1}"><b class="tm-ripple" data-note-ripple></b><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><use href="#i-flag.fill"></use></svg></span>`,
        );
      out.push('</div>');
    }
    // The pinned header: block name, then tree numbers over their columns.
    out.push(`<div class="tm-h"><span class="tm-name">Block ${w.block}</span><span class="tm-cols" style="--nfs:${numFs}">`);
    for (let tree = 1; tree <= ACROSS; tree += 1) out.push(`<span>${tree}</span>`);
    out.push('</span></div></div>');
  }
  return out.join('');
}

/** The whole field at 'All': square cells sized to the width, block names, no row numbers (the app's overview). */
export function appOverviewSVG(o: { status: Uint8Array; notes?: readonly TreeNote[]; target?: number; width?: number; id?: string }): string {
  const width = o.width ?? APP_MAP.screen - 2 * APP_MAP.left;
  const id = o.id ?? 'ov';
  const inset = 2;
  const gap = 5;
  const head = 16;
  const stripGap = 10;
  const side = Math.floor(((width - 2 - PER_STRIP * 2 * inset - (PER_STRIP - 1) * gap) / (PER_STRIP * ACROSS)) * 4) / 4;
  const bw = ACROSS * side + 2 * inset;
  const bh = DOWN * side + 2 * inset;
  const stripH = head + bh;
  const height = FIELD.gridRows * stripH + (FIELD.gridRows - 1) * stripGap;
  const origin = (b: number) => {
    const i = b - 1;
    return { x: 1 + (i % PER_STRIP) * (bw + gap), y: Math.floor(i / PER_STRIP) * (stripH + stripGap) };
  };
  const r = (v: number) => String(Math.round(v * 100) / 100);
  const fills = [`url(#${id}-n)`, `url(#${id}-e)`, `url(#${id}-t)`];
  const out: string[] = [
    `<svg class="tm-ov" viewBox="0 0 ${r(width)} ${r(height)}" style="--h:${r(height)}" aria-hidden="true" focusable="false">`,
    '<defs>',
    `<pattern id="${id}-n" width="${side}" height="${side}" patternUnits="userSpaceOnUse"><rect x=".5" y=".5" width="${side - 1}" height="${side - 1}" rx=".7" fill="#C9D8CC"/></pattern>`,
    `<pattern id="${id}-e" width="${side}" height="${side}" patternUnits="userSpaceOnUse"><rect x=".5" y=".5" width="${side - 1}" height="${side - 1}" rx=".7" fill="#1D5B3A"/></pattern>`,
    `<pattern id="${id}-t" width="${side}" height="${side}" patternUnits="userSpaceOnUse"><rect x=".5" y=".5" width="${side - 1}" height="${side - 1}" rx=".7" fill="#B57A12"/></pattern>`,
    '</defs>',
  ];
  for (let b = 1; b <= FIELD.blocks; b += 1) {
    const p = origin(b);
    const hot = b === o.target;
    out.push(
      `<text x="${r(p.x + 1)}" y="${r(p.y + head - 5)}" class="tm-ov-name${hot ? ' tm-ov-hot' : ''}">Block ${b}</text>`,
      `<rect x="${r(p.x)}" y="${r(p.y + head)}" width="${r(bw)}" height="${r(bh)}" rx="3" class="tm-ov-block${hot ? ' tm-ov-hot' : ''}"/>`,
    );
  }
  for (const run of fieldRuns(o.status)) {
    const p = origin(run.block);
    const x = p.x + inset + (run.tree0 - 1) * side;
    const y = p.y + head + inset + (run.row0 - 1) * side;
    out.push(
      `<g transform="translate(${r(x)} ${r(y)})"><rect width="${r((run.tree1 - run.tree0 + 1) * side)}" height="${r((run.row1 - run.row0 + 1) * side)}" fill="${fills[run.state]}"/></g>`,
    );
  }
  for (const n of o.notes ?? []) {
    const p = origin(n.block);
    const cx = p.x + inset + (n.tree - 0.5) * side;
    const cy = p.y + head + inset + (n.row - 0.5) * side;
    out.push(
      `<g data-note-marker="${n.block}-${n.row}-${n.tree}" transform="translate(${r(cx - 1)} ${r(cy - 10)}) scale(.5)"><path d="M5.6 2.8c.5 0 .9.4.9.9v.1h10.9c.7 0 1.1.7.8 1.3l-2.4 3.9 2.4 3.9c.4.6 0 1.3-.8 1.3H6.5v7c0 .5-.4.9-.9.9s-.9-.4-.9-.9V3.7c0-.5.4-.9.9-.9Z" fill="#A2391F" stroke="#fff" stroke-width="2.4" paint-order="stroke" stroke-linejoin="round"/></g>`,
    );
  }
  out.push('</svg>');
  return out.join('');
}
