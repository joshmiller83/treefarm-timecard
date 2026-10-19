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

/**
 * The intro never prints under the stat tiles. At laptop heights the first tile's big numerals
 * reach the intro's last line in the document, so the intro must be gone (or clear of the
 * tiles) whenever a tile shows. Scrolled in small steps through the whole chapter.
 */
for (const vp of [
  { width: 1280, height: 600 },
  { width: 1366, height: 657 },
  { width: 1024, height: 640 },
]) {
  test(`pace at ${vp.width} × ${vp.height}: the intro and the stat tiles never overlap on screen`, async ({ page }, info) => {
    test.skip(!/desktop/.test(info.project.name), 'laptop and desktop sizes');
    test.setTimeout(90_000);
    await page.setViewportSize(vp);
    await page.goto('/');
    await settle(page);
    const geo = await page.evaluate(() => {
      const t = document.querySelector('#pace .track')!.getBoundingClientRect();
      return { top: t.top + scrollY, h: t.height };
    });
    // The chapter as a reader meets it: its scene built (it builds as the reader nears it).
    await page.evaluate((y) => window.scrollTo(0, y), Math.round(geo.top - vp.height * 1.5));
    await page.waitForFunction(() => performance.getEntriesByType('measure').some((m) => m.name === 'tf:scene:pace'), null, { timeout: 15_000 });
    const worst: string[] = [];
    for (let y = geo.top - vp.height; y <= geo.top + geo.h; y += 40) {
      await page.evaluate((y) => window.scrollTo(0, y), Math.round(y));
      await page.waitForTimeout(90);
      const hit = await page.evaluate(() => {
        const vis = (el: Element) => {
          for (let n: Element | null = el; n; n = n.parentElement) {
            const cs = getComputedStyle(n);
            if (Number(cs.opacity) < 0.1 || cs.visibility === 'hidden') return false;
          }
          return true;
        };
        const intro = Array.from(document.querySelectorAll('#pace .beat-head p')).filter(vis).map((e) => e.getBoundingClientRect());
        const tiles = Array.from(document.querySelectorAll('#pace [data-tile] .pace-tile-face')).filter(vis).map((e) => e.getBoundingClientRect());
        let most = 0;
        for (const a of intro)
          for (const b of tiles) {
            const dy = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top);
            const dx = Math.min(a.right, b.right) - Math.max(a.left, b.left);
            if (dx > 1 && dy > most) most = dy;
          }
        return Math.round(most);
      });
      if (hit > 1) worst.push(`${hit}px at scrollY ${Math.round(y)}`);
    }
    expect(worst, 'intro paragraph under a visible stat tile').toEqual([]);
  });
}

