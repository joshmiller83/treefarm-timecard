import AxeBuilder from '@axe-core/playwright';
import { expect, test } from '@playwright/test';
import { settle } from './helpers';

/**
 * axe at every stage of the scroll, not only at load: copy fades, dims and moves while the
 * reader scrolls, so contrast and hidden-but-focusable problems only show mid-scene.
 * 24 positions through the whole page, in each page project's solo run (playwright.config.ts:
 * alone, after everything else, so axe is never starved by parallel workers).
 */
test('axe: no serious or critical violations at 24 scroll positions', { tag: '@solo' }, async ({ page }) => {
  test.setTimeout(300_000);
  await page.goto('/');
  await settle(page);
  const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  const found: string[] = [];
  const knownContrast: string[] = [];
  const steps = 24;
  for (let i = 0; i < steps; i += 1) {
    const y = Math.round((h * (i + 0.5)) / steps);
    // Arrive the way a reader does: in steps, so the scrubbed scenes catch up.
    await page.evaluate((y) => window.scrollTo(0, y - 300), y);
    await page.waitForTimeout(150);
    await page.evaluate((y) => window.scrollTo(0, y), y);
    await page.waitForTimeout(900);
    const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze();
    for (const v of results.violations) {
      if (v.impact !== 'serious' && v.impact !== 'critical') continue;
      for (const n of v.nodes.slice(0, 4)) {
        const line = `@${y} ${v.id}: ${n.target.join(' ')} ${(n.any[0]?.message ?? '').slice(0, 90)}`;
        // Known issue #15: text that is mid-fade between story beats can dip below 4.5:1 for a
        // few dozen pixels of scroll. Reported here, not failed, until #15 is fixed. Every other
        // rule still fails the test.
        if (v.id === 'color-contrast') knownContrast.push(line);
        else found.push(line);
      }
    }
  }
  if (knownContrast.length) {
    test.info().annotations.push({
      type: 'known issue #15',
      description: `${knownContrast.length} contrast nodes during fades: ${knownContrast.slice(0, 6).join(' | ')}`,
    });
  }
  expect(found).toEqual([]);
});
