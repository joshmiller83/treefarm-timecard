/**
 * BUILT IN THE OPEN (#open): the honest closing and the footer.
 * Spec: jq '.sections[] | select(.id=="open")' docs/landing/brief.json, and decisions.md #5, #6.
 *
 * Runs in the page projects (desktop 1440 × 900, mobile 375 × 812) against the built site.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';

const REPO = 'https://github.com/joshmiller83/treefarm-timecard';
const DOCS = `${REPO}/tree/main/docs`;
const COMMAND = 'swift test --package-path Packages/TreeFarmKit';
const STACK = ['SwiftUI', 'App Intents', 'ActivityKit', 'Vapor', 'SQLite', 'Cloudflare Tunnel', 'MIT'];

function watch(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  return problems;
}

/** Scrolls #open into view the way a reader arrives: from above, in steps. */
async function arrive(page: Page) {
  const top = await page.evaluate(() => document.getElementById('open')!.getBoundingClientRect().top + scrollY);
  for (const f of [0.6, 0.8, 0.9, 1]) {
    await page.evaluate((y) => window.scrollTo(0, y), Math.max(0, Math.round(top * f - 200)));
    await page.waitForTimeout(150);
  }
  await page.evaluate((y) => window.scrollTo(0, y), Math.max(0, top - 80));
}

/** True when nothing inside #open is faded, offset or clipped (the final state). */
async function finalState(page: Page) {
  return page.locator('#open').evaluate((sec) => {
    const off: string[] = [];
    const els = [sec, ...Array.from(sec.querySelectorAll<HTMLElement | SVGElement>('*'))];
    for (const el of els) {
      const cs = getComputedStyle(el);
      if (el.closest('.sr-only')) continue;
      if (Number(cs.opacity) < 0.999) off.push(`opacity ${cs.opacity}: ${el.outerHTML.slice(0, 70)}`);
      if (cs.visibility === 'hidden') off.push(`hidden: ${el.outerHTML.slice(0, 70)}`);
    }
    const ring = sec.querySelector('[data-icon-ring]');
    const dash = ring ? parseFloat(getComputedStyle(ring).strokeDashoffset || '0') : 0;
    if (Math.abs(dash) > 0.001) off.push(`ring dashoffset ${dash}`);
    return off;
  });
}

for (const mode of ['reduced', 'motion'] as const) {
  test.describe(`${mode}`, () => {
    test.use({ reducedMotion: mode === 'reduced' ? 'reduce' : 'no-preference' });

    test('present, honest and complete in its final state', async ({ page }) => {
      const problems = watch(page);
      await page.goto('/');
      await page.evaluate(() => document.fonts.ready);
      await arrive(page);
      const sec = page.locator('section#open');
      await expect(sec).toHaveAttribute('aria-labelledby', 'open-h');
      await expect(page.getByRole('heading', { level: 2, name: 'Built on a working tree farm. Out in the open.' })).toBeVisible();
      await expect(sec.locator('.eyebrow').first()).toHaveText(/the story so far/i);

      // The three facts, in plain text.
      const text = (await sec.innerText()).replace(/\s+/g, ' ');
      expect(text).toContain('in active development');
      expect(text).toContain('A TestFlight beta is coming');
      expect(text).toContain('Nothing is on the App Store yet');
      expect(text).toContain('open source under the MIT license');
      // Truth rules: no money, no email, no counts or badges.
      expect(text).not.toMatch(/\$|@|App Store badge|download/i);

      // Where it stands: the honest status rail.
      const rail = sec.getByRole('list', { name: 'Where it stands' });
      await expect(rail.getByRole('listitem')).toHaveCount(4);
      await expect(rail).toContainText('In active development');
      await expect(rail).toContainText('Not yet');

      // The stack.
      const chips = sec.getByRole('list', { name: 'The stack' }).getByRole('listitem');
      await expect(chips).toHaveText(STACK);

      // The terminal card says the command to screen readers and on screen.
      const term = sec.locator('[data-open-term]');
      await expect(term).toBeVisible();
      await expect(term.locator('.sr-only')).toHaveText(COMMAND);
      await expect(term.locator('[data-term-cmd]')).toHaveText(COMMAND);

      // One clear call to action; every link in the section goes to the repo.
      const primary = sec.getByRole('link', { name: 'Follow along on GitHub' });
      const docs = sec.getByRole('link', { name: 'Read the docs' });
      await expect(primary).toHaveAttribute('href', REPO);
      await expect(docs).toHaveAttribute('href', DOCS);
      await primary.scrollIntoViewIfNeeded();
      await expect(primary).toBeVisible();
      await expect(docs).toBeVisible();
      for (const href of await sec.locator('a[href]').evaluateAll((as) => as.map((a) => (a as HTMLAnchorElement).href)))
        expect(href.startsWith(REPO)).toBe(true);
      await expect(sec.getByText('Follow along on GitHub for news about the beta.')).toBeVisible();

      // The icon is decorative and complete.
      await expect(sec.locator('[data-app-icon]')).toHaveAttribute('aria-hidden', 'true');

      // The stage phone is released here (desktop with motion).
      if (mode === 'motion' && (page.viewportSize()?.width ?? 0) >= 900) {
        await expect.poll(() => page.locator('[data-stage]').evaluate((s) => getComputedStyle(s).opacity)).toBe('0');
      }

      // Final state: nothing faded, the ring drawn, the command typed.
      await expect.poll(() => finalState(page), { timeout: 8000 }).toEqual([]);
      expect(problems).toEqual([]);
    });

    test('focus runs from the section buttons into the footer', async ({ page, browserName }) => {
      await page.goto('/');
      await arrive(page);
      const docs = page.locator('#open').getByRole('link', { name: 'Read the docs' });
      await docs.focus();
      await page.keyboard.press(browserName === 'webkit' ? 'Alt+Tab' : 'Tab');
      const inFooter = await page.evaluate(() => !!document.activeElement?.closest('body > footer'));
      expect(inFooter).toBe(true);
    });
  });
}

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('no overflow at 375 and nothing wider than the viewport', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    await page.locator('#open').scrollIntoViewIfNeeded();
    const wide = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const nodes = [document.getElementById('open')!, document.querySelector('body > footer')!];
      return nodes
        .flatMap((n) => [n, ...Array.from(n.querySelectorAll('*'))])
        .filter((el) => !el.closest('.sr-only'))
        .map((el) => ({ el: el.outerHTML.slice(0, 60), r: el.getBoundingClientRect() }))
        .filter(({ r }) => r.width > 0 && (r.right > vw + 0.5 || r.left < -0.5))
        .map(({ el, r }) => `${Math.round(r.left)}–${Math.round(r.right)}: ${el}`);
    });
    expect(wide).toEqual([]);
    expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(0);
  });

  test('axe: no serious or critical violations in the section and footer', async ({ page }) => {
    await page.goto('/');
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    await page.locator('#open').scrollIntoViewIfNeeded();
    const results = await new AxeBuilder({ page })
      .include('#open')
      .include('body > footer')
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
      .analyze();
    const bad = results.violations
      .filter((v) => v.impact === 'serious' || v.impact === 'critical')
      .map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`);
    expect(bad).toEqual([]);
  });

  test('the footer: a contentinfo landmark with the required lines and no email', async ({ page }) => {
    await page.goto('/');
    const footer = page.getByRole('contentinfo');
    await expect(footer).toHaveCount(1);
    await expect(footer).toContainText('Tree Farm Time Card · Open source');
    await expect(footer).toContainText('Screens on this page are recreations of the app as it’s being built.');
    await expect(footer).toContainText('This page has no trackers and no cookies.');
    await expect(footer).toContainText('trademarks of Apple Inc.');
    expect(await footer.innerText()).not.toContain('@');
  });
});

test.describe('motion', () => {
  test.use({ reducedMotion: 'no-preference' });

  test('arriving straight at #open shows the finished section at once', async ({ page }) => {
    const problems = watch(page);
    await page.goto('/#open');
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(600);
    expect(await finalState(page)).toEqual([]);
    expect(problems).toEqual([]);
  });

  test('the copy button copies the command', async ({ page, browserName, context }) => {
    test.skip(browserName !== 'chromium', 'clipboard permissions are Chromium-only in Playwright');
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.goto('/');
    await arrive(page);
    const copy = page.locator('#open').getByRole('button', { name: /copy/i });
    await copy.click();
    await expect(page.locator('#open [data-copy-status]')).toHaveText('Copied');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(COMMAND);
  });
});
