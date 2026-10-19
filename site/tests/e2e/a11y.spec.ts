import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { settle } from './helpers';

async function serious(page: Page) {
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  return results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
}

test('axe: no serious or critical violations with motion', async ({ page }) => {
  await page.goto('/');
  await settle(page);
  expect(await serious(page)).toEqual([]);
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('axe: no serious or critical violations on the static page', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    // content-visibility: auto skips far sections; render everything for the scan.
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    expect(await serious(page)).toEqual([]);
  });
});

test('landmarks, skip link and one H1', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('header')).toHaveCount(1);
  await expect(page.locator('main#content')).toHaveCount(1);
  await expect(page.locator('body > footer')).toHaveCount(1);
  await expect(page.locator('nav[aria-label="The shift"]')).toHaveCount(1);
  await page.keyboard.press('Tab');
  const first = page.locator(':focus');
  await expect(first).toHaveText('Skip to content');
  await expect(first).toHaveAttribute('href', '#content');
  // Every phone mockup is one image with a label.
  const phones = page.locator('main [data-phone][role="img"]');
  const n = await phones.count();
  expect(n).toBeGreaterThan(0);
  for (let i = 0; i < n; i += 1) expect((await phones.nth(i).getAttribute('aria-label'))?.length ?? 0).toBeGreaterThan(20);
});
