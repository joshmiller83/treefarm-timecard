import { expect, test } from '@playwright/test';
import { settle } from './helpers';

/**
 * Copy beats never print through each other at common laptop heights (all engines with
 * PW_ALL=1). Beats sit at fixed points of their section's track, so their boxes in the
 * document must not overlap.
 */
for (const vp of [
  { width: 1366, height: 657 },
  { width: 1280, height: 600 },
  { width: 1024, height: 768 },
  { width: 1440, height: 900 },
]) {
  test(`pace at ${vp.width} × ${vp.height}: the stats and the bullets keep apart`, async ({ page }, info) => {
    test.skip(!/desktop/.test(info.project.name), 'laptop and desktop sizes');
    await page.setViewportSize(vp);
    await page.goto('/');
    await settle(page);
    const gap = await page.evaluate(() => {
      const a = document.querySelector('#pace .pace-stats')!.getBoundingClientRect();
      const b = document.querySelector('#pace .pace-more')!.getBoundingClientRect();
      return Math.round(b.top - a.bottom);
    });
    expect(gap, 'px between the stat tiles and the bullets').toBeGreaterThanOrEqual(24);

    // And on screen: scroll through the chapter; no visible bullet ever overlaps a visible tile.
    const geo = await page.evaluate(() => {
      const t = document.querySelector('#pace .track')!.getBoundingClientRect();
      return { top: t.top + scrollY, h: t.height };
    });
    for (let p = 0.3; p <= 1.001; p += 0.1) {
      await page.evaluate((y) => window.scrollTo(0, y), Math.round(geo.top + p * (geo.h - vp.height)));
      await page.waitForTimeout(250);
      const hits = await page.evaluate(() => {
        const vis = (el: Element) => {
          for (let n: Element | null = el; n; n = n.parentElement) if (Number(getComputedStyle(n).opacity) < 0.1) return false;
          return true;
        };
        const tiles = Array.from(document.querySelectorAll('#pace [data-tile]')).filter(vis).map((e) => e.getBoundingClientRect());
        const more = Array.from(document.querySelectorAll('#pace [data-bullet], #pace [data-small]')).filter(vis).map((e) => e.getBoundingClientRect());
        return more.filter((m) => tiles.some((t) => Math.min(m.bottom, t.bottom) - Math.max(m.top, t.top) > 1)).length;
      });
      expect(hits, `progress ${p.toFixed(1)}`).toBe(0);
    }
  });
}
