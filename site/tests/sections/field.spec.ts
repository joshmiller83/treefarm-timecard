/**
 * The field section (#field): present and composed with and without motion, its labels come
 * from the ledger, the scene plays through with no errors and no sideways overflow, and Try it
 * works by keyboard with a live status. Runs against the built site, like tests/e2e.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { FIELD_TREES, MOMENTS, fmtCount, treesAt } from '../../src/data/ledger';
import { fieldSummary, zoomSummary } from '../../src/scripts/fieldstate';
import { COUNTS, stripText } from '../../src/sections/field/plan';
import { settle, watch } from '../e2e/helpers';

const overflow = () => document.documentElement.scrollWidth - document.documentElement.clientWidth;

/** The field track's scroll range: [top, top + height − viewport]. */
const trackRange = (page: Page) =>
  page.evaluate(() => {
    const t = document.querySelector<HTMLElement>('#field .track')!;
    const top = t.getBoundingClientRect().top + scrollY;
    return [top, top + t.offsetHeight - innerHeight] as const;
  });

/** Scrolls to section progress p and lets the scrub (0.6 s) catch up. */
async function goTo(page: Page, p: number) {
  const [a, b] = await trackRange(page);
  await page.evaluate((y) => window.scrollTo(0, y), Math.round(a + p * (b - a)));
  await page.waitForTimeout(1100);
}

/**
 * Scrolls to p and polls until the scene shows what `ready` expects there. Every try measures the
 * track again and arrives with a small scroll, as a reader would: on a busy machine a
 * ScrollTrigger.refresh() can land mid-scrub after a jump (fonts, content-visibility of the
 * sections above) and leave the timeline short of the trigger until the next scroll event.
 */
async function goUntil(page: Page, p: number, ready: (g: Geometry) => boolean) {
  let last: Geometry | null = null;
  await expect
    .poll(
      async () => {
        const [a, b] = await trackRange(page);
        const y = Math.round(a + p * (b - a));
        await page.evaluate((y) => window.scrollTo(0, y - 3), y);
        await page.waitForTimeout(50);
        await page.evaluate((y) => window.scrollTo(0, y), y);
        await page.waitForTimeout(900);
        last = await geometry(page);
        return ready(last);
      },
      { timeout: 30_000, intervals: [200, 500, 1000], message: `the scene at ${p}` },
    )
    .toBe(true)
    .catch((e: Error) => {
      throw new Error(`${e.message}\nlast geometry: ${JSON.stringify(last)}`);
    });
  return geometry(page);
}

type Box = { top: number; bottom: number; left: number; right: number; opacity: number };
type Pt = { x: number; y: number };

/** Where things are now: the overview canvas's camera and rows, the cards, the chip, the strip and the Undo chip. */
const geometry = (page: Page) =>
  page.evaluate(() => {
    const c = document.querySelector<HTMLCanvasElement>('#field [data-field-fig] canvas[data-fieldmap]')!;
    type Handle = { orientation: string; state: { camera: number }; pointAt(b: number, r: number, t: number): { x: number; y: number } };
    const m = (c as HTMLCanvasElement & { fieldMap: Handle }).fieldMap;
    const r = c.getBoundingClientRect();
    const pt = (block: number, row: number, tree: number) => {
      const p = m.pointAt(block, row, tree);
      return { x: r.left + p.x, y: r.top + p.y };
    };
    const box = (sel: string) => {
      const e = document.querySelector<HTMLElement>(sel)!;
      const b = e.getBoundingClientRect();
      return { top: b.top, bottom: b.bottom, left: b.left, right: b.right, opacity: Number(getComputedStyle(e).opacity) };
    };
    return {
      orientation: m.orientation,
      camera: m.state.camera,
      canvasWidth: r.width,
      /** The overview's first and last trees across (block 1 tree 1, block 7 tree 10). */
      across: [pt(1, 1, 1), pt(7, 1, 10)] as [Pt, Pt],
      row28: pt(2, 28, 10),
      row40: pt(2, 40, 10),
      card2: box('[data-field-card="2"]'),
      card3: box('[data-field-card="3"]'),
      chip: box('[data-field-season]'),
      strip: box('#field [data-field-counts]'),
      undo: box('[data-field-undo]'),
      toast: !!document.querySelector('#field [data-field-fig][data-toast]'),
      /** The camera box's width at rest (the canvas's, before the tilt's scale). */
      restWidth: c.offsetWidth,
      motion: document.documentElement.className,
    };
  });
type Geometry = Awaited<ReturnType<typeof geometry>>;

async function serious(page: Page) {
  const results = await new AxeBuilder({ page })
    .include('#field')
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
    .analyze();
  return results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
}

test.describe('with motion', () => {
  test('the scene plays through the track with no console errors and ends at rest', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await expect(page.locator('html')).toHaveClass(/(^|\s)motion(\s|$)/);
    const section = page.locator('section#field');
    await expect(section).toHaveAttribute('aria-labelledby', 'field-h');
    await expect(page.getByRole('heading', { level: 2, name: 'Every tree is a dot.' })).toBeAttached();

    // The overview canvas is one image whose label is the ledger's summary.
    const canvas = page.locator('#field [data-field-fig] canvas[data-fieldmap]');
    await expect(canvas).toHaveAttribute('role', 'img');
    await expect(canvas).toHaveAttribute('aria-label', fieldSummary(MOMENTS.field));

    // Step through the track; the canvas follows the choreography.
    await goTo(page, 0.42);
    await expect(page.locator('[data-field-card="1"]')).toBeVisible();
    await goTo(page, 0.6);
    const cam = await canvas.evaluate((c) => (c as HTMLCanvasElement & { fieldMap?: { state: { camera: number } } }).fieldMap?.state.camera ?? -1);
    expect(cam).toBeGreaterThan(0.95);
    await expect(page.locator('[data-field-card="2"]')).toBeVisible();
    await goTo(page, 0.84);
    await expect(page.locator('[data-field-card="3"]')).toBeVisible();
    await goTo(page, 1);

    // The counter strip ends on the ledger: 8,540 trees · 2,420 shaped · 230 today.
    for (const [k, v] of Object.entries({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: treesAt(MOMENTS.field) }))
      await expect(page.locator(`[data-field-count="${k}"]`)).toHaveAttribute('data-odo-text', fmtCount(v));
    await expect(page.locator('#field [data-field-counts] .sr-only')).toHaveText(stripText(COUNTS));
    expect(problems).toEqual([]);
  });

  test('the DayClock holds at 2:16 PM, the minute in the eyebrow and the tag', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    await goTo(page, 0.5);
    await expect(page.locator('[data-shift-tag]').first()).toHaveText('2:16 PM · The field');
    await expect(page.locator('#field .eyebrow')).toContainText('2:16 PM');
  });

  test('the heading never runs under the header: its lines are masked before the field’s content', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    for (const p of [0, 0.05, 0.1, 0.15]) {
      await goTo(page, p);
      const g = await page.evaluate(() => {
        const head = document.querySelector<HTMLElement>('#field .beat-head')!;
        const frame = document.querySelector<HTMLElement>('#field .frame')!;
        const fig = document.querySelector<HTMLElement>('#field [data-field-fig]')!;
        let y = parseFloat(getComputedStyle(frame).top) || 0;
        for (let e: HTMLElement | null = fig; e && e !== frame; e = e.offsetParent as HTMLElement | null) y += e.offsetTop;
        if (innerWidth >= 900) y += document.querySelector<HTMLElement>('#field .fm-top')!.offsetHeight;
        return { top: head.getBoundingClientRect().top, cut: parseFloat(head.style.getPropertyValue('--cut')) || 0, line: y };
      });
      // Everything of the heading above the line is inside the mask's clear part (cut − 64px).
      if (g.top < g.line) expect(g.top + g.cut - 64, `at ${p}`).toBeGreaterThanOrEqual(g.line - 1);
    }
  });

  test('the Undo chip sits beside row 37 on a wide canvas, or as a toast in the legend’s place', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    const g = await goUntil(page, 0.655, (x) => x.camera === 1 && x.undo.opacity > 0.5);
    if (g.toast) {
      await expect(page.locator('#field .fm-foot [data-field-undo]')).toHaveCount(1);
      expect(g.undo.top).toBeGreaterThanOrEqual(g.card2.bottom - 1);
    } else {
      expect(g.undo.left).toBeGreaterThan(g.row40.x);
      expect(Math.abs((g.undo.top + g.undo.bottom) / 2 - (g.row28.y + (g.row40.y - g.row28.y) * (9 / 12)))).toBeLessThan(12);
    }
  });

  test('no horizontal overflow anywhere in the track', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    for (let i = 0; i <= 10; i += 1) {
      await goTo(page, i / 10);
      expect(await page.evaluate(overflow), `at ${i * 10}%`).toBeLessThanOrEqual(0);
    }
  });

  test('axe: no serious or critical violations in the section', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    await goTo(page, 0.5);
    expect(await serious(page)).toEqual([]);
  });
});

// Real iPhone Safari heights (100svh with the toolbars showing), not just 812.
for (const [width, height] of [
  [375, 667],
  [390, 664],
  [393, 759],
  [430, 746],
] as const) {
  test.describe(`phone at ${width}×${height}`, () => {
    test.use({ viewport: { width, height } });
    test.skip(({ isMobile }) => !isMobile, 'phone layout');

    test('the overview is upright and wide, and the close-up clears the cards and the strip', async ({ page }) => {
      const { problems } = watch(page);
      await page.goto('/');
      await settle(page);

      let g = await goUntil(page, 0.45, (x) => x.camera === 0 && Math.abs(x.canvasWidth - x.restWidth) < 1);
      expect(g.orientation).toBe('portrait');
      // Portrait: block 7 is to the right of block 1 on the same row, and the field spans most of the width.
      expect(Math.abs(g.across[1].y - g.across[0].y)).toBeLessThan(1);
      expect(g.across[1].x - g.across[0].x).toBeGreaterThan(0.75 * g.canvasWidth);

      // The demo: rows 28–40 sit between the strip and card 2.
      g = await goUntil(page, 0.62, (x) => x.camera === 1 && x.card2.opacity > 0.99);
      expect(g.row40.y + 9).toBeLessThanOrEqual(g.card2.top);
      expect(g.row28.y - 9).toBeGreaterThanOrEqual(g.strip.bottom);

      // The season flip: the rows clear card 3, and the chip sits between the strip and row 28.
      g = await goUntil(page, 0.8, (x) => x.card3.opacity > 0.99 && x.chip.opacity > 0.99);
      expect(g.row40.y + 9).toBeLessThanOrEqual(g.card3.top);
      expect(g.chip.top).toBeGreaterThanOrEqual(g.strip.bottom - 1);
      expect(g.chip.bottom).toBeLessThanOrEqual(g.row28.y - 9);
      expect(problems).toEqual([]);
    });
  });
}

test.describe('at 320px', () => {
  test.use({ viewport: { width: 320, height: 640 } });

  test('no horizontal overflow, with motion, through the track', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    for (let i = 0; i <= 8; i += 1) {
      await goTo(page, i / 8);
      expect(await page.evaluate(overflow), `at ${Math.round((i / 8) * 100)}%`).toBeLessThanOrEqual(0);
    }
  });

  test('no horizontal overflow without motion', async ({ page }) => {
    await page.goto('/?motion=off');
    await page.locator('[data-tryit]').scrollIntoViewIfNeeded();
    expect(await page.evaluate(overflow)).toBeLessThanOrEqual(0);
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('a complete static section: both maps, the strip, the legend, the three points', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    await page.locator('#field-h').scrollIntoViewIfNeeded();
    await expect(page.locator('#field-h')).toHaveText('Every tree is a dot.');

    const maps = page.locator('#field canvas[data-fieldmap][role="img"]');
    await expect(maps).toHaveCount(2);
    await expect(maps.nth(0)).toHaveAttribute('aria-label', fieldSummary(MOMENTS.field));
    await expect(maps.nth(1)).toHaveAttribute('aria-label', zoomSummary());
    for (const fig of ['[data-field-fig]', '.fm-zoomfig', '.fm-shot']) {
      const f = page.locator(`#field ${fig}`);
      await f.scrollIntoViewIfNeeded();
      await expect(f).toBeVisible();
      await expect(f.locator('figcaption')).toBeVisible();
    }
    await expect(page.locator('#field [data-field-counts]')).toContainText('8,540');
    await expect(page.getByRole('list', { name: 'Map key' })).toBeVisible();
    for (const t of ['Today', 'Shaped earlier', 'Not yet', 'Note']) await expect(page.getByRole('list', { name: 'Map key' })).toContainText(t);
    // The three points are plain, fully visible text.
    const cards = page.locator('#field [data-field-card]');
    await expect(cards).toHaveCount(3);
    for (let i = 0; i < 3; i += 1) {
      await expect(cards.nth(i)).toBeVisible();
      expect(Number(await cards.nth(i).evaluate((e) => getComputedStyle(e).opacity))).toBe(1);
    }
    await expect(cards.nth(2)).toContainText('Notes stay with the tree.');
    // The phone is one image with a label from the ledger.
    await expect(page.locator('#field .fm-shot [data-phone][role="img"]')).toHaveAttribute('aria-label', /Trees tab at 2:16 PM/);
    expect(problems).toEqual([]);
  });

  test('axe: no serious or critical violations on the static section', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    expect(await serious(page)).toEqual([]);
  });

  test('no horizontal overflow', async ({ page }) => {
    await page.goto('/');
    expect(await page.evaluate(overflow)).toBeLessThanOrEqual(0);
  });
});

test.describe('Try it', () => {
  test.use({ reducedMotion: 'reduce' });

  test('Tab reaches the grid once, arrows move, Enter acts, and the status says what changed', async ({ page }) => {
    await page.goto('/');
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    const grid = page.getByRole('grid', { name: 'Block 2, rows 28 to 40' });
    await grid.scrollIntoViewIfNeeded();
    await expect(page.locator('[data-tryit][data-ready]')).toBeAttached();
    await expect(page.getByRole('heading', { level: 3, name: 'Try it. Tap a row number.' })).toBeVisible();
    await expect(page.getByText('This is a small copy of the map. Nothing you do here is saved.')).toBeVisible();

    // One tab stop in the grid. The next row (37) wears the gold hint until the first tap.
    await expect(grid.locator('button[tabindex="0"]')).toHaveCount(1);
    await expect(grid.locator('[data-next]')).toHaveAttribute('data-try-row', '37');
    const status = page.locator('[data-try-status]');
    await expect(status).toHaveAttribute('role', 'status');
    const today = page.locator('[data-try-today]');
    await expect(today).toHaveText(fmtCount(treesAt(MOMENTS.field)));

    // Focus the reset button, then Shift+Tab back past the controls into the grid's single stop.
    await page.getByRole('button', { name: 'Reset' }).focus();
    await page.keyboard.press('Tab');
    await expect(page.locator(':focus')).toHaveAttribute('data-try-row', '28');
    await page.keyboard.press('Tab');
    expect(await page.evaluate(() => !!document.activeElement?.closest('[data-try-grid]'))).toBe(false);

    // Back into the grid: move down to row 37's number and mark the row.
    await page.keyboard.press('Shift+Tab');
    await expect(page.locator(':focus')).toHaveAttribute('data-try-row', '28');
    for (let i = 0; i < 9; i += 1) await page.keyboard.press('ArrowDown');
    await expect(page.locator(':focus')).toHaveAttribute('data-try-row', '37');
    await expect(page.locator(':focus')).toHaveAccessibleName('Row 37: not yet');
    await page.keyboard.press('Enter');
    await expect(status).toHaveText('Row 37 marked, 10 trees');
    await expect(grid.locator('[data-next]')).toHaveCount(0);
    await expect(today).toHaveText(fmtCount(treesAt(MOMENTS.field) + 10));
    await expect(grid.locator('[data-try-tree="37-1"]')).toHaveAttribute('data-s', 'today');
    await expect(page.locator(':focus')).toHaveAccessibleName('Row 37: shaped today');

    // Arrow right onto a tree and toggle it with Space (One mode).
    await page.keyboard.press('ArrowRight');
    await expect(page.locator(':focus')).toHaveAccessibleName('Row 37, tree 1: shaped today');
    await page.keyboard.press(' ');
    await expect(status).toHaveText('Row 37, tree 1 unmarked');

    // Undo is one tap; Reset goes back to the ledger.
    await page.getByRole('button', { name: 'Undo' }).click();
    await expect(status).toHaveText('Undid your last change');
    await expect(grid.locator('[data-try-tree="37-1"]')).toHaveAttribute('data-s', 'today');
    await page.getByRole('button', { name: 'Reset' }).click();
    await expect(status).toHaveText('Back to the map at 2:16 PM');
    await expect(grid.locator('[data-try-tree="37-1"]')).toHaveAttribute('data-s', 'ring');
    await expect(page.getByRole('button', { name: 'Undo' })).toHaveAttribute('aria-disabled', 'true');
  });

  test('every tree and row number is at least a 30px target, down to a 375px phone', async ({ page }) => {
    await page.goto('/');
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    const grid = page.getByRole('grid', { name: 'Block 2, rows 28 to 40' });
    await grid.scrollIntoViewIfNeeded();
    const sizes = await grid.evaluate((g) =>
      [g.querySelector('[data-try-tree="28-1"]')!, g.querySelector('[data-try-row="28"]')!].map((e) => e.getBoundingClientRect()),
    );
    for (const r of sizes) {
      expect(r.width).toBeGreaterThanOrEqual(30);
      expect(r.height).toBeGreaterThanOrEqual(30);
    }
  });

  test('Fill anchors on the first tap and fills to the second; Erase clears', async ({ page }) => {
    await page.goto('/');
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    const grid = page.getByRole('grid', { name: 'Block 2, rows 28 to 40' });
    await grid.scrollIntoViewIfNeeded();
    await expect(page.locator('[data-tryit][data-ready]')).toBeAttached();
    const status = page.locator('[data-try-status]');

    await page.getByRole('radio', { name: 'Fill' }).check();
    await grid.locator('[data-try-tree="38-2"]').click();
    await expect(status).toHaveText('Row 38, tree 2. Now tap the last tree');
    await expect(grid.locator('[data-try-tree="38-2"]')).toHaveAttribute('data-anchor', '');
    await grid.locator('[data-try-tree="38-6"]').click();
    await expect(status).toHaveText('Marked 5 trees, from row 38, tree 2 to row 38, tree 6');

    await page.getByRole('radio', { name: 'Erase' }).check();
    await grid.locator('[data-try-row="38"]').click();
    await expect(status).toHaveText('Row 38 cleared, 5 trees');
    await expect(grid.locator('[data-try-tree="38-4"]')).toHaveAttribute('data-s', 'ring');
  });
});
