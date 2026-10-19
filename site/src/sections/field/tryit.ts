/**
 * TRY IT: the small working copy of block 2, rows 28–40 under the field section.
 *
 * The model is createTryIt() from src/scripts/fieldstate.ts (pure, unit-tested by the map
 * team). This file adds the pure helpers the strip needs (keyboard moves, names, the today
 * count; tested in tryit.test.ts) and initTryIt(), the vanilla DOM controller:
 *
 * - role="grid", 13 rows × (a row-number button + 10 tree buttons), one roving tabindex,
 *   so Tab reaches the grid once; arrows, Home/End (Ctrl for the corners) and Page Up/Down move;
 *   Enter or Space acts per mode (they are real buttons).
 * - One / Fill / Erase radios, Undo (aria-disabled when there is nothing to undo, so focus is
 *   never lost) and Reset.
 * - A polite status line says what changed ("Row 37 marked, 10 trees").
 * - Nothing is saved. Changes animate (150 ms, CSS) only under html.motion.
 *
 * No GSAP and no DOM work at import: Field.astro loads this module when the strip comes near.
 */
import { FIELD, MOMENTS, treesAt, type Flag } from '../../data/ledger.ts';
import { EARLIER_S, TODAY, ZOOM_TARGET, createTryIt, notesAt, type TapMode, type TreeState, type TryIt } from '../../scripts/fieldstate.ts';

const ACROSS = FIELD.treesPerRow;

/** The grid: rows 28–40, a row-number column plus one column per tree. */
export const GRID = {
  from: ZOOM_TARGET.from,
  to: ZOOM_TARGET.to,
  rows: ZOOM_TARGET.to - ZOOM_TARGET.from + 1,
  cols: ACROSS + 1,
} as const;

export interface Pos {
  r: number;
  c: number;
}

/** Page Up / Page Down move this many rows. */
const PAGE = 4;

/** Where a key moves focus in a rows × cols grid (no wrapping), or null when the key is not a move. */
export function gridMove(pos: Pos, key: string, g: { rows: number; cols: number; ctrl?: boolean }): Pos | null {
  const clampR = (r: number) => Math.max(0, Math.min(g.rows - 1, r));
  const clampC = (c: number) => Math.max(0, Math.min(g.cols - 1, c));
  switch (key) {
    case 'ArrowUp':
      return { r: clampR(pos.r - 1), c: pos.c };
    case 'ArrowDown':
      return { r: clampR(pos.r + 1), c: pos.c };
    case 'ArrowLeft':
      return { r: pos.r, c: clampC(pos.c - 1) };
    case 'ArrowRight':
      return { r: pos.r, c: clampC(pos.c + 1) };
    case 'Home':
      return g.ctrl ? { r: 0, c: 0 } : { r: pos.r, c: 0 };
    case 'End':
      return g.ctrl ? { r: g.rows - 1, c: g.cols - 1 } : { r: pos.r, c: g.cols - 1 };
    case 'PageUp':
      return { r: clampR(pos.r - PAGE), c: pos.c };
    case 'PageDown':
      return { r: clampR(pos.r + PAGE), c: pos.c };
    default:
      return null;
  }
}

const STATE_WORDS: Record<TreeState, string> = { 0: 'not yet', 1: 'shaped earlier', 2: 'shaped today' };
/** The data-s attribute the CSS paints: ring, earlier or today. */
export const STATE_ATTR: Record<TreeState, 'ring' | 'earlier' | 'today'> = { 0: 'ring', 1: 'earlier', 2: 'today' };

/** 'Row 31, tree 4: shaped today. Note: Replant' */
export function cellLabel(row: number, tree: number, s: TreeState, note?: Flag | null, anchor = false): string {
  return `Row ${row}, tree ${tree}: ${STATE_WORDS[s]}${note ? `. Note: ${note}` : ''}${anchor ? '. Fill starts here' : ''}`;
}

/** 'Row 37: not yet', 'Row 30: shaped today', 'Row 37: 2 of 10 shaped' */
export function rowLabel(t: TryIt, row: number): string {
  const states = Array.from({ length: ACROSS }, (_, i) => t.get(row, i + 1));
  const done = states.filter((s) => s !== 0).length;
  if (states.every((s) => s === TODAY)) return `Row ${row}: shaped today`;
  if (states.every((s) => s === EARLIER_S)) return `Row ${row}: shaped earlier`;
  if (done === 0) return `Row ${row}: not yet`;
  return `Row ${row}: ${done} of ${ACROSS} shaped`;
}

/** Tree notes inside the grid's rows at 2:16 PM (the older Replant note on row 31, tree 4). */
export const notesHere = () =>
  notesAt(MOMENTS.field).filter((n) => n.block === ZOOM_TARGET.block && n.row >= GRID.from && n.row <= GRID.to);

const goldIn = (t: TryIt) => {
  let n = 0;
  for (let row = GRID.from; row <= GRID.to; row += 1) for (let tree = 1; tree <= ACROSS; tree += 1) if (t.get(row, tree) === TODAY) n += 1;
  return n;
};
let startGold: number | null = null;

/** Your trees today with your Try it changes: the ledger's count, minus this copy's starting gold, plus its gold now. */
export function todayCount(t: TryIt, base: number = treesAt(MOMENTS.field)): number {
  startGold ??= goldIn(createTryIt());
  return base - startGold + goldIn(t);
}

// ---------------------------------------------------------------------------
// The DOM controller

const MODES: readonly TapMode[] = ['one', 'fill', 'erase'];

export function initTryIt(root: HTMLElement): () => void {
  if (root.dataset.ready) return () => {};
  root.dataset.ready = '';
  const grid = root.querySelector<HTMLElement>('[data-try-grid]');
  const status = root.querySelector<HTMLElement>('[data-try-status]');
  const today = root.querySelector<HTMLElement>('[data-try-today]');
  const undoBtn = root.querySelector<HTMLButtonElement>('[data-try-undo]');
  const resetBtn = root.querySelector<HTMLButtonElement>('[data-try-reset]');
  const radios = Array.from(root.querySelectorAll<HTMLInputElement>('input[data-try-mode]'));
  if (!grid) return () => {};

  const model = createTryIt();
  const base = treesAt(MOMENTS.field);
  const notes = new Map(notesHere().map((n) => [`${n.row}-${n.tree}`, n.flag] as const));
  let mode: TapMode = (radios.find((r) => r.checked)?.value as TapMode) ?? 'one';

  // cells[r][c]: c = 0 is the row number, 1–10 the trees.
  const cells: HTMLButtonElement[][] = [];
  for (let r = 0; r < GRID.rows; r += 1) {
    const row = GRID.from + r;
    const rowBtn = grid.querySelector<HTMLButtonElement>(`[data-try-row="${row}"]`);
    const line: HTMLButtonElement[] = rowBtn ? [rowBtn] : [];
    for (let tree = 1; tree <= ACROSS; tree += 1) {
      const b = grid.querySelector<HTMLButtonElement>(`[data-try-tree="${row}-${tree}"]`);
      if (b) line.push(b);
    }
    cells.push(line);
  }
  let pos: Pos = { r: 0, c: 0 };
  const posOf = (el: Element): Pos | null => {
    for (let r = 0; r < cells.length; r += 1) {
      const c = cells[r]!.indexOf(el as HTMLButtonElement);
      if (c >= 0) return { r, c };
    }
    return null;
  };
  const rove = (next: Pos, focus: boolean) => {
    cells[pos.r]?.[pos.c]?.setAttribute('tabindex', '-1');
    pos = next;
    const el = cells[pos.r]?.[pos.c];
    if (!el) return;
    el.setAttribute('tabindex', '0');
    if (focus) el.focus();
  };

  let said = '';
  const say = (msg: string) => {
    if (!status) return;
    // The same sentence twice in a row still gets announced.
    if (msg === said) status.textContent = '';
    said = msg;
    requestAnimationFrame(() => (status.textContent = msg));
  };

  const render = () => {
    const anchor = mode === 'fill' ? model.anchor : null;
    for (let r = 0; r < GRID.rows; r += 1) {
      const row = GRID.from + r;
      const line = cells[r]!;
      line[0]?.setAttribute('aria-label', rowLabel(model, row));
      for (let tree = 1; tree <= ACROSS; tree += 1) {
        const b = line[tree];
        if (!b) continue;
        const s = model.get(row, tree);
        const isAnchor = !!anchor && anchor.row === row && anchor.tree === tree;
        if (b.dataset.s !== STATE_ATTR[s]) b.dataset.s = STATE_ATTR[s];
        b.toggleAttribute('data-anchor', isAnchor);
        b.setAttribute('aria-label', cellLabel(row, tree, s, notes.get(`${row}-${tree}`), isAnchor));
        if (s === EARLIER_S) b.setAttribute('aria-disabled', 'true');
        else b.removeAttribute('aria-disabled');
      }
    }
    undoBtn?.setAttribute('aria-disabled', String(!model.canUndo));
    if (today) today.textContent = todayCount(model, base).toLocaleString('en-US');
    root.dataset.mode = mode;
  };

  const act = (fn: () => string, kind: 'row' | 'tree' | 'other') => {
    grid.dataset.last = kind;
    // The gold "next row" hint has done its job once anything is tapped.
    grid.querySelector('[data-next]')?.removeAttribute('data-next');
    say(fn());
    render();
  };

  const onClick = (e: MouseEvent) => {
    const b = (e.target as Element).closest<HTMLButtonElement>('button');
    if (!b || !grid.contains(b)) return;
    const p = posOf(b);
    if (p) rove(p, false);
    const row = Number(b.dataset.tryRow);
    if (row) return act(() => model.rowTap(row, mode), 'row');
    const [r, t] = (b.dataset.tryTree ?? '').split('-').map(Number);
    if (r && t) act(() => model.treeTap(r, t, mode), 'tree');
  };

  const onKey = (e: KeyboardEvent) => {
    if (e.altKey || e.metaKey) return;
    const from = posOf(e.target as Element);
    if (!from) return;
    const next = gridMove(from, e.key, { rows: GRID.rows, cols: GRID.cols, ctrl: e.ctrlKey });
    if (!next) return;
    e.preventDefault();
    pos = from;
    rove(next, true);
  };

  // Clicking a cell with the mouse moves the roving stop there too.
  const onFocusIn = (e: FocusEvent) => {
    const p = posOf(e.target as Element);
    if (p && (p.r !== pos.r || p.c !== pos.c)) rove(p, false);
  };

  const onMode = () => {
    const picked = radios.find((r) => r.checked)?.value as TapMode | undefined;
    if (!picked || !MODES.includes(picked)) return;
    mode = picked;
    render();
    say(mode === 'fill' ? 'Fill: tap the first tree, then the last' : mode === 'erase' ? 'Erase: tap a tree or a row number to clear it' : 'One: tap a tree to mark or unmark it');
  };

  const onUndo = () => {
    if (!model.canUndo) return say('Nothing to undo');
    act(() => model.undo(), 'other');
  };
  const onReset = () => act(() => model.reset(), 'other');

  grid.addEventListener('click', onClick);
  grid.addEventListener('keydown', onKey);
  grid.addEventListener('focusin', onFocusIn);
  radios.forEach((r) => r.addEventListener('change', onMode));
  undoBtn?.addEventListener('click', onUndo);
  resetBtn?.addEventListener('click', onReset);

  // Exactly one tab stop in the grid: the first row number.
  cells.flat().forEach((b) => b.setAttribute('tabindex', '-1'));
  rove({ r: 0, c: 0 }, false);
  render();

  // The next row's pill pulses once (CSS, motion only) when most of the grid is in view.
  const cue =
    'IntersectionObserver' in window
      ? new IntersectionObserver(
          (entries) => {
            if (!entries.some((e) => e.isIntersecting)) return;
            root.dataset.cue = '';
            cue?.disconnect();
          },
          { threshold: 0.6 },
        )
      : null;
  cue?.observe(grid);

  return () => {
    cue?.disconnect();
    grid.removeEventListener('click', onClick);
    grid.removeEventListener('keydown', onKey);
    grid.removeEventListener('focusin', onFocusIn);
    radios.forEach((r) => r.removeEventListener('change', onMode));
    undoBtn?.removeEventListener('click', onUndo);
    resetBtn?.removeEventListener('click', onReset);
    delete root.dataset.ready;
  };
}
