/**
 * The field map's pure parts: geometry, ledger-driven tree states, the map in words, the field
 * scene's choreography, the camera and the in-app map window. The canvas renderer itself is
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
} from '../data/ledger.ts';
import {
  BEATS,
  DEMO_ROW,
  DIM_FLOOR,
  EARLIER_S,
  EMPTY,
  LANDSCAPE_TURN,
  MAX_ZOOM_PITCH,
  TODAY,
  ZOOM_TARGET,
  blockLabelPx,
  blockOrigin,
  blockRect,
  blockRuns,
  cameraAt,
  countStatus,
  dimAt,
  dotCenter,
  fieldLayout,
  fieldRuns,
  fieldSummary,
  fitView,
  frameRect,
  goldRows,
  lerpView,
  notesAt,
  overviewView,
  runPieces,
  sceneState,
  statusOf,
  targetRect,
  toFrame,
  toScreen,
  treeIndex,
  treeStatus,
  visibleCells,
  zoomSummary,
  createTryIt,
} from './fieldmap.ts';
import * as fieldstate from './fieldstate.ts';
import { APP_ZOOM, appMapWindow, appTreeMarkup } from '../components/app/trees/markup.ts';

const { fieldSVG } = fieldstate;

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

  it('turns the field a quarter turn anticlockwise for the landscape overview (about 1.58:1)', () => {
    const l = fieldLayout('landscape');
    expect(l.width).toBe(125);
    expect(l.height).toBe(79);
    expect(l.width / l.height).toBeCloseTo(1.58, 1);
    // Rows run left to right; tree 1 is at the bottom of its band; block 1 sits bottom left.
    expect(dotCenter(2, 1, 1, 'portrait')).toEqual({ x: 12, y: 0.5 });
    expect(dotCenter(2, 1, 1, 'landscape')).toEqual({ x: 0.5, y: 67 });
    expect(dotCenter(2, 61, 10, 'landscape')).toEqual({ x: 60.5, y: 58 });
    expect(blockRect(1, 'landscape')).toEqual({ x: 0, y: 69, w: 61, h: 10 });
    expect(blockRect(7, 'landscape')).toEqual({ x: 0, y: 0, w: 61, h: 10 });
    expect(blockRect(8, 'landscape')).toEqual({ x: 64, y: 69, w: 61, h: 10 });
    // A true rotation (distances kept, orientation kept), so a camera can turn it back upright.
    const a = dotCenter(2, 30, 3);
    const b = dotCenter(5, 7, 9);
    const [fa, fb] = [toFrame(a, 'landscape'), toFrame(b, 'landscape')];
    expect(Math.hypot(fa.x - fb.x, fa.y - fb.y)).toBeCloseTo(Math.hypot(a.x - b.x, a.y - b.y));
    const cross = (p: { x: number; y: number }, q: { x: number; y: number }, r: { x: number; y: number }) =>
      (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
    const c = dotCenter(9, 40, 1);
    expect(Math.sign(cross(fa, fb, toFrame(c, 'landscape')))).toBe(Math.sign(cross(a, b, c)));
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
  it('2:16 PM: 2,190 green plus 230 gold, the rest rings', () => {
    const s = treeStatus({ at: MOMENTS.field });
    const c = countStatus(s);
    expect(c.earlier).toBe(2190);
    expect(c.earlier).toBe(EARLIER_COUNT);
    expect(c.today).toBe(230);
    expect(c.today).toBe(treesAt(MOMENTS.field));
    expect(c.earlier + c.today).toBe(fieldShapedAt(MOMENTS.field));
    expect(c.empty).toBe(8540 - 2420);
  });

  it('gold is block 2 rows 14–36; row 37 is still to do at 2:16', () => {
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

  it('builds runs block by block', () => {
    const s = treeStatus({ at: MOMENTS.field });
    expect(fieldRuns(s)).toEqual(Array.from({ length: 14 }, (_, b) => blockRuns(s, b + 1)).flat());
    // Block 2: green rows 1–13, gold 14–36, rings 37–61.
    expect(blockRuns(s, 2).map((r) => [r.row0, r.row1, r.state])).toEqual([
      [1, 13, EARLIER_S],
      [14, 36, TODAY],
      [37, 61, EMPTY],
    ]);
  });

  it('runs cover every tree exactly once', () => {
    const runs = fieldRuns(treeStatus({ at: MOMENTS.field }));
    const total = runs.reduce((n, r) => n + (r.row1 - r.row0 + 1) * (r.tree1 - r.tree0 + 1), 0);
    expect(total).toBe(8540);
    const gold = runs.filter((r) => r.state === TODAY).reduce((n, r) => n + (r.row1 - r.row0 + 1) * (r.tree1 - r.tree0 + 1), 0);
    expect(gold).toBe(230);
    expect(runs.length).toBeLessThan(40);
  });

  it('describes the close-up from the ledger', () => {
    const text = zoomSummary();
    expect(text).toContain('Rows 28 to 36 shaped today in gold');
    expect(text).toContain('rows 37 to 40 not yet shaped');
    expect(text).toContain('row 31, tree 4: Replant');
    expect(zoomSummary({ block: 3, from: 6, to: 16 }, MOMENTS.synced)).toContain('Rows 6 to 10 shaped earlier in green, row 11 shaped today in gold, row 12 shaped earlier in green');
  });

  it('summarises the map in words from the ledger: the brief’s sentence at 2:16 PM', () => {
    expect(fieldSummary(MOMENTS.field)).toBe(
      'Map of North field: 14 blocks of 61 rows, 10 trees a row, 8,540 trees. Rows 14 to 36 of block 2 shaped today in gold. Block 1, blocks 8 and 9, and the first rows of blocks 2, 3 and 4 shaped earlier in green. The rest not yet shaped.',
    );
    expect(fieldSummary()).toBe(fieldSummary(MOMENTS.field));
  });

  it('follows the ledger at other minutes', () => {
    expect(fieldSummary(MOMENTS.clockIn)).toContain('Nothing shaped today yet.');
    expect(fieldSummary(14 * 60)).toContain('Rows 14 to 34 and part of row 35 of block 2 shaped today in gold.');
    // After the sync Alex's row 11 is his, Sam's row 12 is green.
    const synced = fieldSummary(MOMENTS.synced);
    expect(synced).toContain('Rows 14 to 36 of block 2 and row 11 of block 3 shaped today in gold.');
    expect(synced).toContain('and row 12 of block 3 shaped earlier in green.');
    expect(fieldSummary(MOMENTS.clockOut)).toContain('Rows 14 to 41 of block 2 and row 11 of block 3 shaped today in gold.');
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
    // Snapped to whole device pixels per pitch, and capped.
    expect(fitView({ x: 0, y: 0, w: 30, h: 30 }, 400, 400, {}, Infinity, 2).s).toBe(13);
    expect(fitView({ x: 0, y: 0, w: 10, h: 10 }, 400, 400, {}, 24, 2).s).toBe(24);
    // …but not when that would shrink a small map by more than 6% (3.9 → 3 at 1×).
    expect(fitView({ x: 0, y: 0, w: 100, h: 100 }, 390, 390, {}, Infinity, 1).s).toBe(3.9);
  });

  it('interpolates zoom geometrically about a fixed anchor', () => {
    const a = { cx: 50, cy: 50, s: 2 };
    const b = { cx: 20, cy: 30, s: 8 };
    expect(lerpView(a, b, 0)).toEqual({ ...a, r: 0 });
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

  it('turns and zooms as one spiral: one point stays put, the turn is linear', () => {
    const W = 1138;
    const H = 658;
    const a = overviewView('landscape', W, H, 2);
    const b = cameraAt(1, 'landscape', W, H);
    expect(a.r).toBe(LANDSCAPE_TURN);
    expect(b.r).toBe(0);
    expect(lerpView(a, b, 0.5).r).toBeCloseTo(LANDSCAPE_TURN / 2);
    // Find the fixed point numerically: the world point whose screen position is the same in a and b.
    // Then every in-between view keeps it there too.
    const grid = 400;
    let best = { d: Infinity, x: 0, y: 0 };
    for (let i = 0; i <= grid; i += 1)
      for (let j = 0; j <= grid; j += 1) {
        const x = -40 + (i / grid) * 160;
        const y = -40 + (j / grid) * 200;
        const p = toScreen(a, W, H, x, y);
        const q = toScreen(b, W, H, x, y);
        const d = Math.hypot(p.x - q.x, p.y - q.y);
        if (d < best.d) best = { d, x, y };
      }
    expect(best.d).toBeLessThan(12);
    const p0 = toScreen(a, W, H, best.x, best.y);
    for (const t of [0.2, 0.5, 0.8]) {
      const p = toScreen(lerpView(a, b, t), W, H, best.x, best.y);
      expect(Math.hypot(p.x - p0.x, p.y - p0.y)).toBeLessThan(12);
    }
  });

  it('ends upright on block 2 rows 28–40 with 7px dots and the row numbers on the left', () => {
    for (const [W, H, o] of [
      [1138, 658, 'landscape'],
      [343, 545, 'portrait'],
    ] as const) {
      const cam = cameraAt(1, o, W, H, ZOOM_TARGET, 2);
      const t = targetRect(ZOOM_TARGET);
      expect(cam.r).toBe(0);
      expect(cam.cx).toBeCloseTo(t.x + t.w / 2);
      expect(cam.cy).toBeCloseTo(t.y + t.h / 2);
      expect(cam.s).toBeLessThanOrEqual(MAX_ZOOM_PITCH);
      expect(cam.s * 0.3).toBeGreaterThan(6.5); // dot radius ≈ 7px
      // Rows run down the screen; tree 1 sits left of tree 10; the numbers' gutter is left of tree 1.
      const og = blockOrigin(2);
      const r28 = toScreen(cam, W, H, og.x + 0.5, og.y + 27.5);
      const r40 = toScreen(cam, W, H, og.x + 0.5, og.y + 39.5);
      const t10 = toScreen(cam, W, H, og.x + 9.5, og.y + 27.5);
      const num = toScreen(cam, W, H, og.x - 0.7, og.y + 27.5);
      expect(r40.y).toBeGreaterThan(r28.y);
      expect(t10.x).toBeGreaterThan(r28.x);
      expect(num.x).toBeLessThan(r28.x);
      expect(num.x).toBeGreaterThan(20);
      expect(cameraAt(0, o, W, H).s).toBeLessThan(cam.s);
    }
  });

  it('dims everything but the target rows in the close-up', () => {
    expect(dimAt(0)).toBe(1);
    expect(dimAt(1)).toBe(DIM_FLOOR);
    const s = treeStatus({ at: MOMENTS.field });
    const full: string[] = [];
    let cells = 0;
    for (const r of fieldRuns(s))
      for (const p of runPieces(r, ZOOM_TARGET, dimAt(1))) {
        cells += (p.row1 - p.row0 + 1) * (r.tree1 - r.tree0 + 1);
        if (p.alpha === 1) for (let row = p.row0; row <= p.row1; row += 1) full.push(`${r.block}-${row}`);
      }
    expect(cells).toBe(8540);
    expect([...new Set(full)]).toEqual(Array.from({ length: 13 }, (_, i) => `2-${28 + i}`));
    // In the overview nothing is dimmed.
    expect(fieldRuns(s).flatMap((r) => runPieces(r, ZOOM_TARGET, dimAt(0))).every((p) => p.alpha === 1)).toBe(true);
  });

  it('culls to the visible cells, turned or not', () => {
    const W = 1180;
    const H = 700;
    const count = (cells: ReturnType<typeof visibleCells>) =>
      cells.reduce((n, c) => n + (c.row1 - c.row0 + 1) * (c.tree1 - c.tree0 + 1), 0);
    expect(count(visibleCells(cameraAt(0, 'landscape', W, H), W, H))).toBe(8540);
    const zoomed = visibleCells(cameraAt(1, 'landscape', W, H), W, H);
    expect(count(zoomed)).toBeLessThan(2000);
    expect(zoomed.some((c) => c.block === 2 && c.row0 <= 28 && c.row1 >= 40)).toBe(true);
    const half = visibleCells(cameraAt(0.5, 'landscape', W, H), W, H);
    expect(count(half)).toBeGreaterThan(count(zoomed));
    expect(count(half)).toBeLessThan(8540);
  });

  it('fits “Block 14” over its block on a phone, or abbreviates to “B14”', () => {
    const phone = blockLabelPx('portrait', 343, 545, 2);
    expect(phone.short).toBe(false);
    expect(phone.text(14)).toBe('Block 14');
    // The label and a 5px gap fit in a block plus its gutter.
    const s = overviewView('portrait', 343, 545, 2).s;
    expect(8 * 0.6 * phone.px + 5).toBeLessThanOrEqual(11.5 * s + 1e-9);
    const narrow = blockLabelPx('portrait', 301, 484, 2);
    expect(narrow.short).toBe(true);
    expect(narrow.text(14)).toBe('B14');
    expect(blockLabelPx('landscape', 1138).text(7)).toBe('Block 7');
    expect(blockLabelPx('landscape', 600).text(7)).toBe('7');
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

describe('Try it (the small interactive copy of block 2 rows 28–40)', () => {
  it('starts from the 2:16 ledger state', () => {
    const t = createTryIt();
    expect(t.rows).toEqual([28, 40]);
    expect(t.get(36, 1)).toBe(TODAY);
    expect(t.get(37, 1)).toBe(EMPTY);
    expect(t.canUndo).toBe(false);
  });

  it('a row number marks the whole row, and again clears it', () => {
    const t = createTryIt();
    expect(t.rowTap(37)).toBe('Row 37 marked, 10 trees');
    expect(Array.from({ length: 10 }, (_, i) => t.get(37, i + 1))).toEqual(Array(10).fill(TODAY));
    expect(t.rowTap(37)).toBe('Row 37 cleared, 10 trees');
    expect(t.get(37, 4)).toBe(EMPTY);
  });

  it('one mode toggles a tree; erase clears; undo pops; reset restores', () => {
    const t = createTryIt();
    expect(t.treeTap(38, 4, 'one')).toBe('Row 38, tree 4 marked');
    expect(t.treeTap(38, 4, 'one')).toBe('Row 38, tree 4 unmarked');
    expect(t.treeTap(36, 2, 'erase')).toBe('Row 36, tree 2 unmarked');
    expect(t.treeTap(39, 2, 'erase')).toBe('Row 39, tree 2 isn’t marked');
    expect(t.undo()).toBe('Undid your last change');
    expect(t.get(36, 2)).toBe(TODAY);
    t.rowTap(40);
    expect(t.reset()).toBe('Back to the map at 2:16 PM');
    expect(t.get(40, 1)).toBe(EMPTY);
    expect(t.canUndo).toBe(false);
    expect(t.undo()).toBe('Nothing to undo');
  });

  it('fill anchors on the first tap and fills to the second, in reading order', () => {
    const t = createTryIt();
    expect(t.treeTap(37, 9, 'fill')).toBe('Row 37, tree 9. Now tap the last tree');
    expect(t.anchor).toEqual({ row: 37, tree: 9 });
    expect(t.treeTap(38, 2, 'fill')).toBe('Marked 4 trees, from row 37, tree 9 to row 38, tree 2');
    expect([t.get(37, 8), t.get(37, 9), t.get(37, 10), t.get(38, 1), t.get(38, 2), t.get(38, 3)]).toEqual([EMPTY, TODAY, TODAY, TODAY, TODAY, EMPTY]);
    expect(t.anchor).toBeNull();
    // Backwards works too, and tapping the anchor again starts over.
    t.treeTap(40, 3, 'fill');
    expect(t.treeTap(40, 3, 'fill')).toBe('Start over: tap the first tree');
    t.treeTap(40, 3, 'fill');
    expect(t.treeTap(40, 1, 'fill')).toBe('Marked 3 trees, from row 40, tree 1 to row 40, tree 3');
  });

  it('never changes trees someone else shaped', () => {
    const t = createTryIt({ block: 2, from: 10, to: 16 });
    expect(t.get(12, 1)).toBe(EARLIER_S);
    expect(t.treeTap(12, 1, 'one')).toBe('Row 12, tree 1 was shaped earlier');
    expect(t.rowTap(12)).toBe('Every tree in row 12 was shaped earlier');
    expect(t.treeTap(12, 1, 'erase')).toBe('Row 12, tree 1 was shaped earlier');
    expect(t.canUndo).toBe(false);
  });
});
