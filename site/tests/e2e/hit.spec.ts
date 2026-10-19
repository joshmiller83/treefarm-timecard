import { expect, test, type Page } from '@playwright/test';
import { settle } from './helpers';

/**
 * Hit testing: every visible link and button a reader can see is the element a tap at its
 * centre lands on. Invisible layers (an opacity-0 caption card, a fixed overlay) must never
 * swallow taps. Phone widths and a tablet, with motion, through the whole page.
 */

/** Controls whose centre is on screen, visible, and not the element a tap there would hit. */
async function blocked(page: Page) {
  return page.evaluate(() => {
    // Everything the header covers: the bar, the ribbon and the band with the chapter chip.
    const band = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--chrome-h')) || 59;
    const visible = (el: Element) => {
      if (el.closest('[aria-hidden="true"], [inert]')) return false;
      for (let n: Element | null = el; n && n !== document.documentElement; n = n.parentElement) {
        const cs = getComputedStyle(n);
        if (cs.visibility !== 'visible' && n === el) return false;
        if (Number(cs.opacity) < 0.6) return false;
        if (cs.display === 'none') return false;
      }
      return true;
    };
    const out: string[] = [];
    for (const el of Array.from(document.querySelectorAll<HTMLElement>('main a[href], main button, footer a[href], footer button'))) {
      const r = el.getBoundingClientRect();
      if (r.width < 4 || r.height < 4) continue;
      const x = r.left + r.width / 2;
      const y = r.top + r.height / 2;
      if (y < band + 4 || y > innerHeight - 4 || x < 2 || x > innerWidth - 2) continue;
      if (!visible(el)) continue;
      const hit = document.elementFromPoint(x, y);
      if (hit && (hit === el || el.contains(hit))) continue;
      const who = hit ? `${hit.tagName.toLowerCase()}${hit.className && typeof hit.className === 'string' ? '.' + hit.className.trim().split(/\s+/).join('.') : ''}` : 'nothing';
      out.push(`${(el.textContent ?? '').trim().replace(/\s+/g, ' ').slice(0, 40) || el.getAttribute('aria-label')} @${Math.round(scrollY)} → ${who}`);
    }
    return out;
  });
}

for (const vp of [
  { width: 375, height: 812 },
  { width: 768, height: 1024 },
]) {
  test.describe(`hit testing at ${vp.width}`, () => {
    test.use({ viewport: vp });

    test('the hero links take a tap', async ({ page }, info) => {
      test.skip(!/mobile/.test(info.project.name), 'phone and tablet widths');
      await page.goto('/');
      await settle(page);
      for (const name of ['Follow along on GitHub', 'Walk through a shift']) {
        const link = page.getByRole('link', { name }).first();
        await link.scrollIntoViewIfNeeded();
        const box = (await link.boundingBox())!;
        const ok = await page.evaluate(
          ({ x, y, name }) => {
            const hit = document.elementFromPoint(x, y);
            return !!hit?.closest('a') && hit.closest('a')!.textContent!.includes(name);
          },
          { x: box.x + box.width / 2, y: box.y + box.height / 2, name },
        );
        expect(ok, name).toBe(true);
      }
      await page.getByRole('link', { name: 'Walk through a shift' }).first().tap();
      await expect(page).toHaveURL(/#voice$/);
    });

    test('nothing invisible sits over a control, anywhere on the page', async ({ page }, info) => {
      test.skip(!/mobile/.test(info.project.name), 'phone and tablet widths');
      test.setTimeout(120_000);
      await page.goto('/');
      await settle(page);
      const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
      const steps = 40;
      const problems: string[] = [];
      for (let i = 0; i <= steps; i += 1) {
        await page.evaluate((y) => window.scrollTo(0, y), Math.round((h * i) / steps));
        await page.waitForTimeout(140);
        problems.push(...(await blocked(page)));
      }
      expect(problems).toEqual([]);
    });
  });
}

/** Rects of the visible cards of one chapter that overlap an element of the next one. */
async function overlaps(page: Page, fromSel: string, targetSel: string) {
  return page.evaluate(
    ({ fromSel, targetSel }) => {
      const target = document.querySelector(targetSel)!.getBoundingClientRect();
      const out: string[] = [];
      for (const el of Array.from(document.querySelectorAll<HTMLElement>(fromSel))) {
        const cs = getComputedStyle(el);
        if (cs.visibility !== 'visible' || Number(cs.opacity) < 0.05 || cs.display === 'none') continue;
        const r = el.getBoundingClientRect();
        const x = Math.min(r.right, target.right) - Math.max(r.left, target.left);
        const y = Math.min(r.bottom, target.bottom) - Math.max(r.top, target.top);
        if (x > 1 && y > 1 && target.bottom > 0 && target.top < innerHeight) out.push(`${el.className} over ${targetSel} by ${Math.round(y)}px @${Math.round(scrollY)}`);
      }
      return out;
    },
    { fromSel, targetSel },
  );
}

for (const vp of [
  { width: 360, height: 640 },
  { width: 375, height: 667 },
  { width: 430, height: 932 },
]) {
  test(`lock screen → field seam at ${vp.width} × ${vp.height}: no lock-screen card over the field's heading`, async ({ page }, info) => {
    test.skip(!/mobile/.test(info.project.name), 'phone widths');
    await page.setViewportSize(vp);
    await page.goto('/');
    await settle(page);
    const end = await page.evaluate(() => {
      const t = document.querySelector('#lock-screen .track')!;
      return t.getBoundingClientRect().bottom + scrollY;
    });
    const problems: string[] = [];
    for (let y = end - 2 * vp.height; y <= end + vp.height; y += Math.round(vp.height / 6)) {
      await page.evaluate((y) => window.scrollTo(0, y), y);
      await page.waitForTimeout(160);
      problems.push(...(await overlaps(page, '#lock-screen .beat', '#field-h')));
      problems.push(...(await overlaps(page, '#lock-screen .beat', '#field .eyebrow')));
    }
    expect(problems).toEqual([]);
  });
}
