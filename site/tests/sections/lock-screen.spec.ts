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

/** Scrolls so the section's track is at scroll progress `p` (0–1). */
async function toProgress(page: Page, p: number, wait = 900) {
  await page.evaluate((p) => {
    const track = document.querySelector<HTMLElement>('#lock-screen .track')!;
    const top = track.getBoundingClientRect().top + scrollY;
    window.scrollTo(0, Math.round(top + p * (track.offsetHeight - innerHeight)));
  }, p);
  await page.waitForTimeout(wait);
}

/** Waits until this section's scene has been built (it marks the section). */
async function sceneBuilt(page: Page) {
  await toProgress(page, 0, 200);
  await expect(page.locator('#lock-screen[data-ls-scene="built"]')).toHaveCount(1, { timeout: 8000 });
}

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
    await expect(crops.nth(0)).toHaveAttribute('aria-label', /compact.*Row 37.*6:29/i);
    await expect(crops.nth(1)).toHaveAttribute('aria-label', /expanded.*North field.*Block 2.*6:29:10/i);

    // Figure 3: the controls, with the qualifiers and the 8-hour footnote.
    await expect(sec.locator('[data-controls]')).toBeVisible();
    const foot = sec.locator('[data-ls-footnote]');
    await expect(foot).toContainText('A Live Activity can stay up for 8 hours. Time Card reminds you before it runs out.');
    await expect(foot).toContainText('The Action button is on iPhones that have one.');
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

    // Mid-callouts: the phone is zoomed and every callout is on screen, none overlapping.
    await toProgress(page, 0.52, 1400);
    const scale = await stage.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).a);
    expect(scale).toBeGreaterThan(1.3);
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

    // After the tap: Row 37, Row 38, Row 39 and Break; 230 trees.
    await toProgress(page, 0.66, 1400);
    const la = page.locator('[data-stage] [data-screen="lock-1414-tapped"] [data-la]');
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    await expect(la.locator('[data-trees]')).toHaveAttribute('data-odo-text', fmtCount(TAPPED.trees));
    await expect(la).not.toContainText(/clock out/i);

    // The island beat: unlocked, the island expanded.
    await toProgress(page, 0.84, 1400);
    const island = page.locator('[data-stage] [data-screen="home-1416-island-compact"] [data-island]');
    const w = await island.evaluate((el) => el.getBoundingClientRect().width / el.closest('.screen')!.getBoundingClientRect().width);
    expect(w).toBeGreaterThan(330 / 393);
    await expect(island.locator('[data-island-expanded]')).toContainText('North field · Block 2');

    // The end: the phone at rest on the lock screen in the tapped state.
    await toProgress(page, 1, 1400);
    const end = await stage.evaluate((el) => getComputedStyle(el).transform);
    expect(['none', 'matrix(1, 0, 0, 1, 0, 0)']).toContain(end);
    expect(Number(await page.locator('[data-stage] [data-screen="lock-1414-tapped"]').evaluate((el) => getComputedStyle(el).opacity))).toBeGreaterThan(0.99);
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    expect(problems).toEqual([]);
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

    await toProgress(page, 0.57, 1200);
    await expect(page.locator('#lock-screen [data-ls-tap-card] [data-ls-ghost]')).toBeInViewport();

    await toProgress(page, 1, 1400);
    const la = page.locator('#lock-screen figure.shot [data-screen="lock-1414-tapped"] [data-la]');
    expect(await visibleRows(la)).toEqual(TAPPED.rows.map((r) => `Row ${r}`));
    expect(problems).toEqual([]);
  });
});
