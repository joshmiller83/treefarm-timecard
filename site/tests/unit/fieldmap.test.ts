/**
 * The field map's pure parts: geometry, ledger-driven tree states, the field scene's
 * choreography, the camera and the in-app map window. The canvas renderer itself is
 * checked in Playwright (tests/lab/map.spec.ts).
 */
import { describe, expect, it } from 'vitest';
import {
  CREW_MARKS,
  EARLIER_COUNT,
  FIELD,
  FIELD_TREES,
  MARKS,
  MOMENTS,
  OFFLINE,
  OLD_NOTE,
  TREE_NOTE,
  fieldShapedAt,
  treesAt,
} from '../../src/data/ledger.ts';
import {
  BEATS,
  DEMO_ROW,
  EARLIER_S,
  EMPTY,
  FIELD_SUMMARY,
  TODAY,
  ZOOM_TARGET,
  blockOrigin,
  cameraAt,
  countStatus,
  dotCenter,
  fieldLayout,
  fieldRuns,
  fieldSVG,
  frameRect,
  goldRows,
  lerpView,
  notesAt,
  sceneState,
  statusOf,
  targetRect,
  treeIndex,
  treeStatus,
  visibleCells,
  fitView,
} from '../../src/scripts/fieldmap.ts';
import { APP_ZOOM, appMapWindow, appTreeMarkup } from '../../src/components/app/trees/markup.ts';

const rowStatus = (s: Uint8Array, block: number, row: number) =>
  Array.from({ length: FIELD.treesPerRow }, (_, t) => statusOf(s, block, row, t + 1));

describe('field layout', () => {
  it('draws exactly 8,540 dots, every one in its own cell', () => {
    for (const o of ['portrait', 'landscape'] as const) {
      const { dots, width, height } = fieldLayout(o);
      expect(dots).toHaveLength(8540);
      expect(dots).toHaveLength(FIELD_TREES);
      const cells = new Set(dots.map((d) => `${d.x},${d.y}`));
      expect(cells.size).toBe(8540);
      for (const d of dots) {
        expect(d.x).toBeGreaterThanOrEqual(0);
        expect(d.y).toBeGreaterThanOrEqual(0);
        expect(d.x + 1).toBeLessThanOrEqual(width);
        expect(d.y + 1).toBeLessThanOrEqual(height);
      }
    }
  });

  it('lays blocks out in 2 strips of 7 with 1.5-pitch gutters and a 3-pitch gap', () => {
    const p = fieldLayout('portrait');
    expect(p.width).toBe(7 * 10 + 6 * 1.5); // 79
    expect(p.height).toBe(2 * 61 + 3); // 125
    expect(blockOrigin(1)).toEqual({ x: 0, y: 0 });
    expect(blockOrigin(2)).toEqual({ x: 11.5, y: 0 });
    expect(blockOrigin(7)).toEqual({ x: 69, y: 0 });
    expect(blockOrigin(8)).toEqual({ x: 0, y: 64 });
    expect(blockOrigin(14)).toEqual({ x: 69, y: 64 });
  });

  it('transposes for the landscape overview (about 1.55:1 and wider than tall)', () => {
    const l = fieldLayout('landscape');
    expect(l.width).toBe(125);
    expect(l.height).toBe(79);
    expect(l.width / l.height).toBeCloseTo(1.58, 1);
    // Row r of a block runs down the screen in landscape: x follows the row, y the tree.
    expect(dotCenter(2, 1, 1, 'landscape')).toEqual({ x: 0.5, y: 12 });
    expect(dotCenter(2, 61, 10, 'landscape')).toEqual({ x: 60.5, y: 21 });
    expect(dotCenter(2, 1, 1, 'portrait')).toEqual({ x: 12, y: 0.5 });
  });

  it('frames include room for the block labels', () => {
    const p = frameRect('portrait');
    expect(p.y).toBeLessThan(0);
    expect(p.h).toBeGreaterThan(125);
    const l = frameRect('landscape');
    expect(l.x).toBeLessThan(0);
    expect(l.w).toBeGreaterThan(125);
    expect(l.w / l.h).toBeGreaterThan(1.5);
  });

  it('indexes trees block by block, row by row', () => {
    expect(treeIndex(1, 1, 1)).toBe(0);
    expect(treeIndex(1, 1, 10)).toBe(9);
    expect(treeIndex(1, 2, 1)).toBe(10);
    expect(treeIndex(2, 1, 1)).toBe(610);
    expect(treeIndex(14, 61, 10)).toBe(8539);
  });
});

describe('tree states from the ledger', () => {
  it('2:15 PM: 2,190 green plus 230 gold, the rest rings', () => {
    const s = treeStatus({ at: MOMENTS.field });
    const c = countStatus(s);
    expect(c.earlier).toBe(2190);
    expect(c.earlier).toBe(EARLIER_COUNT);
    expect(c.today).toBe(230);
    expect(c.today).toBe(treesAt(MOMENTS.field));
    expect(c.earlier + c.today).toBe(fieldShapedAt(MOMENTS.field));
    expect(c.empty).toBe(8540 - 2420);
  });

  it('gold is block 2 rows 14–36; row 37 is still to do at 2:15', () => {
    const s = treeStatus({ at: MOMENTS.field });
    expect(rowStatus(s, 2, 13).every((v) => v === EARLIER_S)).toBe(true);
    for (let r = 14; r <= 36; r += 1) expect(rowStatus(s, 2, r).every((v) => v === TODAY)).toBe(true);
    expect(rowStatus(s, 2, 37).every((v) => v === EMPTY)).toBe(true);
    expect(rowStatus(s, 1, 61).every((v) => v === EARLIER_S)).toBe(true);
    expect(rowStatus(s, 9, 1).every((v) => v === EARLIER_S)).toBe(true);
    expect(rowStatus(s, 10, 1).every((v) => v === EMPTY)).toBe(true);
  });

  it('fills a part row from tree 1: two trees of row 35 at 2:00', () => {
    const s = treeStatus({ at: 14 * 60 });
    expect(rowStatus(s, 2, 35)).toEqual([TODAY, TODAY, ...Array(8).fill(EMPTY)]);
  });

  it('has no gold before the first row and 290 at clock-out', () => {
    expect(countStatus(treeStatus({ at: MOMENTS.clockIn })).today).toBe(0);
    expect(countStatus(treeStatus({ at: MOMENTS.clockOut })).today).toBe(treesAt(MOMENTS.clockOut));
  });

  it('crew, 2:47: block 3 rows 1–10 green, Sam’s row 12 not marked yet', () => {
    const s = treeStatus({ at: MOMENTS.crew });
    expect(rowStatus(s, 3, 10).every((v) => v === EARLIER_S)).toBe(true);
    expect(rowStatus(s, 3, 11).every((v) => v === EMPTY)).toBe(true);
    expect(rowStatus(s, 3, 12).every((v) => v === EMPTY)).toBe(true);
  });

  it('offline, 2:56: Alex’s rows 11 and 12 are gold on his phone and Sam’s mark has not arrived', () => {
    const s = treeStatus({ at: MOMENTS.alexRow12 });
    expect(rowStatus(s, 3, 11).every((v) => v === TODAY)).toBe(true);
    expect(rowStatus(s, 3, 12).every((v) => v === TODAY)).toBe(true);
  });

  it('synced, 3:00: first mark wins, so row 11 stays gold and row 12 turns green', () => {
    const s = treeStatus({ at: MOMENTS.synced });
    expect(rowStatus(s, 3, 11).every((v) => v === TODAY)).toBe(true);
    expect(rowStatus(s, 3, 12).every((v) => v === EARLIER_S)).toBe(true);
    // Sam's 2:49 tap precedes Alex's 2:56 mark in the ledger.
    const sam = CREW_MARKS.find((m) => m.block === 3 && m.row === 12)!;
    const alex = MARKS.find((m) => m.block === 3 && m.row === 12)!;
    expect(sam.at).toBeLessThan(alex.at);
    expect(alex.rejected).toBe(true);
  });

  it('Sam’s phone at 2:49: his row 12 gold, Alex’s block 2 rows green, Alex’s offline row 11 not there yet', () => {
    const s = treeStatus({ at: MOMENTS.samMarks, who: 'Sam' });
    expect(rowStatus(s, 3, 12).every((v) => v === TODAY)).toBe(true);
    expect(rowStatus(s, 3, 11).every((v) => v === EMPTY)).toBe(true);
    expect(rowStatus(s, 2, 20).every((v) => v === EARLIER_S)).toBe(true);
    expect(countStatus(s).today).toBe(10);
    // After sync Sam sees Alex's row 11 as green, and never Alex's rejected row 12 as Alex's.
    const later = treeStatus({ at: OFFLINE.back, who: 'Sam' });
    expect(rowStatus(later, 3, 11).every((v) => v === EARLIER_S)).toBe(true);
    expect(rowStatus(later, 3, 12).every((v) => v === TODAY)).toBe(true);
  });

  it('pending rows show gold whatever the ledger says', () => {
    const s = treeStatus({ at: MOMENTS.crew, pending: [{ block: 5, row: 2 }] });
    expect(rowStatus(s, 5, 2).every((v) => v === TODAY)).toBe(true);
  });

  it('lists the notes that exist at a minute', () => {
    expect(notesAt(MOMENTS.field)).toEqual([OLD_NOTE]);
    expect(notesAt(MOMENTS.treeNote)).toEqual([OLD_NOTE, TREE_NOTE]);
  });

  it('orders today’s rows by when they were marked', () => {
    const rows = goldRows(treeStatus({ at: MOMENTS.field }));
    expect(rows).toHaveLength(23);
    expect(rows[0]).toEqual({ block: 2, row: 14 });
    expect(rows[22]).toEqual({ block: 2, row: 36 });
  });

  it('runs cover every tree exactly once', () => {
    const runs = fieldRuns(treeStatus({ at: MOMENTS.field }));
    const total = runs.reduce((n, r) => n + (r.row1 - r.row0 + 1) * (r.tree1 - r.tree0 + 1), 0);
    expect(total).toBe(8540);
    const gold = runs.filter((r) => r.state === TODAY).reduce((n, r) => n + (r.row1 - r.row0 + 1) * (r.tree1 - r.tree0 + 1), 0);
    expect(gold).toBe(230);
    expect(runs.length).toBeLessThan(40);
  });

  it('summarises the map in words from the ledger', () => {
    expect(FIELD_SUMMARY).toContain('8,540 trees');
    expect(FIELD_SUMMARY).toContain('Rows 14 to 36 of block 2 shaped today in gold');
  });
});

describe('the static SVG fallback', () => {
  it('draws one rect per run, labels every block and carries no script', () => {
    const svg = fieldSVG({ orientation: 'portrait', at: MOMENTS.field });
    expect(svg.startsWith('<svg')).toBe(true);
    for (let b = 1; b <= 14; b += 1) expect(svg).toContain(`>Block ${b}<`);
    expect(svg).not.toContain('<script');
    expect(svg).toContain('data-note="2-31-4"');
  });

  it('labels rows 28–40 in the zoomed view', () => {
    const svg = fieldSVG({ orientation: 'portrait', at: MOMENTS.field, zoom: ZOOM_TARGET });
    for (let r = 28; r <= 40; r += 1) expect(svg).toContain(`>${r}<`);
  });
});

describe('the field scene choreography (brief: field.animation)', () => {
  it('starts in the overview with today’s rows still rings', () => {
    const s = sceneState(0);
    expect(s.camera).toBe(0);
    expect(s.reveal).toBe(0);
    expect(s.season).toBe(0);
  });

  it('flips rows 14→36 one row per 1/23 of [.3, .52]', () => {
    expect(sceneState(BEATS.reveal[0]).reveal).toBe(0);
    expect(sceneState(BEATS.reveal[1]).reveal).toBe(23);
    const mid = (BEATS.reveal[0] + BEATS.reveal[1]) / 2;
    expect(sceneState(mid).reveal).toBeCloseTo(11.5, 5);
  });

  it('zooms in, plays the row 37 demo, then puts row 37 back to rings', () => {
    expect(sceneState(0.6).camera).toBe(1);
    expect(sceneState(0.6).labels).toBe(1);
    expect(sceneState((BEATS.demoIn[1] + BEATS.demoOut[0]) / 2).demo).toBe(1);
    expect(sceneState(BEATS.demoOut[1]).demo).toBe(0);
    expect(DEMO_ROW).toEqual({ block: 2, row: 37 });
  });

  it('flips the season to rings and keeps the note, then restores the fills and zooms out', () => {
    expect(sceneState(0.84).season).toBe(1);
    expect(sceneState(0.84).camera).toBe(1);
    expect(sceneState(0.84).pulse).toBeGreaterThan(0);
    const end = sceneState(1);
    expect(end.season).toBe(0);
    expect(end.camera).toBe(0);
    expect(end.reveal).toBe(23);
    expect(end.labels).toBe(0);
  });

  it('is pure: the same progress gives the same state', () => {
    for (const p of [0, 0.31, 0.5, 0.66, 0.8, 0.95, 1]) expect(sceneState(p)).toEqual(sceneState(p));
  });

  it('clamps out-of-range progress', () => {
    expect(sceneState(-1)).toEqual(sceneState(0));
    expect(sceneState(2)).toEqual(sceneState(1));
  });
});

describe('camera', () => {
  it('fits a rect inside the canvas, centered', () => {
    const v = fitView({ x: 0, y: 0, w: 100, h: 50 }, 400, 400);
    expect(v.s).toBe(4);
    expect(v.cx).toBe(50);
    expect(v.cy).toBe(25);
  });

  it('interpolates zoom geometrically about a fixed anchor', () => {
    const a = { cx: 50, cy: 50, s: 2 };
    const b = { cx: 20, cy: 30, s: 8 };
    expect(lerpView(a, b, 0)).toEqual(a);
    const end = lerpView(a, b, 1);
    expect(end.cx).toBeCloseTo(20);
    expect(end.cy).toBeCloseTo(30);
    expect(end.s).toBeCloseTo(8);
    expect(lerpView(a, b, 0.5).s).toBeCloseTo(4); // geometric mean, not 5
    // The anchor point stays put on screen through the whole move.
    const W = 300;
    const screen = (v: { cx: number; s: number }, x: number) => (x - v.cx) * v.s + W / 2;
    const anchorX = (b.cx - (a.cx * a.s) / b.s) / (1 - a.s / b.s);
    for (const t of [0, 0.25, 0.5, 0.75, 1]) expect(screen(lerpView(a, b, t), anchorX)).toBeCloseTo(screen(a, anchorX), 6);
  });

  it('zooms the overview to block 2 rows 28–40 with ~7px dots on a desktop canvas', () => {
    const W = 1180;
    const H = 700;
    const cam = cameraAt(1, 'landscape', W, H, ZOOM_TARGET);
    const t = targetRect(ZOOM_TARGET, 'landscape');
    const center = { x: t.x + t.w / 2, y: t.y + t.h / 2 };
    expect(cam.cx).toBeCloseTo(center.x);
    expect(cam.cy).toBeCloseTo(center.y);
    expect(cam.s).toBeLessThanOrEqual(24);
    expect(cam.s).toBeGreaterThan(18);
    const over = cameraAt(0, 'landscape', W, H, ZOOM_TARGET);
    expect(over.s).toBeLessThan(cam.s);
  });

  it('culls to the visible cells', () => {
    const W = 1180;
    const H = 700;
    const zoomed = visibleCells(cameraAt(1, 'landscape', W, H, ZOOM_TARGET), 'landscape', W, H);
    const all = visibleCells(cameraAt(0, 'landscape', W, H, ZOOM_TARGET), 'landscape', W, H);
    const count = (cells: ReturnType<typeof visibleCells>) =>
      cells.reduce((n, c) => n + (c.row1 - c.row0 + 1) * (c.tree1 - c.tree0 + 1), 0);
    expect(count(all)).toBe(8540);
    expect(count(zoomed)).toBeLessThan(2500);
    expect(zoomed.some((c) => c.block === 2 && c.row0 <= 28 && c.row1 >= 40)).toBe(true);
  });
});

describe('the Trees tab map window', () => {
  it('fits one block at L zoom inside the 393 pt screen', () => {
    const w = appMapWindow({ block: 2, first: 28, zoom: 'L', height: 560 });
    const target = w.blocks.find((b) => b.block === 2)!;
    expect(target.x).toBe(16);
    expect(target.x + target.width).toBeLessThanOrEqual(393 - 16);
    expect(target.rows[0]).toBe(28);
    expect(target.rows[1]).toBeGreaterThanOrEqual(40);
    expect(w.blocks.filter((b) => b.x < 393)).toHaveLength(1);
  });

  it('shows neighbouring blocks in the same strip at smaller zooms', () => {
    const m = appMapWindow({ block: 2, first: 28, zoom: 'M', height: 560 });
    expect(m.blocks.map((b) => b.block)).toEqual([2, 3]);
    const xs = appMapWindow({ block: 2, first: 1, zoom: 'XS', height: 560 });
    expect(xs.blocks.map((b) => b.block)).toEqual([2, 3, 4]);
    // Strips never mix: block 7's neighbour on the right is nothing, not block 8.
    const edge = appMapWindow({ block: 7, first: 1, zoom: 'XS', height: 560 });
    expect(edge.blocks.map((b) => b.block)).toEqual([7]);
  });

  it('never runs past row 61', () => {
    const w = appMapWindow({ block: 3, first: 50, zoom: 'XS', height: 900 });
    expect(w.blocks[0]!.rows[1]).toBe(61);
  });

  it('zoom metrics grow from XS to L', () => {
    const order = ['XS', 'S', 'M', 'L'] as const;
    for (let i = 1; i < order.length; i += 1) expect(APP_ZOOM[order[i]!].cw).toBeGreaterThan(APP_ZOOM[order[i - 1]!].cw);
  });

  it('writes the scene hooks for each tree and row', () => {
    const s = treeStatus({ at: MOMENTS.field });
    const html = appTreeMarkup({ status: s, block: 2, first: 28, zoom: 'L', height: 560, notes: [OLD_NOTE], currentRow: 37 });
    expect(html).toContain('data-map-row="37"');
    expect(html).toContain('data-row-label="37"');
    expect(html).toContain('data-tree="2-37-4"');
    expect(html).toContain('data-note-marker="2-31-4"');
    expect(html).toMatch(/data-tree="2-36-1" data-s="today"/);
    expect(html).toMatch(/data-tree="2-37-1" data-s="ring"/);
    expect(html).not.toContain('<script');
  });
});
