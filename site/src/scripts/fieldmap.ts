/**
 * STUB (map): the field geometry and the canvas renderer for FieldMap.astro, TreesTab and
 * Try it. Keep the exported names; fill in the implementation (with unit tests).
 */
import { FIELD, FIELD_TREES } from '../data/ledger.ts';

/** The canvas's accessible summary, from the ledger (brief: FieldMap ACCESSIBILITY). */
export const FIELD_SUMMARY =
  'Map of North field: 14 blocks of 61 rows, 10 trees a row, 8,540 trees. Rows 14 to 36 of block 2 shaped today in gold. Block 1, blocks 8 and 9, and the first rows of blocks 2, 3 and 4 shaped earlier in green. The rest not yet shaped.';

export interface Dot {
  x: number;
  y: number;
  block: number;
  row: number;
  tree: number;
}

/** Dot positions in dot-pitch units: blocks 10 wide × 61 tall, 1.5-pitch gutters, 3 between grid rows. */
export function fieldLayout(): { width: number; height: number; dots: Dot[] } {
  const gutter = 1.5;
  const rowGap = 3;
  const dots: Dot[] = [];
  for (let b = 0; b < FIELD.blocks; b += 1) {
    const gx = b % FIELD.blocksPerGridRow;
    const gy = Math.floor(b / FIELD.blocksPerGridRow);
    const ox = gx * (FIELD.treesPerRow + gutter);
    const oy = gy * (FIELD.rowsPerBlock + rowGap);
    for (let r = 0; r < FIELD.rowsPerBlock; r += 1)
      for (let t = 0; t < FIELD.treesPerRow; t += 1) dots.push({ x: ox + t, y: oy + r, block: b + 1, row: r + 1, tree: t + 1 });
  }
  const width = FIELD.blocksPerGridRow * FIELD.treesPerRow + (FIELD.blocksPerGridRow - 1) * gutter;
  const height = FIELD.gridRows * FIELD.rowsPerBlock + (FIELD.gridRows - 1) * rowGap;
  if (dots.length !== FIELD_TREES) throw new Error('field layout does not add up');
  return { width, height, dots };
}

export interface FieldMapHandle {
  setProgress(p: number): void;
  destroy(): void;
}

/** STUB: draws nothing yet. */
export function createFieldMap(_canvas: HTMLCanvasElement): FieldMapHandle {
  return { setProgress() {}, destroy() {} };
}
