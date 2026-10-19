import { expect, test } from '@playwright/test';
import { contrastOf } from './contrast';

/**
 * Pixel-sampled contrast where axe can't tell (text over gradients and tints).
 * See contrast.ts: the background is photographed with the text made transparent.
 */
test.describe('static page (reduced motion)', () => {
  test.use({ reducedMotion: 'reduce' });

  for (const width of [320, 375, 600, 899]) {
    test(`clock-out caption stays readable over the dusk band at ${width}px`, async ({ page }, info) => {
      test.skip(!/mobile/.test(info.project.name), 'one run per width');
      await page.setViewportSize({ width, height: 800 });
      await page.goto('/');
      await page.evaluate(() => document.fonts.ready);
      const cap = page.locator('#clock-out .shot figcaption');
      await cap.evaluate((el) => el.scrollIntoView({ block: 'center' }));
      await page.waitForTimeout(200);
      const r = await contrastOf(page, '#clock-out .shot figcaption');
      expect(r, 'the caption is on screen').not.toBeNull();
      expect(r!.ratio, `ratio ${r!.ratio} at ${r!.fontPx}px`).toBeGreaterThanOrEqual(r!.needed);
    });
  }
});
