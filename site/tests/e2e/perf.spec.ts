import { expect, test } from '@playwright/test';
import { SECTION_IDS, settle } from './helpers';

/**
 * Runs in the solo projects (playwright.config.ts): alone, after everything else.
 *
 * Scroll smoothness (Chromium, 1x CPU): once the page has settled, scrolling the whole page
 * never produces a long animation frame over 200 ms that the page's own work explains (its
 * scripts plus style, layout and paint: 100 ms or more of it). A frame that is long with no
 * work in it is the machine pausing the tab, not the page. Scenes are pre-built in idle time
 * (motion.ts), so no scene is built while the reader scrolls.
 */
test('no long frames over 200 ms while scrolling the whole page', { tag: '@solo' }, async ({ page, browserName }, info) => {
  test.skip(browserName !== 'chromium', 'Long Animation Frames is Chromium only');
  test.skip(!/^(desktop|mobile)(-solo)?$/.test(info.project.name), 'Chromium page projects');
  test.setTimeout(120_000);
  await page.addInitScript(() => {
    const w = window as unknown as { __loaf: { start: number; duration: number; work: number; what: string }[] };
    w.__loaf = [];
    try {
      new PerformanceObserver((list) => {
        for (const e of list.getEntries()) {
          const f = e as unknown as { renderStart?: number; scripts?: { sourceFunctionName?: string; sourceURL?: string; duration: number }[] };
          const scripts = f.scripts ?? [];
          const render = f.renderStart ? e.startTime + e.duration - f.renderStart : 0;
          const work = scripts.reduce((t, x) => t + x.duration, 0) + render;
          const what = `render ${Math.round(render)}ms; ` + scripts.map((x) => `${x.sourceFunctionName || '?'}@${(x.sourceURL || '').split('/').pop()} ${Math.round(x.duration)}ms`).join(', ');
          w.__loaf.push({ start: e.startTime, duration: e.duration, work, what });
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
  // Let the machine settle (a run that follows other projects starts while browsers close).
  await page.waitForTimeout(1500);
  const t0 = await page.evaluate(() => performance.now());
  const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  if (info.project.name.startsWith('mobile')) {
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
    (t0) =>
      (window as unknown as { __loaf: { start: number; duration: number; work: number; what: string }[] }).__loaf.filter(
        (f) => f.start >= t0 && f.duration > 200 && f.work >= 100,
      ),
    t0,
  );
  expect(long.map((f) => `${Math.round(f.duration)}ms at ${Math.round(f.start)}: ${f.what}`)).toEqual([]);
});

test('scroll layout shift over the whole page stays under 0.02 at 375', { tag: '@solo' }, async ({ page, browserName }, info) => {
  test.skip(browserName !== 'chromium', 'layout-shift entries are Chromium only');
  test.skip(!/^mobile(-solo)?$/.test(info.project.name), 'the phone layout');
  test.setTimeout(120_000);
  await page.addInitScript(() => {
    const w = window as unknown as { __ls: { v: number; t: number; src: string }[] };
    w.__ls = [];
    new PerformanceObserver((list) => {
      for (const e of list.getEntries() as unknown as Array<{ value: number; startTime: number; hadRecentInput: boolean; sources?: { node?: Node | null }[] }>) {
        if (e.hadRecentInput) continue;
        const src = (e.sources ?? []).map((s) => (s.node as Element | null)?.className?.toString().slice(0, 40) ?? '?').join('|');
        w.__ls.push({ v: e.value, t: e.startTime, src });
      }
    }).observe({ type: 'layout-shift', buffered: true });
  });
  await page.goto('/');
  await settle(page);
  await page.waitForTimeout(1500);
  const t0 = await page.evaluate(() => performance.now());
  const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  for (let y = 0; y <= h; y += 140) {
    await page.evaluate((y) => window.scrollTo(0, y), y);
    await page.waitForTimeout(30);
  }
  await page.waitForTimeout(800);
  const shifts = await page.evaluate((t0) => (window as unknown as { __ls: { v: number; t: number; src: string }[] }).__ls.filter((e) => e.t >= t0), t0);
  const sum = shifts.reduce((a, e) => a + e.v, 0);
  expect(sum, shifts.map((s) => `${s.v.toFixed(4)} ${s.src}`).join('\n')).toBeLessThan(0.02);
});
