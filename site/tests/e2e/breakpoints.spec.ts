import { expect, test, type Page } from '@playwright/test';
import { settle } from './helpers';

/**
 * Crossing a breakpoint mid-visit keeps the reader's place: the same chapter at about the same
 * progress (an iPad turned between portrait and landscape changes every track's height). And a
 * wide window made shorter than 560px becomes the static page on the reader's chapter, never a
 * motion layout with its scenes gone.
 */

/** The chapter whose track holds the middle of the viewport, and its progress. */
const where = (page: Page) =>
  page.evaluate(() => {
    for (const s of Array.from(document.querySelectorAll<HTMLElement>('main section.sec'))) {
      const t = (s.querySelector<HTMLElement>('.track') ?? s).getBoundingClientRect();
      if (t.top <= innerHeight / 2 && t.bottom > innerHeight / 2) {
        const p = -t.top / Math.max(1, t.height - innerHeight);
        return { id: s.id, p: Math.round(p * 100) / 100 };
      }
    }
    return { id: '', p: 0 };
  });

const goTo = (page: Page, id: string, p: number) =>
  page.evaluate(
    ({ id, p }) => {
      const t = document.querySelector<HTMLElement>(`#${id} .track`)!;
      window.scrollTo(0, Math.round(t.getBoundingClientRect().top + scrollY + p * (t.offsetHeight - innerHeight)));
    },
    { id, p },
  );

for (const [from, to] of [
  [
    { width: 768, height: 1024 },
    { width: 1024, height: 768 },
  ],
  [
    { width: 1024, height: 768 },
    { width: 768, height: 1024 },
  ],
] as const) {
  for (const [id, p] of [
    ['crew', 0.53],
    ['field', 0.3],
    ['notes', 0.6],
  ] as const) {
    test(`${from.width}×${from.height} → ${to.width}×${to.height} keeps ${id} at ${p}`, async ({ page }, info) => {
      test.skip(info.project.name !== 'desktop' && info.project.name !== 'firefox-desktop', 'resizes a window');
      test.setTimeout(60_000);
      await page.setViewportSize(from);
      await page.goto('/');
      await settle(page);
      test.skip(!(await page.locator('html.motion').count()), 'motion is off');
      // Arrive the way a reader does: a few steps, then rest.
      for (const q of [p - 0.1, p - 0.05, p]) {
        await goTo(page, id, Math.max(0, q));
        await page.waitForTimeout(150);
      }
      await page.waitForTimeout(800);
      expect(await where(page)).toEqual({ id, p: expect.closeTo(p, 1) as unknown as number });
      await page.setViewportSize(to);
      await page.waitForTimeout(2600);
      const now = await where(page);
      expect(now.id, `after the turn: ${JSON.stringify(now)}`).toBe(id);
      expect(Math.abs(now.p - p), `after the turn: ${JSON.stringify(now)}`).toBeLessThan(0.06);
    });
  }
}

test('a wide window made shorter than 560px turns into the static page on the same chapter', async ({ page }, info) => {
  test.skip(info.project.name !== 'desktop' && info.project.name !== 'firefox-desktop', 'resizes a window');
  test.setTimeout(60_000);
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.goto('/');
  await settle(page);
  test.skip(!(await page.locator('html.motion').count()), 'motion is off');
  await goTo(page, 'notes', 0.3);
  await page.waitForTimeout(1200);
  const reload = page.waitForEvent('load');
  await page.setViewportSize({ width: 1280, height: 500 });
  await reload;
  await page.waitForTimeout(600);
  await expect(page.locator('html')).not.toHaveClass(/\bmotion\b/);
  await expect(page).toHaveURL(/#notes$/);
  const top = await page.locator('#notes').evaluate((el) => el.getBoundingClientRect().top);
  const pad = await page.evaluate(() => parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 0);
  expect(Math.abs(top - pad)).toBeLessThan(24);
});
