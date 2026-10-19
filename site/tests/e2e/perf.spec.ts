import { expect, test } from '@playwright/test';
import { SECTION_IDS, settle } from './helpers';

/**
 * Scroll smoothness (Chromium, 1x CPU): once the page has settled, scrolling the whole page
 * never produces a long animation frame over 200 ms. Scenes are pre-built in idle time
 * (motion.ts), so no scene is built while the reader scrolls.
 */
test('no long frames over 200 ms while scrolling the whole page', async ({ page, browserName }, info) => {
  test.skip(browserName !== 'chromium', 'Long Animation Frames is Chromium only');
  test.skip(info.project.name !== 'desktop' && info.project.name !== 'mobile', 'Chromium page projects');
  test.setTimeout(120_000);
  await page.addInitScript(() => {
    const w = window as unknown as { __loaf: { start: number; duration: number; what: string }[] };
    w.__loaf = [];
    try {
      new PerformanceObserver((list) => {
        for (const e of list.getEntries()) {
          const scripts = (e as unknown as { scripts?: { sourceFunctionName?: string; sourceURL?: string; duration: number }[] }).scripts ?? [];
          const what = scripts.map((s) => `${s.sourceFunctionName || '?'}@${(s.sourceURL || '').split('/').pop()} ${Math.round(s.duration)}ms`).join(', ');
          w.__loaf.push({ start: e.startTime, duration: e.duration, what });
        }
      }).observe({ type: 'long-animation-frame', buffered: true });
    } catch {
      /* not supported */
    }
  });
  await page.goto('/');
  await settle(page);
  // Every scene pre-builds in idle time after the load (motion.ts measures each build).
  await page.waitForFunction((n) => performance.getEntriesByType('measure').filter((m) => m.name.startsWith('tf:scene:')).length >= n, SECTION_IDS.length, {
    timeout: 30_000,
  });
  await page.waitForTimeout(500);
  const t0 = await page.evaluate(() => performance.now());
  const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  if (info.project.name === 'mobile') {
    // Touch emulation has no wheel: step the scroll position at a reader's pace.
    for (let y = 0; y <= h; y += 160) {
      await page.evaluate((y) => window.scrollTo(0, y), y);
      await page.waitForTimeout(16);
    }
  } else {
    await page.mouse.move(400, 400);
    for (let y = 0; y <= h; y += 120) {
      await page.mouse.wheel(0, 120);
      await page.waitForTimeout(16);
    }
  }
  await page.waitForTimeout(800);
  const long = await page.evaluate(
    (t0) => (window as unknown as { __loaf: { start: number; duration: number; what: string }[] }).__loaf.filter((f) => f.start >= t0 && f.duration > 200),
    t0,
  );
  expect(long.map((f) => `${Math.round(f.duration)}ms at ${Math.round(f.start)}: ${f.what}`)).toEqual([]);
});
