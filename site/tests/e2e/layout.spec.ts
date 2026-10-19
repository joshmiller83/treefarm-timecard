import { expect, test } from '@playwright/test';
import { settle } from './helpers';

const overflow = () => document.documentElement.scrollWidth - document.documentElement.clientWidth;

for (const width of [320, 375]) {
  test.describe(`at ${width}px`, () => {
    test.use({ viewport: { width, height: 740 } });

    test('no horizontal overflow, with motion, anywhere on the page', async ({ page }) => {
      await page.goto('/');
      await settle(page);
      const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
      for (let i = 0; i <= 10; i += 1) {
        await page.evaluate((y) => window.scrollTo(0, y), Math.round((h * i) / 10));
        await page.waitForTimeout(100);
        expect(await page.evaluate(overflow), `scrolled ${i * 10}%`).toBeLessThanOrEqual(0);
      }
    });

    test('no horizontal overflow without motion', async ({ page }) => {
      await page.goto('/?motion=off');
      expect(await page.evaluate(overflow)).toBeLessThanOrEqual(0);
    });
  });
}

test('at 375 × 667 the H1, body, pill and primary button are above the fold', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 667 });
  await page.goto('/');
  await page.evaluate(() => document.fonts.ready);
  for (const loc of [
    page.locator('h1'),
    page.locator('#hero .beat-intro p').first(),
    page.locator('#hero .pill-status'),
    page.getByRole('link', { name: 'Follow along on GitHub' }).first(),
  ]) {
    const box = await loc.boundingBox();
    expect(box, await loc.innerText()).not.toBeNull();
    expect(box!.y + box!.height).toBeLessThanOrEqual(667);
  }
});
