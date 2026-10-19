/**
 * HERO · 7:02 AM · Clock in. The section's own checks (projects 'desktop' 1440 × 900 and
 * 'mobile' 375 × 812). Spec: jq '.sections[] | select(.id=="hero")' docs/landing/brief.json
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const LABEL =
  'iPhone lock screen at 7:02 AM. Siri says: Clocked in at 7:02. You’re on block 2, row 14. ' +
  'The Time Card Live Activity shows On the clock, North field, Block 2, 0 trees this shift, ' +
  'and buttons for row 14, row 15, row 16 and Break.';
const REPO = 'https://github.com/joshmiller83/treefarm-timecard';
const STATUS = 'In development · TestFlight beta coming';

const isMobile = (page: Page) => (page.viewportSize()?.width ?? 1440) < 900;

/** Collects console errors and page errors. */
function watch(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text()}`));
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  return problems;
}

/** Records when html.hero-intro comes and goes (ms since navigation start). */
async function recordIntro(page: Page) {
  await page.addInitScript(() => {
    const w = window as unknown as { __heroIntro: { on?: number; off?: number } };
    w.__heroIntro = {};
    // <html> may not exist yet when this runs: watch the document for it.
    new MutationObserver(() => {
      const on = !!document.documentElement?.classList.contains('hero-intro');
      if (on && w.__heroIntro.on === undefined) w.__heroIntro.on = performance.now();
      if (!on && w.__heroIntro.on !== undefined && w.__heroIntro.off === undefined) w.__heroIntro.off = performance.now();
    }).observe(document, { attributes: true, subtree: true, attributeFilter: ['class'] });
  });
}

/** Waits until the motion core has built the hero scene. */
async function booted(page: Page) {
  await page.waitForFunction(() => document.documentElement.classList.contains('motion-ready') && !document.documentElement.classList.contains('intro-wait'), null, {
    timeout: 8000,
  });
}

/** Waits for the load sequence to finish (on mobile, after bringing the phone on screen). */
async function introDone(page: Page) {
  await booted(page);
  if (isMobile(page)) await page.locator('#hero [data-hero-device]').scrollIntoViewIfNeeded();
  await page.waitForFunction(() => document.documentElement.dataset.heroIntro === 'done', null, { timeout: 8000 });
}

const opacity = (page: Page, sel: string) => page.locator(sel).first().evaluate((el) => Number(getComputedStyle(el).opacity));

test.describe('the hero', () => {
  test('says what it is, the hook, the honest status and where to go', async ({ page }) => {
    await page.goto('/');
    const hero = page.locator('#hero');
    await expect(hero.locator('h1')).toHaveText('Keep your gloves on.');
    await expect(hero.locator('.eyebrow')).toHaveText(/Time Card · For Christmas tree trimmers/i);
    await expect(hero.locator('.hero-body')).toContainText('iPhone time card for people who shape Christmas trees');
    await expect(hero.locator('.hero-body')).toContainText('with your phone locked in your pocket');
    // The sentences are separate spans (blocks on phones): their spaces must survive.
    await expect(hero.locator('.hero-body')).toContainText('Christmas trees. Clock in');
    await expect(hero.locator('.hero-body')).toContainText('in your pocket. The lock screen does the rest.');
    await expect(hero.locator('.pill-status')).toHaveText(STATUS);
    const gh = hero.getByRole('link', { name: 'Follow along on GitHub' });
    await expect(gh).toHaveAttribute('href', REPO);
    await expect(hero.getByRole('link', { name: 'Walk through a shift' })).toHaveAttribute('href', '#voice');
    await expect(hero.locator('.hero-fine')).toHaveText('Open source, MIT licensed. Not on the App Store yet.');
    // Truth: nothing about prices, stores or ratings beyond the fine print.
    const text = await hero.innerText();
    expect(text).not.toMatch(/\$|download on|get it on|rating|★/i);
  });

  test('labels the phone with the brief’s sentence and hides the mock from screen readers', async ({ page }) => {
    await page.goto('/');
    const phone = page.locator('#hero [data-phone][role="img"]');
    await expect(phone).toHaveCount(1);
    await expect(phone).toHaveAttribute('aria-label', LABEL);
    await expect(phone.locator('.phone-body')).toHaveAttribute('aria-hidden', 'true');
    // The spoken lines are decoration; the caption carries the words.
    for (const said of await page.locator('#hero [data-said]').all()) await expect(said).toHaveAttribute('aria-hidden', 'true');
    await expect(page.locator('#hero figcaption')).toContainText('You say “Clock in with Time Card.”');
    // One final layer (it sits in the stage phone on desktop with motion).
    await expect(page.locator('[data-screen="lock-0702-clockin"]')).toHaveAttribute('data-final', '');
  });

  test('plays the load sequence without errors and lands on the rest pose', async ({ page }) => {
    const problems = watch(page);
    await recordIntro(page);
    await page.goto('/');
    await introDone(page);
    const t = await page.evaluate(() => (window as unknown as { __heroIntro: { on?: number; off?: number } }).__heroIntro);
    expect(t.on, 'the sequence started').toBeDefined();
    expect(t.off, 'the sequence finished').toBeDefined();
    // The brief allows 3.1 s; a little slack for a busy test machine. Mobile's phone half waits for the scroll.
    if (!isMobile(page)) expect(t.off! - t.on!).toBeLessThan(3100 + 600);
    // Rest pose: the lock screen, its clock and the Live Activity; Siri's card and glow have gone.
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-la]')).toBe(1);
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-lock] > [data-clock]')).toBe(1);
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-snippet]')).toBe(0);
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-glow]')).toBe(0);
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-dim]')).toBe(0);
    for (const sel of ['#hero .eyebrow', '#hero .hero-body', '#hero .hero-cta', '#hero .hero-fine']) expect(await opacity(page, sel), sel).toBe(1);
    const words = page.locator(`#hero [data-said="${isMobile(page) ? 'figure' : 'stage'}"] [data-said-word]`);
    await expect(words).toHaveCount(6);
    for (const w of await words.all()) expect(await w.evaluate((el) => Number(getComputedStyle(el).opacity))).toBe(1);
    await expect(page.locator('[data-screen="lock-0702-clockin"] [data-la] [data-pill-text="clock"]')).toHaveText('On the clock');
    expect(problems).toEqual([]);
  });

  test('never hides the H1 (the LCP element), not even during the sequence', async ({ page }) => {
    await page.goto('/');
    const samples: number[] = [];
    for (let i = 0; i < 16; i += 1) {
      samples.push(await opacity(page, '#hero h1'));
      await page.waitForTimeout(200);
    }
    expect(Math.min(...samples)).toBe(1);
    await expect(page.locator('#hero h1')).toBeVisible();
  });

  test('has no serious accessibility problems once it settles', async ({ page }) => {
    await page.goto('/');
    await introDone(page);
    await page.evaluate(() => scrollTo(0, 0));
    await page.waitForTimeout(400);
    const results = await new AxeBuilder({ page }).include('#hero').withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze();
    const serious = results.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`);
    expect(serious).toEqual([]);
  });

  test('skips the sequence when Pause motion is on', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('tf-pause', '1'));
    await recordIntro(page);
    await page.goto('/');
    await booted(page);
    await page.waitForTimeout(200);
    const t = await page.evaluate(() => (window as unknown as { __heroIntro: { on?: number } }).__heroIntro);
    expect(t.on).toBeUndefined();
    if (isMobile(page)) await page.locator('#hero [data-hero-device]').scrollIntoViewIfNeeded();
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-la]')).toBe(1);
    expect(await opacity(page, '#hero .hero-body')).toBe(1);
  });

  test('ends the sequence at once when Pause motion is pressed', async ({ page }) => {
    await page.goto('/');
    await booted(page);
    await page.waitForTimeout(300);
    await page.locator('[data-pause-toggle]').click();
    await expect(page.locator('html')).toHaveAttribute('data-hero-intro', 'done');
    if (isMobile(page)) await page.locator('#hero [data-hero-device]').scrollIntoViewIfNeeded();
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-la]')).toBe(1);
    expect(await opacity(page, '#hero .hero-fine')).toBe(1);
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-snippet]')).toBe(0);
    // Restore for the next test in this worker.
    await page.evaluate(() => localStorage.removeItem('tf-pause'));
  });

  test('has no horizontal overflow at 320 and 375', async ({ page }) => {
    for (const width of [320, 375]) {
      await page.setViewportSize({ width, height: 700 });
      await page.goto('/');
      await booted(page);
      const h = await page.locator('#hero').evaluate((el) => el.getBoundingClientRect().bottom + scrollY);
      for (let y = 0; y <= h; y += 240) {
        await page.evaluate((top) => scrollTo(0, top), y);
        await page.waitForTimeout(60);
        expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth), `${width}px at ${y}`).toBeLessThanOrEqual(0);
      }
    }
  });
});

test.describe('the hero on a phone', () => {
  test.beforeEach(({ page }) => test.skip(!isMobile(page), 'mobile layout'));

  test('puts the H1, body, pill and primary button above the fold at 375 × 667', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto('/');
    for (const sel of ['#hero h1', '#hero .hero-body', '#hero .pill-status', '#hero .hero-gh']) {
      const box = await page.locator(sel).boundingBox();
      expect(box, sel).not.toBeNull();
      expect(box!.y + box!.height, sel).toBeLessThanOrEqual(667);
    }
    // Full-width buttons, 48px tall, stacked.
    const gh = await page.locator('#hero .hero-gh').boundingBox();
    const walk = await page.locator('#hero .hero-walk').boundingBox();
    expect(gh!.height).toBeGreaterThanOrEqual(48);
    expect(walk!.height).toBeGreaterThanOrEqual(48);
    expect(gh!.width).toBeGreaterThan(375 - 2 * 16 - 1);
    expect(walk!.y).toBeGreaterThan(gh!.y + gh!.height - 1);
  });

  test('waits to play the phone’s half until the phone is on screen', async ({ page }) => {
    await page.goto('/');
    await booted(page);
    await page.waitForTimeout(1200);
    // The copy has played; the phone below the fold is still waiting.
    expect(await opacity(page, '#hero .hero-body')).toBe(1);
    expect(await opacity(page, '#hero [data-phone]')).toBe(0);
    await expect(page.locator('html')).toHaveAttribute('data-hero-intro', 'waiting');
    await expect(page.locator('html')).not.toHaveClass(/hero-intro/);
    await page.locator('#hero [data-hero-device]').scrollIntoViewIfNeeded();
    await page.waitForFunction(() => document.documentElement.dataset.heroIntro === 'done', null, { timeout: 6000 });
    expect(await opacity(page, '#hero [data-phone]')).toBe(1);
    expect(await opacity(page, '[data-screen="lock-0702-clockin"] [data-la]')).toBe(1);
  });

  test('shows a phone at least half the screen tall, with the spoken line above it', async ({ page }) => {
    await page.goto('/');
    const phone = await page.locator('#hero [data-phone]').boundingBox();
    const said = await page.locator('#hero [data-said="figure"]').boundingBox();
    expect(phone!.height).toBeGreaterThan(812 * 0.55);
    expect(said!.y + said!.height).toBeLessThanOrEqual(phone!.y);
    expect(Math.abs(said!.x + said!.width / 2 - (phone!.x + phone!.width / 2))).toBeLessThan(4);
  });
});

test.describe('the hero on the stage (desktop)', () => {
  test.beforeEach(({ page }) => test.skip(isMobile(page), 'desktop layout'));

  for (const [w, h] of [
    [1024, 768],
    [1280, 800],
    [1440, 900],
    [1920, 1080],
  ] as const) {
    test(`floats the spoken line beside the phone without touching the copy at ${w} × ${h}`, async ({ page }) => {
      await page.setViewportSize({ width: w, height: h });
      await page.goto('/');
      await introDone(page);
      const said = page.locator('#hero [data-said="stage"]');
      await expect(said).toBeVisible();
      const s = (await said.boundingBox())!;
      const phone = (await page.locator('[data-stage] [data-phone]').boundingBox())!;
      // Right edge 28px left of the phone, 18% down the frame.
      expect(phone.x - (s.x + s.width)).toBeGreaterThanOrEqual(20);
      expect(phone.x - (s.x + s.width)).toBeLessThanOrEqual(40);
      // No overlap with the eyebrow, the H1's lines or the body.
      const words = await page.locator('#hero [data-said="stage"] .hero-w').evaluateAll((els) =>
        els.flatMap((el) => Array.from(el.getClientRects()).map((r) => ({ x: r.left, y: r.top, w: r.width, h: r.height }))),
      );
      const copy = await page.locator('#hero .beat-head').evaluate((head) => {
        const rects: { x: number; y: number; w: number; h: number }[] = [];
        for (const el of head.querySelectorAll('.eyebrow, h1, .hero-body')) {
          const range = document.createRange();
          range.selectNodeContents(el);
          for (const r of Array.from(range.getClientRects())) rects.push({ x: r.left, y: r.top, w: r.width, h: r.height });
        }
        return rects;
      });
      const hit = (a: { x: number; y: number; w: number; h: number }, b: typeof a) =>
        a.x < b.x + b.w + 16 && b.x < a.x + a.w + 16 && a.y < b.y + b.h && b.y < a.y + a.h;
      for (const word of words) for (const c of copy) expect(hit(word, c), JSON.stringify({ word, c })).toBe(false);
      // The line is Display M or smaller (never competes with the H1), and at least 20px.
      const fs = await said.locator('.hero-said-line').evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
      expect(fs).toBeGreaterThanOrEqual(20);
      expect(fs).toBeLessThanOrEqual(44);
    });
  }

  test('scrubs: the copy lifts away, the rows sink and the shift ribbon arrives', async ({ page }) => {
    await page.goto('/');
    await introDone(page);
    expect(await opacity(page, 'nav.shift .tag-ride')).toBe(0);
    const track = await page.locator('#hero .track').evaluate((el) => {
      const top = el.getBoundingClientRect().top + scrollY;
      return { top, end: top + (el as HTMLElement).offsetHeight - innerHeight };
    });
    await page.evaluate((y) => scrollTo(0, y), track.end);
    await page.waitForTimeout(1500);
    expect(await opacity(page, '#hero .beat-head')).toBeLessThan(0.05);
    expect(await opacity(page, '#hero [data-said="stage"]')).toBeLessThan(0.05);
    expect(await opacity(page, 'nav.shift .tag-ride')).toBeGreaterThan(0.95);
    await expect(page.locator('nav.shift .tag-ride')).toHaveText('7:02 AM · Clock in');
    // The near rows sink 8vh (the far ones less: depth).
    const sink = (band: string) =>
      page.locator(`#hero [data-band="${band}"]`).evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42);
    expect(await sink('near')).toBeCloseTo(900 * 0.08, 0);
    expect(await sink('far')).toBeLessThan(await sink('near'));
    expect(await opacity(page, '#hero [data-band="far"] [data-band-fade]')).toBeCloseTo(0.3, 1);
    // Rest pose for the voice section: the stage phone is upright and lit.
    const phone = page.locator('[data-stage] [data-phone]');
    expect(await phone.evaluate((el) => getComputedStyle(el).transform)).toMatch(/^(none|matrix\(1, 0, 0, 1, 0, 0\))$/);
  });
});

test.describe('the hero with reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('shows the final state at once: Siri’s card on top, the activity below, a still glow', async ({ page }) => {
    const problems = watch(page);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    const layer = page.locator('#hero [data-screen="lock-0702-clockin"]');
    await layer.scrollIntoViewIfNeeded();
    await expect(layer.locator('[data-snippet]')).toBeVisible();
    await expect(layer.locator('[data-snippet-text]')).toHaveText('Clocked in at 7:02. You’re on block 2, row 14.');
    await expect(layer.locator('[data-la]')).toBeVisible();
    await expect(layer.locator('[data-la] .la-timer')).toHaveAttribute('data-odo-text', '0:00:00');
    await expect(layer.locator('[data-la] [data-pill-text="clock"]')).toHaveText('On the clock');
    for (const r of [14, 15, 16]) await expect(layer.locator(`[data-la] [data-row="${r}"]`)).toHaveText(`Row ${r}`);
    await expect(layer.locator('[data-glow]')).toHaveAttribute('data-glow-mode', 'auto');
    expect(await opacity(page, '#hero [data-glow]')).toBeLessThan(1);
    // The snippet sits at the top of the screen, the activity at the bottom.
    const snip = (await layer.locator('[data-snippet]').boundingBox())!;
    const la = (await layer.locator('[data-la]').boundingBox())!;
    expect(snip.y + snip.height).toBeLessThan(la.y);
    // The spoken line is static and whole; the caption is visible.
    await expect(page.locator('#hero [data-said="figure"]')).toBeVisible();
    for (const w of await page.locator('#hero [data-said="figure"] [data-said-word]').all()) expect(await w.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    await expect(page.locator('#hero figcaption')).toBeVisible();
    // Nothing in the copy waits to fade in.
    for (const sel of ['#hero .eyebrow', '#hero .hero-body', '#hero .pill-status', '#hero .hero-cta', '#hero .hero-fine']) expect(await opacity(page, sel), sel).toBe(1);
    // No parallax, no ribbon fill.
    await expect(page.locator('nav.shift .ribbon-fill')).toBeHidden();
    expect(problems).toEqual([]);
  });
});
