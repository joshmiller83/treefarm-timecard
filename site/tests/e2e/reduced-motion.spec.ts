import { expect, test } from '@playwright/test';
import { SECTION_IDS, settle, watch } from './helpers';

test.use({ reducedMotion: 'reduce' });

test('reduced motion: a complete static page, and GSAP is never requested', async ({ page }) => {
  const { problems, requests } = watch(page);
  await page.goto('/');
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(1500);
  await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
  // Every chapter heading and every figure is visible.
  for (const id of SECTION_IDS) {
    await page.locator(`#${id}-h`).scrollIntoViewIfNeeded();
    await expect(page.locator(`#${id}-h`)).toBeVisible();
  }
  const figures = page.locator('main figure');
  const n = await figures.count();
  for (let i = 0; i < n; i += 1) {
    await figures.nth(i).scrollIntoViewIfNeeded();
    await expect(figures.nth(i)).toBeVisible();
  }
  // Nothing in the copy is faded.
  const faded = await page.locator('main .beat, main .beat *').evaluateAll((els) =>
    els.filter((e) => Number(getComputedStyle(e).opacity) < 1).map((e) => e.outerHTML.slice(0, 80)),
  );
  expect(faded).toEqual([]);
  // The pause toggle is hidden and the ribbon fill is off.
  await expect(page.locator('[data-pause-toggle]')).toBeHidden();
  expect(requests.filter((u) => /gsap|motion\.[\w-]+\.js|ScrollTrigger/i.test(u))).toEqual([]);
  expect(problems).toEqual([]);
});

test.describe('reduced motion switched on mid-visit', () => {
  test.use({ reducedMotion: 'no-preference' });

  test('the page becomes the static page on the chapter the reader was in', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    await expect(page.locator('html')).toHaveClass(/motion-ready/);
    await page.locator('#field').evaluate((el) => window.scrollTo(0, el.getBoundingClientRect().top + scrollY + 200));
    await page.waitForTimeout(600);
    await Promise.all([page.waitForEvent('load'), page.emulateMedia({ reducedMotion: 'reduce' })]);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    await expect(page).toHaveURL(/#field$/);
    await page.waitForTimeout(400);
    const top = await page.locator('#field').evaluate((el) => el.getBoundingClientRect().top);
    expect(Math.abs(top)).toBeLessThan(160);
  });
});
