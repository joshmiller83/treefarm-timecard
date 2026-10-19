/**
 * The map lab (/lab/map/): every Trees tab state follows the ledger, the field canvas draws
 * (and draws fast), the static fallbacks hold up, and the page is accessible at 375 and 1440.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';
import { CONFLICT_MESSAGE } from '../../src/data/ledger';
import { watch } from '../e2e/helpers';

const URL = '/lab/map/';

const state = (page: Page, id: string) => page.locator(`[data-lab-state="${id}"]`);
const rowStates = (scope: Locator, block: number, row: number) =>
  scope.locator(`[data-block-row="${block}-${row}"] [data-tree]`).evaluateAll((els) => els.map((e) => e.getAttribute('data-s')));
const all = (v: string) => Array(10).fill(v);

/** Waits for a FieldMap canvas's first frame, then counts its pixels by colour. */
async function canvasPixels(canvas: Locator) {
  await expect(canvas.locator('xpath=..')).toHaveAttribute('data-ready', '');
  return canvas.evaluate((el: HTMLCanvasElement) => {
    const g = el.getContext('2d');
    if (!g) return { gold: 0, green: 0, any: 0 };
    const d = g.getImageData(0, 0, el.width, el.height).data;
    let gold = 0;
    let green = 0;
    let any = 0;
    for (let i = 0; i < d.length; i += 4) {
      const [r, gr, b, a] = [d[i]!, d[i + 1]!, d[i + 2]!, d[i + 3]!];
      if (a < 200) continue;
      any += 1;
      if (r > 200 && gr > 140 && gr < 190 && b < 110) gold += 1;
      if (r < 70 && gr > 100 && gr < 140 && b > 60 && b < 100) green += 1;
    }
    return { gold, green, any };
  });
}

test('renders every state with no console errors', async ({ page }) => {
  const { problems } = watch(page);
  await page.goto(URL);
  const ids = await page.locator('[data-lab-state]').evaluateAll((els) => els.map((e) => e.getAttribute('data-lab-state')));
  expect(ids).toEqual([
    'trees-1416-block2',
    'trees-1433-note',
    'trees-1433-markers',
    'trees-1447-block3',
    'trees-1456-offline',
    'trees-1500-synced',
    'sam-1449-trees',
  ]);
  for (const id of ids) {
    const s = state(page, id!);
    await expect(s.locator('[data-map]')).toHaveCount(1);
    expect(await s.locator('[data-tree]').count()).toBeGreaterThan(150);
    await expect(s.locator('[data-phone][role="img"]')).toHaveAttribute('aria-label', /.{20,}/);
  }
  for (const z of ['All', 'XS', 'S', 'M']) await expect(page.locator(`[data-lab-zoom="${z}"] [data-map][data-zoom="${z}"]`)).toHaveCount(1);
  // Let the lazy canvases boot before judging the console.
  await page.locator('canvas[data-fieldmap]').last().scrollIntoViewIfNeeded();
  await expect(page.locator('[data-fieldmap-box][data-ready]').first()).toBeAttached();
  expect(problems).toEqual([]);
});

test('2:16 PM, block 2: gold rows 14–36, row 37 next, the old note on row 31', async ({ page }) => {
  await page.goto(URL);
  const s = state(page, 'trees-1416-block2');
  expect(await rowStates(s, 2, 36)).toEqual(all('today'));
  expect(await rowStates(s, 2, 28)).toEqual(all('today'));
  expect(await rowStates(s, 2, 37)).toEqual(all('ring'));
  await expect(s.locator('[data-map-row="37"] [data-tree]')).toHaveCount(10);
  await expect(s.locator('[data-tree="2-37-4"]')).toHaveCount(1);
  await expect(s.locator('[data-row-label="37"]')).toHaveText('37');
  await expect(s.locator('[data-row-label="37"]')).toHaveClass(/tm-cur/);
  await expect(s.locator('[data-note-marker="2-31-4"]')).toHaveCount(1);
  await expect(s.locator('[data-note-marker="2-36-7"]')).toHaveCount(0);
  await expect(s.locator('[data-zoom-chip="L"]')).toHaveClass(/is-on/);
  await expect(s.locator('[data-mode="one"] [data-mode-option="one"]')).toHaveClass(/is-on/);
  await expect(s.locator('[data-undo-btn]')).toHaveText(/Undo/);
  await expect(s.locator('[data-legend]')).toHaveText(/Today\s*Earlier\s*Not yet\s*Note/);
  await expect(s.locator('[data-field-picker]')).toHaveText('North field');
  await expect(s.locator('[data-tab="trees"]')).toHaveClass(/is-active/);
  await expect(s.locator('[data-clock]').first()).toHaveText('2:16');
  // A gold dot really is gold, and the ring really is a ring.
  const colours = await s.locator('[data-tree="2-36-1"], [data-tree="2-37-1"]').evaluateAll((els) =>
    els.map((e) => [getComputedStyle(e, '::after').opacity, getComputedStyle(e, '::after').backgroundColor]),
  );
  expect(colours).toEqual([
    ['1', 'rgb(181, 122, 18)'],
    ['0', 'rgb(181, 122, 18)'],
  ]);
});

test('notes: both flags, and the sheet scrolls row 36 into view with tree 7 selected', async ({ page }) => {
  await page.goto(URL);
  const s = state(page, 'trees-1433-note');
  await expect(s.locator('[data-note-marker="2-36-7"]')).toHaveAttribute('data-flag', 'Needs attention');
  await expect(s.locator('[data-tree="2-36-7"]')).toHaveAttribute('data-selected', '');
  await expect(s.locator('[data-sheet]')).toHaveCount(1);
  // [data-sheet] is the slide wrapper (it holds 40 pt of room for the shadow); its first child is the visible sheet.
  const [row, sheet] = await Promise.all([s.locator('[data-tree="2-36-7"]').boundingBox(), s.locator('[data-sheet] > :first-child').boundingBox()]);
  expect(row!.y + row!.height).toBeLessThan(sheet!.y);
  const m = state(page, 'trees-1433-markers');
  await expect(m.locator('[data-note-marker]')).toHaveCount(2);
});

test('crew: offline marks, first mark wins after sync, and Sam’s own phone', async ({ page }) => {
  await page.goto(URL);
  const before = state(page, 'trees-1447-block3');
  expect(await rowStates(before, 3, 10)).toEqual(all('earlier'));
  expect(await rowStates(before, 3, 12)).toEqual(all('ring'));

  const off = state(page, 'trees-1456-offline');
  await expect(off.locator('[data-sync-line]')).toHaveAttribute('data-sync', 'offline');
  // Read the odometer as its value (its digit columns hold 0–9).
  const line = await off.locator('[data-sync-line]').evaluate((el) => {
    const c = el.cloneNode(true) as HTMLElement;
    c.querySelectorAll<HTMLElement>('[data-odo]').forEach((o) => (o.textContent = o.dataset.odoText ?? ''));
    return (c.textContent ?? '').replace(/\s+/g, ' ').trim();
  });
  expect(line).toBe('Offline · 2 changes waiting');
  await expect(off.locator('[data-sync-count]')).toHaveAttribute('data-odo-text', '2');
  await expect(off.locator('[data-no-service]')).toHaveCount(1);
  expect(await rowStates(off, 3, 11)).toEqual(all('today'));
  expect(await rowStates(off, 3, 12)).toEqual(all('today'));

  const synced = state(page, 'trees-1500-synced');
  await expect(synced.locator('[data-sync-line]')).toHaveText('Synced');
  await expect(synced.locator('[data-banner]')).toHaveText(CONFLICT_MESSAGE);
  expect(await rowStates(synced, 3, 11)).toEqual(all('today'));
  expect(await rowStates(synced, 3, 12)).toEqual(all('earlier'));

  const sam = state(page, 'sam-1449-trees');
  await expect(sam.locator('[data-map]')).toHaveAttribute('data-who', 'Sam');
  expect(await rowStates(sam, 3, 12)).toEqual(all('today'));
  expect(await rowStates(sam, 3, 11)).toEqual(all('ring'));
  await expect(sam.locator('[data-tab="team"]')).toHaveCount(0);
});

test('crew states share one map geometry, and the banner is a toast clear of the bars', async ({ page }) => {
  await page.goto(URL);
  const ys = [];
  for (const id of ['trees-1447-block3', 'trees-1456-offline', 'trees-1500-synced']) {
    const s = state(page, id);
    await s.scrollIntoViewIfNeeded();
    const screen = (await s.locator('.screen').boundingBox())!;
    const dot = (await s.locator('[data-tree="3-6-1"]').boundingBox())!;
    ys.push(Math.round((dot.y - screen.y) * 10) / 10);
  }
  expect(new Set(ys).size).toBe(1);
  await expect(state(page, 'trees-1447-block3').locator('[data-sync-line]')).toBeHidden();
  const synced = state(page, 'trees-1500-synced');
  const [banner, legend, undo, more] = await Promise.all([
    synced.locator('[data-banner]').boundingBox(),
    synced.locator('[data-legend]').boundingBox(),
    synced.locator('[data-undo-btn]').boundingBox(),
    synced.locator('[data-tool="more"]').boundingBox(),
  ]);
  expect(banner!.y + banner!.height).toBeLessThan(legend!.y);
  expect(banner!.y).toBeGreaterThan(undo!.y + undo!.height);
  if (more) expect(banner!.y).toBeGreaterThan(more.y + more.height);
});

test('a note badge sits mostly inside its own row', async ({ page }) => {
  await page.goto(URL);
  for (const scope of ['[data-lab-state="trees-1416-block2"]', '[data-lab-zoom="XS"]', '[data-lab-zoom="S"]', '[data-lab-zoom="M"]']) {
    const row = page.locator(`${scope} [data-block-row="2-31"]`);
    await row.scrollIntoViewIfNeeded();
    const [r, b] = await Promise.all([row.boundingBox(), page.locator(`${scope} [data-note-marker="2-31-4"]`).boundingBox()]);
    const inside = Math.min(r!.y + r!.height, b!.y + b!.height) - Math.max(r!.y, b!.y);
    expect(inside / b!.height, scope).toBeGreaterThanOrEqual(0.6);
  }
});

test('one block fills the screen at L and stays inside it', async ({ page }) => {
  await page.goto(URL);
  const s = state(page, 'trees-1416-block2');
  const screen = await s.locator('.screen').boundingBox();
  const dots = await s.locator('[data-map-row="30"] [data-tree]').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().right));
  for (const right of dots) expect(right).toBeLessThan(screen!.x + screen!.width);
  const first = await s.locator('[data-tree="2-30-1"]').boundingBox();
  const label = await s.locator('[data-row-label="30"]').boundingBox();
  expect(label!.x + label!.width).toBeLessThanOrEqual(first!.x + 1);
});

test('the field canvas draws the 2:16 state with the ledger summary as its label', async ({ page }) => {
  await page.goto(URL);
  const canvas = page.locator('.lab-map canvas[data-fieldmap]');
  await canvas.scrollIntoViewIfNeeded();
  await expect(canvas).toHaveAttribute('role', 'img');
  await expect(canvas).toHaveAttribute(
    'aria-label',
    'Map of North field: 14 blocks of 61 rows, 10 trees a row, 8,540 trees. Rows 14 to 36 of block 2 shaped today in gold. Block 1, blocks 8 and 9, and the first rows of blocks 2, 3 and 4 shaped earlier in green. The rest not yet shaped.',
  );
  const px = await canvasPixels(canvas);
  expect(px.gold).toBeGreaterThan(500);
  expect(px.green).toBeGreaterThan(px.gold);
  // Once drawn, the SVG first paint steps aside.
  await expect(page.locator('.lab-map .fm-svg').first()).toBeHidden();
  const zoom = page.locator('canvas[data-fieldmap][data-view="zoom"]');
  await expect(zoom).toHaveAttribute('aria-label', /Rows 28 to 36 shaped today in gold, rows 37 to 40 not yet shaped/);
});

test('the scrubber plays the scene: zoomed demo, then next season’s rings', async ({ page }) => {
  await page.goto(URL);
  const input = page.locator('#scrub');
  const canvas = page.locator('.scrub-map canvas[data-fieldmap]');
  await canvas.scrollIntoViewIfNeeded();
  const read = () => canvas.evaluate((el) => (el as HTMLCanvasElement & { fieldMap: { state: Record<string, number> } }).fieldMap.state);
  await input.fill('0.65');
  await expect.poll(async () => (await read()).demo).toBe(1);
  expect((await read()).camera).toBe(1);
  await input.fill('0.85');
  await expect.poll(async () => (await read()).season).toBe(1);
  await page.waitForTimeout(250);
  const px = await canvasPixels(canvas);
  expect(px.gold).toBe(0);
  expect(px.any).toBeGreaterThan(0);
  await input.fill('1');
  await expect.poll(async () => (await read()).camera).toBe(0);
});

type Handle = {
  setProgress(p: number): void;
  draw(s: Record<string, number>): void;
  render(): void;
  pointAt(b: number, r: number, t: number): { x: number; y: number };
  frames: number;
  state: Record<string, number>;
};

test('the close-up is upright with the target lit and the rest dimmed', async ({ page }) => {
  await page.goto(URL);
  const canvas = page.locator('.scrub-map canvas[data-fieldmap]');
  await canvas.scrollIntoViewIfNeeded();
  await expect(canvas.locator('xpath=..')).toHaveAttribute('data-ready', '');
  const r = await canvas.evaluate((el: HTMLCanvasElement) => {
    const map = (el as HTMLCanvasElement & { fieldMap: Handle }).fieldMap;
    map.setProgress(0.62);
    map.render();
    const g = el.getContext('2d')!;
    const k = el.width / el.clientWidth;
    const alphaAt = (p: { x: number; y: number }) => g.getImageData(Math.round(p.x * k), Math.round(p.y * k), 1, 1).data[3]!;
    const a28 = map.pointAt(2, 28, 1);
    return {
      down: map.pointAt(2, 40, 1).y - a28.y,
      across: map.pointAt(2, 28, 10).x - a28.x,
      lit: alphaAt(map.pointAt(2, 33, 5)),
      dim: alphaAt(map.pointAt(1, 33, 5)),
      dimRow: alphaAt(map.pointAt(2, 20, 5)),
    };
  });
  expect(r.down).toBeGreaterThan(200); // rows run down the screen
  expect(r.across).toBeGreaterThan(150); // tree 1 on the left
  expect(r.lit).toBeGreaterThan(240);
  expect(r.dim).toBeLessThan(80);
  expect(r.dimRow).toBeLessThan(80);
});

test('the season fade never dims the empty rings (no flicker as the camera pulls out)', async ({ page }) => {
  await page.goto(URL);
  const canvas = page.locator('.scrub-map canvas[data-fieldmap]');
  await canvas.scrollIntoViewIfNeeded();
  await expect(canvas.locator('xpath=..')).toHaveAttribute('data-ready', '');
  const [plain, fading] = await canvas.evaluate((el: HTMLCanvasElement) => {
    const map = (el as HTMLCanvasElement & { fieldMap: Handle }).fieldMap;
    const g = el.getContext('2d')!;
    // The brightest pure ring pixel (#6F8F7A) on the canvas.
    const ringMax = () => {
      const d = g.getImageData(0, 0, el.width, el.height).data;
      let max = 0;
      for (let i = 0; i < d.length; i += 4)
        if (Math.abs(d[i]! - 111) < 10 && Math.abs(d[i + 1]! - 143) < 10 && Math.abs(d[i + 2]! - 122) < 10) max = Math.max(max, d[i + 3]!);
      return max;
    };
    const out: number[] = [];
    for (const season of [0, 0.425]) {
      map.draw({ reveal: 23, camera: 0.97, labels: 0, demo: 0, season, pulse: 0, touch: 0 });
      map.render();
      out.push(ringMax());
    }
    return out as [number, number];
  });
  expect(plain).toBeGreaterThan(200);
  expect(Math.abs(fading - plain)).toBeLessThanOrEqual(2);
});

test('redraws once per change, and every frame is cheap', async ({ page, browserName }) => {
  await page.goto(URL);
  const canvas = page.locator('.scrub-map canvas[data-fieldmap]');
  await canvas.scrollIntoViewIfNeeded();
  await expect(canvas.locator('xpath=..')).toHaveAttribute('data-ready', '');
  const r = await canvas.evaluate(async (el: HTMLCanvasElement) => {
    const map = (el as HTMLCanvasElement & { fieldMap: Handle }).fieldMap;
    const frame = () => new Promise((res) => requestAnimationFrame(() => requestAnimationFrame(res)));
    // Same progress three times: one frame. Again: none.
    await frame();
    const f0 = map.frames;
    map.setProgress(0.61);
    map.setProgress(0.61);
    map.setProgress(0.61);
    await frame();
    const once = map.frames - f0;
    map.setProgress(0.61);
    await frame();
    const again = map.frames - f0 - once;
    // Warm up, then time a uniform sweep of synchronous renders.
    for (let i = 0; i <= 100; i += 1) {
      map.setProgress(i / 100);
      map.render();
    }
    const times: number[] = [];
    for (let i = 0; i <= 500; i += 1) {
      map.setProgress(i / 500);
      const t0 = performance.now();
      map.render();
      times.push(performance.now() - t0);
    }
    const sorted = [...times].sort((a, b) => a - b);
    return {
      once,
      again,
      max: sorted[sorted.length - 1]!,
      // The 99th percentile: one GC pause or a busy CPU (the full suite runs in parallel) can spike a single frame.
      p99: sorted[Math.floor(sorted.length * 0.99)]!,
      avg: times.reduce((a, b) => a + b, 0) / times.length,
    };
  });
  expect(r.once).toBe(1);
  expect(r.again).toBe(0);
  // The frame budget is measured in Chromium (CI's browser); other engines' software canvases differ.
  if (browserName !== 'chromium') return;
  expect(r.p99, `p99 ${r.p99.toFixed(1)} ms, max ${r.max.toFixed(1)} ms`).toBeLessThan(50);
  expect(r.avg).toBeLessThanOrEqual(4);
});

test.describe('without JavaScript', () => {
  test.use({ javaScriptEnabled: false });
  test('the SVG first paint shows the field and every Trees tab state is server-rendered', async ({ page }) => {
    await page.goto(URL);
    const svg = page.locator('.lab-map .fm-svg:visible');
    await expect(svg).toHaveCount(1);
    await expect(svg).toContainText('Block 14');
    await expect(svg.locator('[data-note="2-31-4"]')).toHaveCount(1);
    expect(await state(page, 'trees-1416-block2').locator('[data-tree][data-s="today"]').count()).toBeGreaterThanOrEqual(90);
  });
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('the canvas still draws its final state', async ({ page }) => {
    await page.goto(URL);
    const canvas = page.locator('.lab-map canvas[data-fieldmap]');
    await canvas.scrollIntoViewIfNeeded();
    expect((await canvasPixels(canvas)).gold).toBeGreaterThan(500);
  });
});

test('axe: no serious or critical violations, no horizontal overflow', async ({ page }) => {
  await page.goto(URL);
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  const bad = results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).slice(0, 3).join(' | ')}`);
  expect(bad).toEqual([]);
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
});
