/**
 * Section: LOCK SCREEN · 2:14 PM (src/sections/LockScreen.astro, src/scripts/scenes/lock-screen.ts).
 *
 *   npm run build && npx astro preview --background --port 4510
 *   PW_PORT=4510 npx playwright test tests/sections/lock-screen.spec.ts --project=desktop --project=mobile
 *
 * Checks the static final state (reduced motion), the scrubbed scene at key progress points
 * (desktop stage and mobile section phone), the brief's acceptance rules, and axe.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';
import { liveActivityAt, MOMENTS, fmtCount } from '../../src/data/ledger';
import { CALLOUTS, phoneLabel } from '../../src/sections/lock-screen/model';
import { settle, watch } from '../e2e/helpers';

const TAPPED = liveActivityAt(MOMENTS.tapped);
const NOTE_TEXT = CALLOUTS.map((c) => [c.label, c.sub].filter(Boolean).join(' '));

const overflow = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

type Trigger = { trigger?: Element; animation?: unknown; start: number; end: number };

/**
 * Scrolls so the section's track is at scroll progress `p` (0–1): by the scene's own
 * ScrollTrigger when there is one (mobile emulation changes innerHeight as it scrolls).
 */
async function toProgress(page: Page, p: number, wait = 900) {
  await page.evaluate((p) => {
    const track = document.querySelector<HTMLElement>('#lock-screen .track')!;
    const tf = (window as unknown as { __tf?: { ScrollTrigger: { getAll(): Trigger[] } } }).__tf;
    const st = tf?.ScrollTrigger.getAll().find((t) => t.trigger === track && !!t.animation);
    const top = track.getBoundingClientRect().top + scrollY;
    window.scrollTo(0, Math.round(st ? st.start + p * (st.end - st.start) : top + p * (track.offsetHeight - innerHeight)));
  }, p);
  await page.waitForTimeout(wait);
}

/** Waits until this section's scene has been built (it marks the section). */
async function sceneBuilt(page: Page) {
  await toProgress(page, 0, 200);
  await expect(page.locator('#lock-screen[data-ls-scene="built"]')).toHaveCount(1, { timeout: 8000 });
}

/** Computed opacity of the first match. */
const opacity = (loc: Locator) => loc.first().evaluate((el) => Number(getComputedStyle(el).opacity));

/** The scale of an element's own transform (1 when none). */
const scaleOf = (loc: Locator) => loc.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).a);

/** The pt scale of the screen an element sits in. */
const pt = (loc: Locator) => loc.evaluate((el) => el.closest('.screen')!.getBoundingClientRect().width / 393);

/** Row buttons whose centre is inside the visible strip, left to right. */
async function visibleRows(la: Locator): Promise<string[]> {
  return la.evaluate((root) => {
    const strip = root.querySelector('[data-strip]')!.getBoundingClientRect();
    return Array.from(root.querySelectorAll<HTMLElement>('[data-row]'))
      .filter((b) => {
        const r = b.getBoundingClientRect();
        const c = r.left + r.width / 2;
        return c > strip.left && c < strip.right;
      })
      .sort((a, b) => a.getBoundingClientRect().left - b.getBoundingClientRect().left)
      .map((b) => b.textContent!.trim());
  });
}

async function serious(page: Page) {
  const results = await new AxeBuilder({ page })
    .include('#lock-screen')
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
    .analyze();
  return results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
}

// ---------------------------------------------------------------------------

test.describe('reduced motion: the static final state', () => {
  test.use({ reducedMotion: 'reduce' });

  test('shows the tapped lock screen, the numbered notes, the island crops and the controls', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    const sec = page.locator('#lock-screen');
    await sec.scrollIntoViewIfNeeded();
    await expect(page.locator('#lock-screen-h')).toHaveText('Your time card, right on the lock screen.');

    // Figure 1: the phone, with the brief's label.
    const phone = sec.locator('figure.shot [data-phone][role="img"]');
    await expect(phone).toHaveAttribute('aria-label', phoneLabel());
    await phone.scrollIntoViewIfNeeded();
    await expect(phone).toBeVisible();
    const la = phone.locator('[data-screen="lock-1414-tapped"] [data-la]');
    await expect(la).toBeVisible();
    await expect(la.locator('[data-timer]').first()).toHaveAttribute('data-odo-text', '6:27:00');
    await expect(la.locator('[data-trees]')).toHaveAttribute('data-odo-text', fmtCount(TAPPED.trees));
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    await expect(la.locator('[data-break-btn]')).toHaveText('Break');
    await expect(la.locator('[data-undo]')).toContainText(`Row ${TAPPED.undoRow} marked`);
    await expect(la).not.toContainText(/clock out/i);

    // Six numbered pins on the card and the matching list beside it.
    const pins = phone.locator('[data-pin]');
    await expect(pins).toHaveCount(6);
    for (let i = 0; i < 6; i += 1) await expect(pins.nth(i)).toBeVisible();
    const notes = sec.locator('[data-ls-notes] > li');
    await expect(notes).toHaveCount(6);
    for (let i = 0; i < 6; i += 1) {
      await expect(notes.nth(i)).toBeVisible();
      await expect(notes.nth(i)).toContainText(NOTE_TEXT[i]!);
    }
    // The ghost Clock out button, struck through.
    const ghost = sec.locator('[data-ls-notes] [data-ls-ghost]');
    await expect(ghost).toBeVisible();
    await expect(ghost).toHaveAttribute('aria-label', /no clock-out button/i);

    // Figure 2: the Dynamic Island, compact and expanded.
    const crops = sec.locator('[data-ls-island-fig] [role="img"]');
    await expect(crops).toHaveCount(2);
    for (let i = 0; i < 2; i += 1) {
      await crops.nth(i).scrollIntoViewIfNeeded();
      await expect(crops.nth(i)).toBeVisible();
    }
    // A crop of the top of the screen: the search pill and the dock stay below it.
    for (let i = 0; i < 2; i += 1) {
      const clear = await crops.nth(i).evaluate((crop) => {
        const screen = crop.querySelector('.crop-screen')!.getBoundingClientRect();
        return Array.from(crop.querySelectorAll('.home-search, .home-dock')).every((el) => el.getBoundingClientRect().top >= screen.bottom - 0.5);
      });
      expect(clear, `crop ${i + 1} shows only the top of the home screen`).toBe(true);
    }
    await expect(crops.nth(0)).toHaveAttribute('aria-label', /compact.*Row 37.*6:29/i);
    await expect(crops.nth(1)).toHaveAttribute('aria-label', /expanded.*North field.*Block 2.*6:29:10/i);

    // Figure 3: the controls, with the qualifiers and the 8-hour footnote.
    await expect(sec.locator('[data-controls]')).toBeVisible();
    const foot = sec.locator('[data-ls-footnote]');
    await expect(foot).toContainText('A Live Activity can stay up for 8 hours. Time Card reminds you before it runs out.');
    await expect(foot).toContainText('Not every iPhone has an Action button.');
    await expect(foot).toContainText('Control Center controls need iOS 18 or later.');

    // Desktop-only callouts and the mobile tap card stay out of the static page.
    await expect(sec.locator('[data-ls-callouts]')).toBeHidden();
    await expect(sec.locator('[data-ls-tap-card]')).toBeHidden();
    expect(await overflow(page)).toBeLessThanOrEqual(0);
    expect(problems).toEqual([]);
  });

  test('axe: no serious or critical violations in the static section', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    expect(await serious(page)).toEqual([]);
  });
});

test.describe('acceptance: the Live Activity', () => {
  test.use({ reducedMotion: 'reduce' });
  test('is 160 pt or less, with 44 pt buttons and never a clock-out control', async ({ page }) => {
    await page.goto('/');
    // Without motion only the final layer renders (the others are display: none).
    const las = page.locator('#lock-screen [data-final] [data-la]');
    const n = await las.count();
    expect(n).toBeGreaterThan(0);
    for (let i = 0; i < n; i += 1) {
      const la = las.nth(i);
      await expect(la).not.toContainText(/clock out/i);
      // Far sections skip rendering (content-visibility: auto) and Firefox reports unlaid-out
      // boxes inside them (a 208 px screen, a 1322 px card): measure it once it is on screen.
      await la.scrollIntoViewIfNeeded();
      await page.waitForTimeout(100);
      const scale = await pt(la);
      const box = (await la.boundingBox())!;
      expect(box.height / scale).toBeLessThanOrEqual(160.5);
      const btns = la.locator('[data-row], [data-break-btn]');
      for (let j = 0; j < (await btns.count()); j += 1) {
        const b = (await btns.nth(j).boundingBox())!;
        expect(b.height / scale).toBeGreaterThanOrEqual(44);
      }
    }
  });
});

test.describe('motion, desktop stage', () => {
  test.beforeEach(({}, info) => test.skip(info.project.name.includes('mobile'), 'desktop only'));

  test('zooms in, draws six real-text callouts, taps Row 36, shows the island and rests on the tapped card', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await sceneBuilt(page);
    const stage = page.locator('[data-stage] [data-phone]');

    // Callouts are real text, in the section, not in the mock.
    const callouts = page.locator('#lock-screen [data-ls-callouts] [data-callout]');
    await expect(callouts).toHaveCount(6);
    for (let i = 0; i < 6; i += 1) await expect(callouts.nth(i)).toContainText(NOTE_TEXT[i]!);

    // Before the tap callout 5 waits: it points at the Undo, which is not there yet.
    await toProgress(page, 0.5, 1400);
    for (let i = 0; i < 6; i += 1) {
      const o = await opacity(callouts.nth(i));
      if (i === 4) expect(o, 'callout 5 before the Undo').toBeLessThan(0.05);
      else expect(o, `callout ${i + 1}`).toBeGreaterThan(0.9);
    }
    expect(await opacity(page.locator('#lock-screen [data-ls-callouts] [data-line-for="5"] [data-dot]'))).toBeLessThan(0.05);

    // After the tap, before the zoom-out: the phone is zoomed and every callout is on screen,
    // none overlapping, and the Undo is there for callout 5.
    await toProgress(page, 0.617, 1400);
    const scale = await scaleOf(stage);
    expect(scale).toBeGreaterThan(1.3);
    await expect(page.locator('[data-stage] [data-screen="lock-1414-tapped"] [data-undo]')).toBeVisible();
    const boxes = [];
    for (let i = 0; i < 6; i += 1) {
      const c = callouts.nth(i);
      expect(Number(await c.evaluate((el) => getComputedStyle(el).opacity))).toBeGreaterThan(0.9);
      const b = (await c.boundingBox())!;
      expect(b.x).toBeGreaterThanOrEqual(0);
      expect(b.x + b.width).toBeLessThanOrEqual(1440);
      expect(b.y).toBeGreaterThan(59);
      expect(b.y + b.height).toBeLessThanOrEqual(900);
      boxes.push(b);
    }
    for (let i = 0; i < boxes.length; i += 1)
      for (let j = i + 1; j < boxes.length; j += 1) {
        const a = boxes[i]!;
        const b = boxes[j]!;
        const apart = a.x + a.width <= b.x || b.x + b.width <= a.x || a.y + a.height <= b.y || b.y + b.height <= a.y;
        expect(apart, `callouts ${i + 1} and ${j + 1} overlap`).toBe(true);
      }
    await expect(page.locator('#lock-screen [data-ls-callouts] [data-ls-ghost]')).toBeVisible();

    // The zoom-out: no leader outlives the card it points at.
    await toProgress(page, 0.645, 1400);
    for (let i = 0; i < 6; i += 1) expect(await opacity(callouts.nth(i)), `callout ${i + 1} at .645`).toBeLessThan(0.02);
    expect(await opacity(page.locator('#lock-screen [data-ls-callouts] [data-ls-ghost]'))).toBeLessThan(0.02);

    // After the tap: Row 37, Row 38, Row 39 and Break; 230 trees.
    await toProgress(page, 0.66, 1400);
    const la = page.locator('[data-stage] [data-screen="lock-1414-tapped"] [data-la]');
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    await expect(la.locator('[data-trees]')).toHaveAttribute('data-odo-text', fmtCount(TAPPED.trees));
    await expect(la).not.toContainText(/clock out/i);

    // The island beat: each state holds long enough to read.
    const island = page.locator('[data-stage] [data-screen="home-1416-island-compact"] [data-island]');
    const compact = island.locator('[data-island-compact]');
    const expanded = island.locator('[data-island-expanded]');
    const controlsBeat = page.locator('#lock-screen .ls-controls-beat');
    await toProgress(page, 0.77, 1400);
    expect(await opacity(compact), 'compact content at .77').toBe(1);
    expect(await opacity(expanded)).toBe(0);
    for (const p of [0.82, 0.855]) {
      await toProgress(page, p, 1400);
      expect(await opacity(expanded), `expanded content at ${p}`).toBe(1);
      expect(await opacity(compact)).toBe(0);
      const w = await island.evaluate((el) => el.getBoundingClientRect().width / el.closest('.screen')!.getBoundingClientRect().width);
      expect(w).toBeGreaterThan(370 / 393);
      // One message at a time: beat 3 (the Action button) waits for the island to collapse.
      expect(await opacity(controlsBeat), `controls beat at ${p}`).toBeLessThan(0.05);
    }
    await expect(expanded).toContainText('North field · Block 2');
    await toProgress(page, 0.95, 1400);
    expect(await opacity(controlsBeat)).toBe(1);
    expect(await opacity(page.locator('#lock-screen [data-controls]'))).toBe(1);
    expect(await opacity(page.locator('#lock-screen [data-ls-footnote]'))).toBe(1);

    // The end: the phone at rest on the lock screen in the tapped state.
    await toProgress(page, 1, 1400);
    const end = await stage.evaluate((el) => getComputedStyle(el).transform);
    expect(['none', 'matrix(1, 0, 0, 1, 0, 0)']).toContain(end);
    expect(Number(await page.locator('[data-stage] [data-screen="lock-1414-tapped"]').evaluate((el) => getComputedStyle(el).opacity))).toBeGreaterThan(0.99);
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    expect(problems).toEqual([]);
  });

  test('keeps the button strip right after a resize mid-section', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    await sceneBuilt(page);
    const la = page.locator('[data-stage] [data-screen="lock-1414-tapped"] [data-la]');
    await toProgress(page, 0.3, 1400);
    expect(await visibleRows(la)).toEqual(['Row 36', 'Row 37', 'Row 38']);
    await page.setViewportSize({ width: 1180, height: 760 });
    await page.waitForTimeout(800);
    await toProgress(page, 0.3, 1600);
    expect(await visibleRows(la)).toEqual(['Row 36', 'Row 37', 'Row 38']);
    await toProgress(page, 0.45, 1400);
    expect(await visibleRows(la)).toEqual(['Row 36', 'Row 37', 'Row 38']);
    await toProgress(page, 0.66, 1400);
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
  });

  test('on a short window zooms the small stage phone on the island, then lets it go', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 600 });
    await page.goto('/');
    await settle(page);
    await sceneBuilt(page);
    const stage = page.locator('[data-stage] [data-phone]');
    await toProgress(page, 0.82, 1400);
    const island = page.locator('[data-stage] [data-screen="home-1416-island-compact"] [data-island]');
    expect(await scaleOf(stage)).toBeGreaterThan(1.3);
    // As wide as on a 1440 × 900 stage phone (330px: the island at 0.79 px per pt).
    const box = (await island.boundingBox())!;
    expect(box.width).toBeGreaterThan(285);
    expect(box.y).toBeGreaterThan(59);
    expect(box.y + box.height).toBeLessThan(600);
    await toProgress(page, 0.95, 1400);
    expect(await scaleOf(stage)).toBeCloseTo(1, 3);
  });

  test('axe: no serious or critical violations mid-scene', async ({ page }) => {
    await page.goto('/');
    await settle(page);
    await sceneBuilt(page);
    await toProgress(page, 0.4, 1200);
    expect(await serious(page)).toEqual([]);
  });
});

test.describe('motion, mobile section phone', () => {
  test.beforeEach(({}, info) => test.skip(!info.project.name.includes('mobile'), 'mobile only'));

  test('never overflows at 375, pins pulse with the numbered notes, and the island beat plays', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await sceneBuilt(page);
    // The headline and intro step aside as the phone zooms over them.
    await toProgress(page, 0.14, 1200);
    expect(await opacity(page.locator('#lock-screen .beat-head'))).toBeLessThan(0.05);
    for (let i = 0; i <= 20; i += 1) {
      await toProgress(page, i / 20, 120);
      expect(await overflow(page), `at progress ${i / 20}`).toBeLessThanOrEqual(0);
    }
    await toProgress(page, 0.34, 1200);
    const card = page.locator('#lock-screen [data-ls-notes]');
    await expect(card).toBeInViewport();
    const pins = page.locator('#lock-screen figure.shot [data-pin]');
    await expect(pins).toHaveCount(6);
    expect(Number(await pins.nth(0).evaluate((el) => getComputedStyle(el).opacity))).toBeGreaterThan(0.9);
    const box = (await pins.nth(0).boundingBox())!;
    expect(box.width).toBeGreaterThan(18);
    expect(box.width).toBeLessThan(28);

    // Pin 5 waits for the Undo it points at.
    await toProgress(page, 0.5, 1200);
    expect(await opacity(pins.nth(4))).toBeLessThan(0.05);
    await toProgress(page, 0.61, 1200);
    expect(await opacity(pins.nth(4))).toBeGreaterThan(0.9);
    await expect(page.locator('#lock-screen [data-ls-tap-card] [data-ls-ghost]')).toBeInViewport();

    // The island close-up: the phone zooms on the island so its text reads.
    const phone = page.locator('#lock-screen figure.shot [data-phone]');
    const island = page.locator('#lock-screen figure.shot [data-screen="home-1416-island-compact"] [data-island]');
    await toProgress(page, 0.77, 1400);
    expect(await scaleOf(phone)).toBeGreaterThan(1.7);
    expect(await opacity(island.locator('[data-island-compact]'))).toBe(1);
    await toProgress(page, 0.83, 1400);
    expect(await opacity(island.locator('[data-island-expanded]'))).toBe(1);
    const ib = (await island.boundingBox())!;
    expect(ib.width).toBeGreaterThan(300);
    expect(ib.x).toBeGreaterThanOrEqual(15);
    expect(ib.x + ib.width).toBeLessThanOrEqual(375 - 15);
    const cap = (await page.locator('#lock-screen .ls-island-beat').boundingBox())!;
    expect(cap.y).toBeGreaterThan(ib.y + ib.height);
    await expect(page.locator('#lock-screen .ls-island-beat')).toBeInViewport();

    await toProgress(page, 1, 1400);
    expect(await scaleOf(phone)).toBeCloseTo(1, 3);
    const la = page.locator('#lock-screen figure.shot [data-screen="lock-1414-tapped"] [data-la]');
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    expect(problems).toEqual([]);
  });
});
