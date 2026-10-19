/**
 * BUILT IN THE OPEN (#open): the honest closing and the footer.
 * Spec: jq '.sections[] | select(.id=="open")' docs/landing/brief.json, and decisions.md #5, #6.
 *
 * Runs in the page projects (desktop 1440 × 900, mobile 375 × 812) against the built site.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';

const REPO = 'https://github.com/joshmiller83/treefarm-timecard';
const DOCS = `${REPO}/tree/main/docs`;
const COMMAND = 'swift test --package-path Packages/TreeFarmKit';
const STACK = ['SwiftUI', 'App Intents', 'ActivityKit', 'Vapor', 'SQLite', 'Cloudflare Tunnel', 'MIT'];

/** Collects page errors, console errors, and GSAP's warnings (e.g. "GSAP target not found"). */
function watch(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
    if (m.type() === 'warning' && /gsap/i.test(m.text())) problems.push(`warning: ${m.text()}`);
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

/** Waits until an element has faded all the way in and stopped moving (its reveal is done). */
async function settled(loc: Locator) {
  await loc.scrollIntoViewIfNeeded();
  await expect
    .poll(
      () =>
        loc.evaluate(async (el) => {
          const box = () => el.getBoundingClientRect().top;
          const a = box();
          await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
          let o = 1;
          for (let n: Element | null = el; n; n = n.parentElement) o *= Number(getComputedStyle(n).opacity);
          return o === 1 && box() === a;
        }),
      { timeout: 10_000 },
    )
    .toBe(true);
}

/**
 * What inside #open is not in its final state: faded, hidden, shrunk (a dot or a tick still at
 * scale 0), the rail's line not filled, or the ring not drawn. `inView` limits the check to
 * what is on screen. Transient layers (the icon's one-time sheen, the ripple) rest at opacity 0
 * by design.
 */
async function finalState(page: Page, inView = false) {
  return page.locator('#open').evaluate((sec, inView) => {
    const off: string[] = [];
    const els = [sec, ...Array.from(sec.querySelectorAll<HTMLElement | SVGElement>('*'))];
    const scale = (el: Element, cs: CSSStyleDeclaration) => {
      // GSAP writes an SVG element's transform as its attribute, which some engines do not
      // report as the computed CSS transform.
      const own = el instanceof SVGGraphicsElement ? el.transform.baseVal.consolidate()?.matrix : undefined;
      const m = cs.transform !== 'none' ? new DOMMatrix(cs.transform) : (own ?? new DOMMatrix());
      return Math.min(Math.hypot(m.a, m.b), Math.hypot(m.c, m.d));
    };
    for (const el of els) {
      const cs = getComputedStyle(el);
      if (el.closest('.sr-only, [data-transient]')) continue;
      const r = el.getBoundingClientRect();
      if (inView && (r.top >= innerHeight || r.bottom <= 0)) continue;
      const tag = el.outerHTML.slice(0, 70);
      if (Number(cs.opacity) < 0.999) off.push(`opacity ${cs.opacity}: ${tag}`);
      if (cs.visibility === 'hidden') off.push(`hidden: ${tag}`);
      const k = scale(el, cs);
      // The rail's fill rests at its own scale (the share of the line up to "now").
      if (el.matches('[data-rail-fill]')) {
        if (k < 0.3) off.push(`rail fill ${k.toFixed(3)}`);
      } else if (cs.display !== 'none' && k < 0.999) off.push(`scale ${k.toFixed(3)}: ${tag}`);
    }
    const ring = sec.querySelector('[data-icon-ring]');
    const dash = ring ? parseFloat(getComputedStyle(ring).strokeDashoffset || '0') : 0;
    if (Math.abs(dash) > 0.001) off.push(`ring dashoffset ${dash}`);
    return off;
  }, inView);
}

/** True when every character of `phrase` inside the element is set on one line. */
async function onOneLine(loc: Locator, phrase: string) {
  return loc.evaluate((el, phrase) => {
    const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
    const nodes: Text[] = [];
    for (let n = walker.nextNode(); n; n = walker.nextNode()) nodes.push(n as Text);
    const text = nodes.map((n) => n.data).join('').replace(/\s/g, ' ');
    const start = text.indexOf(phrase);
    if (start < 0) return false;
    const tops: number[] = [];
    let pos = 0;
    for (const n of nodes) {
      for (let i = 0; i < n.length; i++) {
        const at = pos + i;
        if (at < start || at >= start + phrase.length || text[at] === ' ') continue;
        const r = document.createRange();
        r.setStart(n, i);
        r.setEnd(n, i + 1);
        tops.push(r.getBoundingClientRect().top);
      }
      pos += n.length;
    }
    return tops.length > 0 && Math.max(...tops) - Math.min(...tops) < 8;
  }, phrase);
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
      const head = page.getByRole('heading', { level: 2, name: 'Built on a working tree farm. Out in the open.' });
      await expect(head).toBeVisible();
      await expect(sec.locator('.eyebrow').first()).toHaveText(/the story so far/i);

      // The three facts, in plain text.
      const status = sec.locator('p', { hasText: 'active development' });
      await expect(status).toHaveText('It’s in active development. A TestFlight beta is coming. Nothing is on the App Store yet.');
      await expect(status).toBeVisible();
      await expect(sec).toContainText('open source under the MIT license');
      // Truth rules: no money, no email, no counts or badges.
      const text = ((await sec.textContent()) ?? '').replace(/\s+/g, ' ');
      expect(text).not.toMatch(/\$|@|App Store badge|download/i);

      // Where it stands: the honest status rail.
      const rail = sec.getByRole('list', { name: 'Where it stands' });
      await expect(rail.getByRole('listitem')).toHaveCount(4);
      await expect(rail).toContainText('In active development');
      await expect(rail).toContainText('Not yet'); // said to screen readers; on screen the open ring says it

      // The stack.
      const chips = sec.getByRole('list', { name: 'The stack' }).getByRole('listitem');
      await expect(chips).toHaveText(STACK);

      // The terminal card says the command to screen readers and on screen.
      const term = sec.locator('[data-open-term]');
      await expect(term).toBeVisible();
      await expect(term.locator('[data-term-sr]')).toHaveText(COMMAND);
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

      // Final state once the reader has scrolled past it all: nothing faded, the ring drawn,
      // the command typed.
      await page.locator('body > footer').scrollIntoViewIfNeeded();
      await expect.poll(() => finalState(page), { timeout: 10_000 }).toEqual([]);
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

  test('the headline never splits “Out in the open.”', async ({ page }) => {
    const head = page.locator('#open-h');
    await page.goto('/');
    // Off-screen sections skip rendering (content-visibility), and their geometry can be stale.
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    await page.evaluate(() => document.fonts.ready);
    for (const width of [320, 375, 768, 1024, 1280, 1440]) {
      await page.setViewportSize({ width, height: 900 });
      await head.scrollIntoViewIfNeeded();
      await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
      expect(await onOneLine(head, 'Out in the open.'), `at ${width}px`).toBe(true);
    }
  });

  test('the header stays readable over this light chapter (static desktop page)', async ({ page }) => {
    test.skip((page.viewportSize()?.width ?? 0) < 900, 'the static header bar is desktop-only');
    // Deferred to Header.astro's owner: the static desktop bar keeps its dark background while
    // the light theme switches its text to ink. Remove this line once that fix lands.
    test.fail(true, 'Header.astro: html:not(.motion) .site-header outranks [data-theme=light]');
    await page.goto('/');
    await page.locator('#open').evaluate((s) => window.scrollTo(0, s.getBoundingClientRect().top + scrollY + 200));
    const header = page.locator('[data-header]');
    await expect(header).toHaveAttribute('data-theme', 'light');
    await page.waitForTimeout(400); // the bar's colour transition
    // WCAG contrast of the wordmark and the GitHub link on the bar, composited over the light
    // chapter (#ECF1EC) that scrolls under it.
    const ratios = await header.evaluate((h) => {
      const rgba = (c: string) => (c.match(/[\d.]+/g) ?? []).map(Number);
      const lum = ([r, g, b]: number[]) => {
        const f = (v: number) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
        return 0.2126 * f(r!) + 0.7152 * f(g!) + 0.0722 * f(b!);
      };
      const [r, g, b, a = 1] = rgba(getComputedStyle(h).backgroundColor);
      const under = [0xec, 0xf1, 0xec];
      const bar = [r!, g!, b!].map((v, i) => v * a + under[i]! * (1 - a));
      return ['.brand', '.gh'].map((sel) => {
        const fg = rgba(getComputedStyle(h.querySelector(sel)!).color);
        const [l1, l2] = [lum(fg), lum(bar)].sort((x, y) => y - x);
        return `${sel} ${((l1! + 0.05) / (l2! + 0.05)).toFixed(2)}`;
      });
    });
    for (const r of ratios) expect(Number(r.split(' ')[1]), r).toBeGreaterThanOrEqual(4.5);
  });

  test('no overflow at 375 and nothing wider than the viewport', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    await page.locator('#open').scrollIntoViewIfNeeded();
    const wide = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const nodes = [document.getElementById('open')!, document.querySelector('body > footer')!];
      return nodes
        .flatMap((n) => [n, ...Array.from(n.querySelectorAll('*'))])
        .filter((el) => !el.closest('.sr-only, [data-transient]'))
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
    // Whatever is on screen is already final: no flash of hidden copy, no replayed intro.
    expect(await finalState(page, true)).toEqual([]);
    expect(problems).toEqual([]);
  });

  // A reader who lands with a part just above the bottom edge (below its trigger line, but on
  // screen) sees it finished, not half-built until they scroll a little more.
  for (const part of ['[data-open-rail]', '[data-open-term]', '[data-open-icon]', '#open-h'] as const) {
    test(`landing with ${part} near the bottom edge shows it finished`, async ({ page }) => {
      const problems = watch(page);
      await page.goto('/');
      await page.evaluate(async () => {
        await document.fonts.ready;
        await (window as unknown as { __tf?: { ready: Promise<void> } }).__tf?.ready;
      });
      // Jump (no smooth scroll) so the part's top sits at 95% of the viewport; this builds the scene.
      await page.locator(part).evaluate((el) => {
        document.documentElement.style.scrollBehavior = 'auto';
        window.scrollTo(0, el.getBoundingClientRect().top + scrollY - innerHeight * 0.95);
      });
      await page.waitForTimeout(1200);
      const top = await page.locator(part).evaluate((el) => el.getBoundingClientRect().top / innerHeight);
      expect(top).toBeGreaterThan(0.86);
      expect(top).toBeLessThan(1);
      expect(await finalState(page, true)).toEqual([]);
      expect(problems).toEqual([]);
    });
  }

  test('with Pause motion on, every part arrives finished', async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem('tf-pause', '1'));
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await arrive(page);
    await page.waitForTimeout(250);
    expect(await finalState(page, true)).toEqual([]);
  });

  test('pressing a button here never jumps the page (so the click lands)', async ({ page, browserName }) => {
    await page.goto('/');
    await arrive(page);
    const primary = page.locator('#open').getByRole('link', { name: 'Follow along on GitHub' });
    await settled(primary);
    const box = (await primary.boundingBox())!;
    const before = await page.evaluate(() => scrollY);
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(200);
    expect(await page.evaluate(() => scrollY)).toBe(before);
    // Chromium and Firefox focus a link on mousedown (that is what used to jump); WebKit does not.
    if (browserName !== 'webkit') await expect(primary).toBeFocused();
  });

  test('the copy button copies the command', async ({ page, browserName, context }) => {
    test.skip(browserName !== 'chromium', 'clipboard permissions are Chromium-only in Playwright');
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.goto('/');
    await arrive(page);
    const copy = page.locator('#open').getByRole('button', { name: /copy/i });
    await settled(copy); // the card fades up 16px as it arrives
    await copy.click();
    await expect(page.locator('#open [data-copy-status]')).toHaveText('Copied');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(COMMAND);
  });
});
