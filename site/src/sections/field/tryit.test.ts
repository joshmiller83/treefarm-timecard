import { describe, expect, it } from 'vitest';
import { MOMENTS, OLD_NOTE, treesAt } from '../../data/ledger.ts';
import { EARLIER_S, EMPTY, TODAY, ZOOM_TARGET, createTryIt } from '../../scripts/fieldstate.ts';
import { GRID, cellLabel, gridMove, rowLabel, todayCount } from './tryit.ts';

const ROWS = ZOOM_TARGET.to - ZOOM_TARGET.from + 1;

describe('Try it: the grid shape', () => {
  it('is block 2 rows 28–40: 13 rows of a row number plus 10 trees', () => {
    expect(GRID.rows).toBe(ROWS);
    expect(GRID.rows).toBe(13);
    expect(GRID.cols).toBe(11);
    expect(GRID.from).toBe(28);
  });
});

describe('Try it: arrow keys move one cell, never off the grid', () => {
  const g = { rows: 13, cols: 11 };
  it('moves with the arrows', () => {
    expect(gridMove({ r: 4, c: 4 }, 'ArrowRight', g)).toEqual({ r: 4, c: 5 });
    expect(gridMove({ r: 4, c: 4 }, 'ArrowLeft', g)).toEqual({ r: 4, c: 3 });
    expect(gridMove({ r: 4, c: 4 }, 'ArrowUp', g)).toEqual({ r: 3, c: 4 });
    expect(gridMove({ r: 4, c: 4 }, 'ArrowDown', g)).toEqual({ r: 5, c: 4 });
  });
  it('stops at the edges', () => {
    expect(gridMove({ r: 0, c: 0 }, 'ArrowUp', g)).toEqual({ r: 0, c: 0 });
    expect(gridMove({ r: 0, c: 0 }, 'ArrowLeft', g)).toEqual({ r: 0, c: 0 });
    expect(gridMove({ r: 12, c: 10 }, 'ArrowDown', g)).toEqual({ r: 12, c: 10 });
    expect(gridMove({ r: 12, c: 10 }, 'ArrowRight', g)).toEqual({ r: 12, c: 10 });
  });
  it('Home and End go to the row number and the last tree; with Ctrl, the corners', () => {
    expect(gridMove({ r: 5, c: 6 }, 'Home', g)).toEqual({ r: 5, c: 0 });
    expect(gridMove({ r: 5, c: 6 }, 'End', g)).toEqual({ r: 5, c: 10 });
    expect(gridMove({ r: 5, c: 6 }, 'Home', { ...g, ctrl: true })).toEqual({ r: 0, c: 0 });
    expect(gridMove({ r: 5, c: 6 }, 'End', { ...g, ctrl: true })).toEqual({ r: 12, c: 10 });
  });
  it('Page Up and Page Down jump a few rows', () => {
    expect(gridMove({ r: 6, c: 2 }, 'PageUp', g)).toEqual({ r: 2, c: 2 });
    expect(gridMove({ r: 1, c: 2 }, 'PageUp', g)).toEqual({ r: 0, c: 2 });
    expect(gridMove({ r: 10, c: 2 }, 'PageDown', g)).toEqual({ r: 12, c: 2 });
  });
  it('leaves every other key alone (Tab leaves the grid, Enter and Space act)', () => {
    for (const k of ['Tab', 'Enter', ' ', 'a', 'Escape']) expect(gridMove({ r: 1, c: 1 }, k, g)).toBeNull();
  });
});

describe('Try it: names for screen readers', () => {
  it('says each tree’s row, number and state, and its note', () => {
    expect(cellLabel(37, 4, EMPTY)).toBe('Row 37, tree 4: not yet');
    expect(cellLabel(30, 1, TODAY)).toBe('Row 30, tree 1: shaped today');
    expect(cellLabel(12, 9, EARLIER_S)).toBe('Row 12, tree 9: shaped earlier');
    expect(cellLabel(OLD_NOTE.row, OLD_NOTE.tree, TODAY, OLD_NOTE.flag)).toBe('Row 31, tree 4: shaped today. Note: Needs attention');
    expect(cellLabel(37, 2, EMPTY, null, true)).toBe('Row 37, tree 2: not yet. Fill starts here');
  });
  it('says what a row holds', () => {
    const t = createTryIt();
    expect(rowLabel(t, 30)).toBe('Row 30: shaped today');
    expect(rowLabel(t, 37)).toBe('Row 37: not yet');
    t.treeTap(37, 1, 'one');
    t.treeTap(37, 2, 'one');
    expect(rowLabel(t, 37)).toBe('Row 37: 2 of 10 shaped');
  });
});

describe('Try it: the today count follows your taps', () => {
  it('starts at the ledger’s 230 and moves ten for a row', () => {
    const t = createTryIt();
    const base = treesAt(MOMENTS.field);
    expect(todayCount(t, base)).toBe(base);
    t.rowTap(37);
    expect(todayCount(t, base)).toBe(base + 10);
    t.rowTap(30, 'erase');
    expect(todayCount(t, base)).toBe(base);
    t.undo();
    expect(todayCount(t, base)).toBe(base + 10);
    t.undo();
    expect(todayCount(t, base)).toBe(base);
    t.treeTap(38, 3, 'one');
    t.reset();
    expect(todayCount(t, base)).toBe(base);
  });
});
