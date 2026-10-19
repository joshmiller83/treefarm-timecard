/**
 * CLOCK OUT (section team). The exchange at dusk, the lights-up and the paper time card.
 * Runs against the built site like tests/e2e (projects 'desktop' 1440 × 900 and 'mobile' 375 × 812).
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const ASK = 'You’ve worked 8 hours 30 minutes today. Clock out?';
const ANSWER = 'Clocked out at 4:31. 8 hours 30 minutes, 290 trees.';
const TOTALS = '39:55 hours · 1,347 trees';
const COLUMNS = ['Date', 'In', 'Out', 'Trees', 'Hours', 'Breaks', 'Notes'];

const sec = (page: Page) => page.locator('#clock-out');

/** Console errors, page errors and failed requests while the test runs. */
function watch(page: Page) {
  const problems: string[] = [];
  const requests: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()}`));
  page.on('response', (r) => {
    if (r.status() >= 400) problems.push(`HTTP ${r.status()}: ${r.url()}`);
  });
  page.on('request', (r) => requests.push(r.url()));
  return { problems, requests };
}

/** Waits for the motion core and the scenes near the first view. */
async function settle(page: Page) {
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(async () => {
    if (!document.documentElement.classList.contains('motion')) return;
    const t0 = performance.now();
    while (!(window as { __tf?: unknown }).__tf && performance.now() - t0 < 5000) await new Promise((r) => setTimeout(r, 50));
    const tf = (window as { __tf?: { ready: Promise<void> } }).__tf;
    if (tf) await Promise.race([tf.ready, new Promise((r) => setTimeout(r, 4000))]);
  });
}

/** Scrolls to progress `p` (0–1, or past 1) of the section's track and lets the scrub land. */
async function scrollTrack(page: Page, p: number, wait = 1100) {
  await page.evaluate((p) => {
    const track = document.querySelector<HTMLElement>('#clock-out .track')!;
    const top = track.getBoundingClientRect().top + scrollY;
    window.scrollTo(0, Math.round(top + p * Math.max(0, track.offsetHeight - innerHeight)));
  }, p);
  await page.waitForTimeout(wait);
}

async function serious(page: Page) {
  const results = await new AxeBuilder({ page })
    .include('#clock-out')
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
    .analyze();
  return results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
}

async function expectPaper(page: Page) {
  const table = sec(page).locator('table');
  await expect(table).toHaveCount(1);
  await expect(table.locator('caption')).toHaveText(/Example time card for Alex, Mon, Oct 12 – Fri, Oct 16/);
  await expect(table.locator('thead th[scope="col"]')).toHaveText(COLUMNS);
  await expect(table.locator('tbody tr[data-day]')).toHaveCount(5);
  await expect(table.locator('tfoot [data-totals]')).toHaveText(TOTALS);
}

async function overflow(page: Page) {
  return page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
}

test.describe('clock-out', () => {
  test('present, labeled, a real table, and nothing about pay', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await expect(sec(page)).toHaveAttribute('aria-labelledby', 'clock-out-h');
    await expect(page.locator('#clock-out-h')).toHaveText('Clocking out takes a yes.');
    await expect(sec(page).getByRole('heading', { level: 3, name: 'A time card you can hand in.' })).toHaveCount(1);
    // The spoken exchange, from siri.ts, on the page.
    await expect(sec(page).locator('[data-co-said]')).toHaveText('“Clock out with Time Card.”');
    await expect(sec(page).locator('[data-co-reply="ask"]')).toHaveText(ASK);
    await expect(sec(page).locator('[data-co-reply="answer"]')).toHaveText(ANSWER);
    // Both phones are one labeled image each.
    const lock = sec(page).locator('[data-phone][role="img"]').filter({ has: page.locator('[data-screen="lock-1631-quiet"]') });
    await expect(lock).toHaveAttribute('aria-label', new RegExp(`Clocked out at 4:31\\. 8 hours 30 minutes, 290 trees`));
    const report = sec(page).locator('[data-co-report] [data-phone][role="img"]');
    await expect(report).toHaveAttribute('aria-label', /Report tab with This week selected: .*39:55 hours and 1,347 trees over 5 days/);
    await expectPaper(page);
    await expect(sec(page).getByText('No pay on the report. Ever.')).toHaveCount(1);
    await expect(sec(page).getByRole('list', { name: 'Export formats' }).getByRole('listitem')).toHaveText(['PDF', 'CSV']);
    // No pay figures or currency anywhere in the section, phones included.
    const text = (await sec(page).textContent()) ?? '';
    expect(text).not.toMatch(/[$€£]|\bwage|\bpaid\b/i);
    expect(await sec(page).locator('[data-paper] th').allTextContents()).not.toContain('Pay');
    expect(problems).toEqual([]);
  });

  test('plays through its track with motion: the day ends, the lights come up, the paper prints', async ({ page, isMobile }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await expect(page.locator('html')).toHaveClass(/(^|\s)motion(\s|$)/);
    for (const p of [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1]) {
      await scrollTrack(page, p, 450);
      expect(await overflow(page), `overflow at ${p}`).toBeLessThanOrEqual(0);
    }
    await scrollTrack(page, 0.2);
    await expect(sec(page)).toHaveAttribute('data-theme', 'dark');
    await scrollTrack(page, 0.95);
    await expect(sec(page)).toHaveAttribute('data-theme', 'light');
    await expect(page.locator('.site-header')).toHaveAttribute('data-theme', 'light');
    if (!isMobile) {
      // Desktop: the paper is staged over the frame, every row printed, the chips popped.
      await expect(sec(page)).toHaveClass(/co-staged/);
      const paper = sec(page).locator('[data-paper]');
      await expect(paper).toBeInViewport();
      const clips = await paper.locator('tr[data-day]').evaluateAll((rows) => rows.map((r) => getComputedStyle(r).clipPath));
      for (const c of clips) expect(c).toMatch(/^(none|inset\(0(px|%)?\))$/);
      await expect(sec(page).locator('[data-co-chip="csv"]')).toHaveCSS('opacity', '1');
      await scrollTrack(page, 1);
      // The stage phone is back at rest for the next chapter.
      const t = await page.locator('[data-stage] [data-phone]').evaluate((el) => getComputedStyle(el).transform);
      expect(t === 'none' || t === 'matrix(1, 0, 0, 1, 0, 0)').toBe(true);
    } else {
      // Mobile: the paper is in flow after the track, full width, as stacked day blocks.
      await scrollTrack(page, 1.6);
      const paper = sec(page).locator('[data-paper]');
      await paper.scrollIntoViewIfNeeded();
      await expect(paper).toBeVisible();
      const box = await paper.boundingBox();
      expect(box!.width).toBeGreaterThan(300);
      expect(await paper.locator('tr[data-day]').first().evaluate((r) => getComputedStyle(r).display)).toBe('flex');
    }
    expect(problems).toEqual([]);
  });

  test('axe after the lights-up: no serious or critical violations', async ({ page, isMobile }) => {
    await page.goto('/');
    await settle(page);
    await scrollTrack(page, isMobile ? 1.6 : 0.9, 1400);
    await expect(sec(page)).toHaveAttribute('data-theme', 'light');
    expect(await serious(page)).toEqual([]);
  });
});

test.describe('clock-out with reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('the final state, static: dusk band, quiet lock screen, the Report tab and the printed paper', async ({ page }) => {
    const { problems, requests } = watch(page);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    await page.locator('#clock-out-h').scrollIntoViewIfNeeded();
    await expect(page.locator('#clock-out-h')).toBeVisible();
    // The exchange as a static transcript, every word at full opacity.
    for (const sel of ['[data-co-said]', '[data-co-reply="ask"]', '[data-co-yes]', '[data-co-reply="answer"]']) {
      const el = sec(page).locator(sel);
      await expect(el).toBeVisible();
      const faded = await el.locator('.co-w').evaluateAll((ws) => ws.filter((w) => Number(getComputedStyle(w).opacity) < 1).length);
      expect(faded, sel).toBe(0);
    }
    // The section phone shows the answer over the quiet lock screen (no Live Activity).
    const quiet = sec(page).locator('[data-screen="lock-1631-quiet"]');
    await quiet.scrollIntoViewIfNeeded();
    await expect(quiet).toBeVisible();
    await expect(quiet.locator('[data-snippet-text]')).toHaveText(ANSWER.replace(/ /g, ' ').replace(/ /g, ' '), { useInnerText: true });
    await expect(quiet.locator('[data-la]')).toHaveCount(0);
    // The light part: the Report tab beside the fully printed paper, the note and the chips.
    for (const sel of ['[data-co-report]', '[data-paper]', '[data-co-note]', '[data-co-chip="pdf"]', '[data-co-chip="csv"]']) {
      const el = sec(page).locator(sel);
      await el.scrollIntoViewIfNeeded();
      await expect(el, sel).toBeVisible();
    }
    await expectPaper(page);
    const rows = sec(page).locator('[data-paper] tr[data-day]');
    for (let i = 0; i < 5; i += 1) await expect(rows.nth(i)).toBeVisible();
    await expect(sec(page).locator('[data-totals]')).toHaveCSS('opacity', '1');
    // Light from the band on; no GSAP ever.
    await sec(page).locator('[data-paper]').scrollIntoViewIfNeeded();
    await expect(sec(page)).toHaveAttribute('data-theme', 'light');
    expect(requests.filter((u) => /gsap|ScrollTrigger/i.test(u))).toEqual([]);
    expect(await overflow(page)).toBeLessThanOrEqual(0);
    expect(problems).toEqual([]);
  });

  test('axe on the static section: no serious or critical violations', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    await sec(page).locator('[data-paper]').scrollIntoViewIfNeeded();
    expect(await serious(page)).toEqual([]);
  });

  test('at 375px the paper is stacked day blocks with no horizontal scroll', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    const paper = sec(page).locator('[data-paper]');
    await paper.scrollIntoViewIfNeeded();
    const box = await paper.boundingBox();
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(375);
    expect(await paper.locator('tr[data-day]').first().evaluate((r) => getComputedStyle(r).display)).toBe('flex');
    expect(await overflow(page)).toBeLessThanOrEqual(0);
  });
});
