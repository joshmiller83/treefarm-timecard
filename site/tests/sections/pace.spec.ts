/**
 * PACE (3:40 PM · the Clock tab): the section on the built page.
 *
 *   - the brief's copy and the phone's label are there, in motion and without it
 *   - reduced motion: the final state is all visible (tiles, bullets, small print, two crops of
 *     the Clock tab: the top, and Hours & pay with the week's bars and pay hidden)
 *   - with motion the tile digits end exactly on 34, 1:46 and 179 at progress 1 and after
 *     scrolling back and forth; the Live Activity and the Clock tab read the ledger's values
 *   - 375px: the tiles wrap 2 + 1 with no horizontal overflow; axe finds nothing serious
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { COPY, bulletText, phoneLabel, tilesAt } from '../../src/sections/pace/pace';

const TILES = tilesAt().map((t) => t.text); // ['34', '1:46', '179']

function watch(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error' || (m.type() === 'warning' && /\[motion\]/.test(m.text()))) problems.push(`${m.type()}: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  return problems;
}

async function settle(page: Page) {
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(async () => {
    if (!document.documentElement.classList.contains('motion')) return;
    const t0 = performance.now();
    while (!(window as { __tf?: unknown }).__tf && performance.now() - t0 < 5000) await new Promise((r) => setTimeout(r, 50));
    const tf = (window as { __tf?: { ready: Promise<void> } }).__tf;
    if (tf) await Promise.race([tf.ready, new Promise((r) => setTimeout(r, 4000))]);
  });
}

/** Scroll the pace track to progress p (0–1), stepping like a reader, and let the scrub settle. */
async function scrubTo(page: Page, p: number, steps = 6) {
  const [from, target] = await page.evaluate((p) => {
    const t = document.querySelector<HTMLElement>('#pace .track')!;
    const top = t.getBoundingClientRect().top + scrollY;
    return [scrollY, top + p * (t.offsetHeight - innerHeight)];
  }, p);
  for (let i = 1; i <= steps; i += 1) {
    await page.evaluate((y) => window.scrollTo(0, y), Math.round(from + ((target - from) * i) / steps));
    await page.waitForTimeout(60);
  }
  await page.waitForTimeout(1400);
}

/** The digits each rolling tile shows, read from its columns' transforms. */
async function rolledTiles(page: Page) {
  return page.locator('#pace [data-roll]').evaluateAll((rolls) =>
    rolls.map((roll) =>
      Array.from(roll.children)
        .map((part) => {
          const col = part.querySelector<HTMLElement>('.roll-col');
          if (!col) return part.textContent ?? '';
          const y = new DOMMatrixReadOnly(getComputedStyle(col).transform).m42;
          const cell = col.getBoundingClientRect().height / col.children.length;
          const idx = Math.round(-y / cell);
          return col.children[idx]?.textContent ?? '?';
        })
        .join(''),
    ),
  );
}

test.describe('pace', () => {
  test('is on the page with the brief’s copy and the phone’s label', async ({ page }) => {
    const problems = watch(page);
    await page.goto('/');
    await settle(page);
    const sec = page.locator('#pace');
    await expect(sec).toHaveAttribute('aria-labelledby', 'pace-h');
    await expect(page.locator('#pace-h')).toHaveText('Know your pace.');
    await expect(sec.locator('.eyebrow')).toHaveText('3:40 PM · The Clock tab');
    await expect(sec.locator('.beat-intro')).toContainText(COPY.body);
    // Each tile reads as one phrase to a screen reader ('1 minute 46 seconds a tree').
    for (const t of tilesAt()) await expect(sec.locator(`[data-tile="${t.id}"] .sr-only`)).toHaveText(t.spoken);
    const bullets = sec.locator('[data-bullet]');
    await expect(bullets).toHaveCount(3);
    for (const [i, b] of COPY.bullets.entries()) await expect(bullets.nth(i)).toHaveText(bulletText(b));
    await expect(sec.locator('[data-small]')).toHaveText(COPY.small);
    // The phone is one image with the brief's sentence and the week's values in words.
    await expect(page.getByRole('img', { name: phoneLabel() })).toHaveCount(1);
    await expect(sec.locator('figcaption')).toHaveText(COPY.caption);
    // No currency anywhere in the section.
    expect(await sec.evaluate((el) => el.textContent ?? '')).not.toContain('$');
    expect(problems).toEqual([]);
  });

  test.describe('reduced motion', () => {
    test.use({ reducedMotion: 'reduce' });

    test('shows the final state: tiles, bullets, small print and two crops of the Clock tab', async ({ page }) => {
      const problems = watch(page);
      await page.goto('/');
      await page.evaluate(() => document.fonts.ready);
      await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
      const sec = page.locator('#pace');
      await sec.scrollIntoViewIfNeeded();
      // Plain numbers, no rolling digits.
      await expect(sec.locator('.pace-num-text')).toHaveText(TILES);
      for (const el of await sec.locator('.pace-num-text, .pace-unit, [data-bullet], [data-small], [data-tile-rule]').all()) {
        await expect(el).toBeVisible();
      }
      await expect(sec.locator('.pace-roll').first()).toBeHidden();
      const faded = await sec.locator('.beat, .beat *').evaluateAll((els) =>
        els.filter((e) => Number(getComputedStyle(e).opacity) < 1).map((e) => e.className),
      );
      expect(faded).toEqual([]);

      // Two phones: the top of the tab and its bottom crop.
      const phones = sec.locator('[data-phone][role="img"]');
      await expect(phones).toHaveCount(2);
      await expect(phones.nth(0)).toBeVisible();
      await expect(phones.nth(1)).toBeVisible();
      const inScreen = async (phone: number, sel: string) =>
        phones.nth(phone).evaluate((ph, sel) => {
          const screen = ph.querySelector('.screen')!.getBoundingClientRect();
          const el = ph.querySelector(sel);
          if (!el) return `missing ${sel}`;
          const r = el.getBoundingClientRect();
          return r.height > 0 && r.top >= screen.top - 0.5 && r.bottom <= screen.bottom + 0.5 ? 'in' : `out ${sel} ${r.top}–${r.bottom} vs ${screen.top}–${screen.bottom}`;
        }, sel);
      // Top crop: status card, now working, trees this shift.
      for (const sel of ['[data-status-card]', '[data-now-working]', '[data-trees-card] [data-trees]']) expect(await inScreen(0, sel)).toBe('in');
      // Bottom crop: the pace card's last rows and Hours & pay with the week's bars and pay hidden.
      for (const sel of ['[data-pace-row="best"]', '[data-pace-row="left"]', '[data-hours-card] [data-bar="mon"]', '[data-hours-card] [data-bar="fri"]', '[data-pay]', '[data-pay-toggle]']) {
        expect(await inScreen(1, sel)).toBe('in');
      }
      await expect(phones.nth(1).locator('[data-pay]')).toHaveText('•••');
      expect(problems).toEqual([]);
    });

    test('axe: nothing serious in the static section', async ({ page }) => {
      await page.goto('/');
      await page.evaluate(() => document.fonts.ready);
      await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
      const r = await new AxeBuilder({ page }).include('#pace').withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
      expect(r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => v.id)).toEqual([]);
    });
  });

  test('axe: nothing serious in the section with motion, mid-scene', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    await page.evaluate(() => {
      const t = document.querySelector<HTMLElement>('#pace .track')!;
      window.scrollTo(0, t.getBoundingClientRect().top + scrollY + 0.5 * (t.offsetHeight - innerHeight));
    });
    await page.waitForTimeout(1500);
    const r = await new AxeBuilder({ page }).include('#pace').withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
    expect(r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => v.id)).toEqual([]);
  });

  test('with motion: the time-lapse, the tiles and the bars land on the ledger’s values, both ways', async ({ page }) => {
    const problems = watch(page);
    await page.goto('/');
    await settle(page);
    test.skip(!(await page.locator('html.motion').count()), 'motion is off in this viewport');
    // Approach from above, like a reader.
    await page.evaluate(() => window.scrollTo(0, document.querySelector<HTMLElement>('#pace')!.getBoundingClientRect().top + scrollY - innerHeight * 1.5));
    await page.waitForTimeout(600);

    const lock = '[data-screen="lock-1540-activity"]';
    const clock = '[data-screen="clock-1540"]';
    await scrubTo(page, 0.005);
    await expect(page.locator(`${lock} [data-trees]`)).toHaveAttribute('data-odo-text', '240');
    await expect(page.locator(`${lock}`)).toHaveCSS('opacity', '1');

    await scrubTo(page, 0.12);
    await expect(page.locator(`${lock} [data-trees]`)).toHaveAttribute('data-odo-text', '260');
    await expect(page.locator(`${clock} [data-status-card] [data-timer]`)).toHaveAttribute('data-odo-text', /^7:39:0\d$/);

    await scrubTo(page, 0.7);
    expect(await rolledTiles(page)).toEqual(TILES);
    const scale = (sel: string) =>
      page.locator(sel).evaluateAll((els) => els.map((e) => new DOMMatrixReadOnly(getComputedStyle(e).transform).d));
    expect((await scale(`${clock} [data-hours-card] [data-bar]`)).every((d) => Math.abs(d - 1) < 1e-3)).toBe(true);
    expect((await scale(`${clock} [data-pace-row="trees-hour"] [data-pace-rule]`))[0]).toBeCloseTo(1, 3);

    await scrubTo(page, 1);
    expect(await rolledTiles(page)).toEqual(TILES);
    // The phone ends at rest on the lock screen.
    expect(await page.locator(lock).evaluate((el) => new DOMMatrixReadOnly(getComputedStyle(el).transform).m42)).toBeCloseTo(0, 0);

    // Back before the first tile, then forward again: still exact.
    await scrubTo(page, 0.2);
    const hidden = await page.locator('#pace [data-tile] .pace-tile-face').evaluateAll((els) => els.map((e) => Number(getComputedStyle(e).opacity)));
    expect(Math.max(...hidden)).toBeLessThan(0.35);
    await scrubTo(page, 0.95);
    expect(await rolledTiles(page)).toEqual(TILES);
    expect(problems).toEqual([]);
  });

  test.describe('at 375px', () => {
    test.use({ viewport: { width: 375, height: 812 } });
    const overflow = () => document.documentElement.scrollWidth - document.documentElement.clientWidth;

    for (const mode of ['motion', 'static'] as const) {
      test(`the tiles wrap 2 + 1 with no horizontal overflow (${mode})`, async ({ page }) => {
        await page.goto(mode === 'static' ? '/?motion=off' : '/');
        await settle(page);
        for (const p of [0, 0.35, 0.7, 1]) {
          await page.evaluate((p) => {
            const t = document.querySelector<HTMLElement>('#pace .track')!;
            window.scrollTo(0, t.getBoundingClientRect().top + scrollY + p * Math.max(0, t.offsetHeight - innerHeight));
          }, p);
          await page.waitForTimeout(150);
          expect(await page.evaluate(overflow), `at ${p}`).toBeLessThanOrEqual(0);
        }
        const boxes = await page.locator('#pace [data-tile]').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().toJSON() as DOMRect));
        expect(boxes).toHaveLength(3);
        const [a, b, c] = boxes as [DOMRect, DOMRect, DOMRect];
        expect(Math.abs(a.top - b.top)).toBeLessThan(1);
        expect(c.top).toBeGreaterThanOrEqual(a.bottom);
        for (const r of boxes) expect(r.right).toBeLessThanOrEqual(375);
      });
    }
  });
});
