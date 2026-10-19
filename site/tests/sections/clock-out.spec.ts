/**
 * CLOCK OUT (section team). The exchange at dusk, the lights-up and the paper time card.
 * Runs against the built site like tests/e2e (projects 'desktop' 1440 × 900 and 'mobile' 375 × 812).
 * The paper's lift is also checked in WebKit (launched here when it is installed).
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, webkit, type Page } from '@playwright/test';
import { BEAT_AT, DESK, MOB } from '../../src/sections/clock-out/model.ts';

const ASK = 'You’ve worked 8 hours 30 minutes today. Clock out?';
const ANSWER = 'Clocked out at 4:31. 8 hours 30 minutes, 290 trees.';
const TOTALS = '39:55 hours · 1,347 trees';
const COLUMNS = ['Date', 'In', 'Out', 'Trees', 'Hours', 'Breaks', 'Notes'];

const sec = (page: Page) => page.locator('#clock-out');

/** Console errors, page errors and failed requests while the test runs. */
function watch(page: Page) {
  const problems: string[] = [];
  const requests: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()}`));
  page.on('response', (r) => {
    if (r.status() >= 400) problems.push(`HTTP ${r.status()}: ${r.url()}`);
  });
  page.on('request', (r) => requests.push(r.url()));
  return { problems, requests };
}

/** Waits for the motion core and the scenes near the first view. */
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

/** Scrolls to progress `p` (0–1, or past 1) of the section's track and lets the scrub land. */
async function scrollTrack(page: Page, p: number, wait = 1100) {
  await page.evaluate((p) => {
    const track = document.querySelector<HTMLElement>('#clock-out .track')!;
    const top = track.getBoundingClientRect().top + scrollY;
    window.scrollTo(0, Math.round(top + p * Math.max(0, track.offsetHeight - innerHeight)));
  }, p);
  await page.waitForTimeout(wait);
}

/** Scrolls like a reader: from where the page is, in ~600 px wheel steps, to progress `p` of the track. */
async function readTo(page: Page, p: number, wait = 1300) {
  const target = await page.evaluate((p) => {
    const track = document.querySelector<HTMLElement>('#clock-out .track')!;
    const top = track.getBoundingClientRect().top + scrollY;
    return Math.round(top + p * Math.max(0, track.offsetHeight - innerHeight));
  }, p);
  let y = await page.evaluate(() => scrollY);
  while (target - y > 700) {
    await page.mouse.wheel(0, 600);
    await page.waitForTimeout(80);
    y = await page.evaluate(() => scrollY);
  }
  await page.evaluate((t) => window.scrollTo(0, t), target);
  await page.waitForTimeout(wait);
}

type Box = { left: number; top: number; right: number; bottom: number; width: number; height: number };
const boxOf = (page: Page, selector: string) =>
  page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const r = el.getBoundingClientRect();
    return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height } as Box;
  }, selector);
const overlap = (a: Box, b: Box) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;

/** WCAG contrast of the header's text against its own background (composited over the page under it). */
async function headerContrast(page: Page) {
  return page.evaluate(() => {
    const parse = (c: string) => (c.match(/[\d.]+/g) ?? ['0', '0', '0', '1']).map(Number);
    const lum = ([r, g, b]: number[]) => {
      const f = (v: number) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
      return 0.2126 * f(r!) + 0.7152 * f(g!) + 0.0722 * f(b!);
    };
    const header = document.querySelector<HTMLElement>('.site-header')!;
    const under = document.elementsFromPoint(innerWidth / 2, header.getBoundingClientRect().bottom + 4).find((el) => !header.contains(el));
    let base = [236, 241, 236];
    for (let el: Element | null = under ?? null; el; el = el.parentElement) {
      const c = parse(getComputedStyle(el).backgroundColor);
      if ((c[3] ?? 1) > 0.5) {
        base = c.slice(0, 3);
        break;
      }
    }
    const [r, g, b, a = 1] = parse(getComputedStyle(header).backgroundColor);
    const bg = [r!, g!, b!].map((v, i) => v * a + base[i]! * (1 - a));
    const ratio = (fg: number[]) => {
      const [l1, l2] = [lum(fg), lum(bg)].sort((x, y) => y - x);
      return (l1! + 0.05) / (l2! + 0.05);
    };
    const brand = header.querySelector('.brand') ?? header;
    const gh = Array.from(header.querySelectorAll('a')).find((a) => /github/i.test(a.textContent ?? '')) ?? header;
    return { brand: ratio(parse(getComputedStyle(brand).color)), github: ratio(parse(getComputedStyle(gh).color)), theme: header.dataset.theme };
  });
}

async function serious(page: Page) {
  const results = await new AxeBuilder({ page })
    .include('#clock-out')
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
    .analyze();
  return results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
}

async function expectPaper(page: Page) {
  const table = sec(page).locator('table');
  await expect(table).toHaveCount(1);
  await expect(table.locator('caption')).toHaveText(/Example time card for Alex, Mon, Oct 12 – Fri, Oct 16/);
  await expect(table.locator('thead th[scope="col"]')).toHaveText(COLUMNS);
  await expect(table.locator('tbody tr[data-day]')).toHaveCount(5);
  await expect(table.locator('tfoot [data-totals]')).toHaveText(TOTALS);
}

async function overflow(page: Page) {
  return page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
}

test.describe('clock-out', () => {
  test('present, labeled, a real table, and nothing about pay', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await expect(sec(page)).toHaveAttribute('aria-labelledby', 'clock-out-h');
    await expect(page.locator('#clock-out-h')).toHaveText('Clocking out takes a yes.');
    await expect(sec(page).getByRole('heading', { level: 3, name: 'A time card you can hand in.' })).toHaveCount(1);
    // The spoken exchange, from siri.ts, on the page.
    await expect(sec(page).locator('[data-co-said]')).toHaveText('“Clock out with Time Card.”');
    await expect(sec(page).locator('[data-co-reply="ask"]')).toHaveText(ASK);
    await expect(sec(page).locator('[data-co-reply="answer"]')).toHaveText(ANSWER);
    // Both phones are one labeled image each.
    const lock = sec(page).locator('[data-phone][role="img"]').filter({ has: page.locator('[data-screen="lock-1631-quiet"]') });
    await expect(lock).toHaveAttribute('aria-label', new RegExp(`Clocked out at 4:31\\. 8 hours 30 minutes, 290 trees`));
    const report = sec(page).locator('[data-co-report] [data-phone][role="img"]');
    await expect(report).toHaveAttribute('aria-label', /Report tab with This week selected: .*39:55 hours and 1,347 trees over 5 days/);
    await expectPaper(page);
    await expect(sec(page).getByText('No pay on the report. Ever.')).toHaveCount(1);
    await expect(sec(page).getByRole('list', { name: 'Exports as' }).getByRole('listitem')).toHaveText(['PDF', 'CSV']);
    // One Report tab in the markup (desktop borrows the after part's for the stage).
    await expect(page.locator('[data-screen="report-week"]')).toHaveCount(1);
    // The question layer's timer is fixed at 8:30:00, so the idle tick never runs it past the ledger.
    await expect(page.locator('[data-screen="lock-1631-ask"] [data-timer]').first()).toHaveAttribute('data-timer', 'fixed');
    // No pay figures or currency anywhere in the section, phones included.
    const text = (await sec(page).textContent()) ?? '';
    expect(text).not.toMatch(/[$€£]|\bwage|\bpaid\b/i);
    expect(await sec(page).locator('[data-paper] th').allTextContents()).not.toContain('Pay');
    expect(problems).toEqual([]);
  });

  test('plays through its track with motion: the day ends, the lights come up, the paper prints', async ({ page, isMobile }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await settle(page);
    await expect(page.locator('html')).toHaveClass(/(^|\s)motion(\s|$)/);
    for (const p of [0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1]) {
      await scrollTrack(page, p, 450);
      expect(await overflow(page), `overflow at ${p}`).toBeLessThanOrEqual(0);
    }
    await scrollTrack(page, 0.2);
    await expect(sec(page)).toHaveAttribute('data-theme', 'dark');
    await scrollTrack(page, 0.95);
    await expect(sec(page)).toHaveAttribute('data-theme', 'light');
    await expect(page.locator('.site-header')).toHaveAttribute('data-theme', 'light');
    if (!isMobile) {
      // Desktop: the paper is staged over the frame, every row printed, the chips popped.
      await expect(sec(page)).toHaveClass(/co-staged/);
      const paper = sec(page).locator('[data-paper]');
      await expect(paper).toBeInViewport();
      const clips = await paper.locator('tr[data-day]').evaluateAll((rows) => rows.map((r) => getComputedStyle(r).clipPath));
      for (const c of clips) expect(c).toMatch(/^(none|inset\(0(px|%)?\))$/);
      await expect(sec(page).locator('[data-co-chip="csv"]')).toHaveCSS('opacity', '1');
      await scrollTrack(page, 1);
      // The stage phone is back at rest for the next chapter.
      const phone = page.locator('[data-stage] [data-phone]');
      await expect
        .poll(() => phone.evaluate((el) => getComputedStyle(el).transform), { timeout: 5000 })
        .toMatch(/^(none|matrix\(1, 0, 0, 1, 0, 0\))$/);
    } else {
      // Mobile: the paper is in flow after the track, full width, as stacked day blocks.
      await scrollTrack(page, 1.6);
      const paper = sec(page).locator('[data-paper]');
      await paper.scrollIntoViewIfNeeded();
      await expect(paper).toBeVisible();
      const box = await paper.boundingBox();
      expect(box!.width).toBeGreaterThan(300);
      expect(await paper.locator('tr[data-day]').first().evaluate((r) => getComputedStyle(r).display)).toBe('flex');
    }
    expect(problems).toEqual([]);
  });

  test('axe after the lights-up: no serious or critical violations', async ({ page, isMobile }) => {
    await page.goto('/');
    await settle(page);
    await scrollTrack(page, isMobile ? 1.6 : 0.9, 1400);
    await expect(sec(page)).toHaveAttribute('data-theme', 'light');
    expect(await serious(page)).toEqual([]);
  });

  test('the paper lifts out of the preview for a reader scrolling down (Chromium and WebKit)', async ({ page, isMobile }) => {
    test.skip(isMobile, 'desktop: the stage phone');
    // A reader's wheel through eight chapters, twice (Chromium, then WebKit): slow on a busy machine.
    test.setTimeout(150_000);
    const at = DESK.lift[0] + 0.004;
    const check = async (p: Page, engine: string) => {
      await settle(p);
      await readTo(p, at, 1600);
      const paper = await boxOf(p, '#clock-out [data-paper]');
      const thumb = await boxOf(p, '[data-stage] [data-paper-thumb]');
      expect(paper && thumb, engine).toBeTruthy();
      for (const k of ['left', 'top', 'width', 'height'] as const) {
        expect(Math.abs(paper![k] - thumb![k]), `${engine}: paper ${k} ${paper![k].toFixed(1)} vs preview ${thumb![k].toFixed(1)}`).toBeLessThanOrEqual(8);
      }
      // Lifted from the preview, it lands in its slot.
      await readTo(p, DESK.print[0] + 0.01, 1400);
      const slot = await boxOf(p, '#clock-out [data-co-fitbox]');
      const landed = await boxOf(p, '#clock-out [data-paper]');
      expect(Math.abs(landed!.left - slot!.left), `${engine}: landed left`).toBeLessThanOrEqual(12);
      expect(Math.abs(landed!.width - slot!.width), `${engine}: landed width`).toBeLessThanOrEqual(16);
    };
    await page.goto('/');
    await check(page, 'chromium');
    let browser: Awaited<ReturnType<typeof webkit.launch>> | null = null;
    try {
      browser = await webkit.launch();
    } catch {
      test.info().annotations.push({ type: 'note', description: 'WebKit is not installed: checked in Chromium only.' });
    }
    if (browser) {
      try {
        const wk = await browser.newPage({ viewport: { width: 1440, height: 900 } });
        await wk.goto(new URL('/', page.url()).href);
        await check(wk, 'webkit');
      } finally {
        await browser.close();
      }
    }
  });

  test('a jump straight past the lift lands the paper in its slot, and a resize keeps it there', async ({ page, isMobile }) => {
    test.skip(isMobile, 'desktop: the staged paper');
    await page.goto('/');
    await settle(page);
    const landed = async (why: string) => {
      await expect
        .poll(async () => {
          const paper = await boxOf(page, '#clock-out [data-paper]');
          const slot = await boxOf(page, '#clock-out [data-co-fitbox]');
          return Math.max(Math.abs(paper!.left - slot!.left), Math.abs(paper!.width - slot!.width) / 2);
        }, { message: why, timeout: 6000 })
        .toBeLessThanOrEqual(12);
    };
    // Like a chapter link: one jump from the top, no scrolling through the lift.
    await scrollTrack(page, DESK.print[1] - 0.04, 1600);
    await landed('after the jump');
    await page.setViewportSize({ width: 1360, height: 860 });
    await page.waitForTimeout(1500);
    await landed('after a resize');
  });

  test('a quiet lock screen before the unlock: the card goes, the date and clock come back', async ({ page, isMobile }) => {
    await page.goto('/');
    await settle(page);
    const B = isMobile ? MOB : DESK;
    await readTo(page, B.quiet[1] + 0.01, 1500);
    const answer = page.locator('[data-screen="lock-1631-answer"]');
    await expect.poll(() => answer.evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    await expect.poll(() => answer.locator('[data-snippet]').evaluate((el) => getComputedStyle(el).opacity)).toBe('0');
    await expect.poll(() => answer.locator('.lock-clock[data-clock]').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    await expect(answer.locator('[data-la]')).toHaveCSS('opacity', '0');
  });

  test('mobile: the cards keep clear of the timer while it is underlined and dismissed; “Yes.” lights in view', async ({ page, isMobile }) => {
    test.skip(!isMobile, 'mobile cards');
    await page.goto('/');
    await settle(page);
    const mid = (w: readonly [number, number]) => (w[0] + w[1]) / 2;
    // “Yes.” lights in view: the card's top is above 85% of the viewport while its words light.
    await readTo(page, MOB.yes[0] + 0.02);
    const yesCard = (await boxOf(page, '#clock-out [data-co-ex="answer"]'))!;
    const vh = page.viewportSize()!.height;
    expect(yesCard.top).toBeLessThanOrEqual(vh * 0.85);
    // The timer: the answer layer's, on the section's own sticky phone.
    for (const p of [MOB.underline[0], mid(MOB.underline), MOB.underline[1], MOB.dismiss[0], mid(MOB.dismiss), MOB.dismiss[1] - 0.004]) {
      await readTo(page, p, 900);
      const timer = (await boxOf(page, '#clock-out [data-screen="lock-1631-answer"] [data-timer]'))!;
      const cards = await page.locator('#clock-out .co-beat').evaluateAll((els) =>
        els.map((el) => {
          const r = el.getBoundingClientRect();
          return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
        }),
      );
      for (const [i, c] of cards.entries()) expect(overlap(c, timer), `card ${i + 1} over the timer at ${p.toFixed(3)}`).toBe(false);
    }
  });

  test('mobile: the timer holds 8:30:00 once the lapse lands, idle or not', async ({ page, isMobile }) => {
    test.skip(!isMobile, 'mobile sticky phone (desktop shares the layers)');
    await page.goto('/');
    await settle(page);
    await readTo(page, (MOB.lapse[1] + MOB.glow[0]) / 2, 2600);
    await expect(page.locator('#clock-out [data-screen="lock-1631-activity"]')).toHaveCSS('opacity', '0');
    const ask = page.locator('#clock-out [data-screen="lock-1631-ask"]');
    await expect(ask).toHaveCSS('opacity', '1');
    expect(await ask.locator('.la-timer').evaluate((el) => (el as HTMLElement).dataset.odoText)).toBe('8:30:00');
  });
});

test.describe('clock-out on a short desktop window (960 × 580)', () => {
  test.use({ viewport: { width: 960, height: 580 } });

  test('the dusk beats never overlap', async ({ page, isMobile }) => {
    test.skip(isMobile, 'desktop layout');
    await page.goto('/');
    await settle(page);
    for (const p of [0.1, 0.2, 0.3, BEAT_AT.forgot.desk]) {
      await readTo(page, p, 700);
      const boxes = await page.locator('#clock-out .co-beat').evaluateAll((els) =>
        els.map((el) => {
          const r = el.getBoundingClientRect();
          return { left: r.left, top: r.top, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
        }),
      );
      for (let i = 1; i < boxes.length; i += 1) {
        expect(boxes[i]!.top - boxes[i - 1]!.bottom, `beats ${i} and ${i + 1} at ${p}`).toBeGreaterThanOrEqual(8);
      }
    }
  });
});

test.describe('clock-out with reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });

  test('the final state, static: dusk band, quiet lock screen, the Report tab and the printed paper', async ({ page }) => {
    const { problems, requests } = watch(page);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    await page.locator('#clock-out-h').scrollIntoViewIfNeeded();
    await expect(page.locator('#clock-out-h')).toBeVisible();
    // The exchange as a static transcript, every word at full opacity.
    for (const sel of ['[data-co-said]', '[data-co-reply="ask"]', '[data-co-yes]', '[data-co-reply="answer"]']) {
      const el = sec(page).locator(sel);
      await expect(el).toBeVisible();
      const faded = await el.locator('.co-w').evaluateAll((ws) => ws.filter((w) => Number(getComputedStyle(w).opacity) < 1).length);
      expect(faded, sel).toBe(0);
    }
    // The section phone shows the answer over the quiet lock screen (no Live Activity).
    const quiet = sec(page).locator('[data-screen="lock-1631-quiet"]');
    await quiet.scrollIntoViewIfNeeded();
    await expect(quiet).toBeVisible();
    // textContent: WebKit leaves innerText empty in a content-visibility: auto section.
    const said = await quiet.locator('[data-snippet-text]').textContent();
    expect(said?.replace(/\s+/g, ' ').trim()).toBe(ANSWER);
    await expect(quiet.locator('[data-la]')).toHaveCount(0);
    // The light part: the Report tab beside the fully printed paper, the note and the chips.
    for (const sel of ['[data-co-report]', '[data-paper]', '[data-co-note]', '[data-co-chip="pdf"]', '[data-co-chip="csv"]']) {
      const el = sec(page).locator(sel);
      await el.scrollIntoViewIfNeeded();
      await expect(el, sel).toBeVisible();
    }
    await expectPaper(page);
    const rows = sec(page).locator('[data-paper] tr[data-day]');
    for (let i = 0; i < 5; i += 1) await expect(rows.nth(i)).toBeVisible();
    await expect(sec(page).locator('[data-totals]')).toHaveCSS('opacity', '1');
    // No GSAP ever.
    expect(requests.filter((u) => /gsap|ScrollTrigger/i.test(u))).toEqual([]);
    expect(await overflow(page)).toBeLessThanOrEqual(0);
    expect(problems).toEqual([]);
  });

  test('axe on the static section: no serious or critical violations', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    await sec(page).locator('[data-paper]').scrollIntoViewIfNeeded();
    expect(await serious(page)).toEqual([]);
  });

  test('the header stays readable over the light part (static)', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    for (const sel of ['[data-co-copy]', '[data-paper]', '.co-exports']) {
      // Far sections render lazily (content-visibility), so the page above can still change
      // height after a jump: settle on the element, then check it is what the header is over.
      for (let i = 0; i < 4; i += 1) {
        await page.evaluate((sel) => {
          const el = document.querySelector(`#clock-out ${sel}`)!;
          window.scrollTo(0, el.getBoundingClientRect().top + scrollY - 40);
        }, sel);
        await page.waitForTimeout(250);
      }
      const under = await page.evaluate(() => {
        const header = document.querySelector('.site-header')!;
        const y = header.getBoundingClientRect().bottom + 4;
        return document.elementsFromPoint(innerWidth / 2, y).some((el) => el.closest('#clock-out .after'));
      });
      expect(under, `the light part is under the header at ${sel}`).toBe(true);
      // The header's colors ease over 0.3 s.
      await page.waitForTimeout(700);
      const c = await headerContrast(page);
      expect(c.brand, `brand over ${sel} (${c.theme})`).toBeGreaterThanOrEqual(4.5);
      expect(c.github, `GitHub over ${sel} (${c.theme})`).toBeGreaterThanOrEqual(4.5);
    }
  });

  test('at 375px the paper is stacked day blocks with no horizontal scroll', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto('/');
    const paper = sec(page).locator('[data-paper]');
    await paper.scrollIntoViewIfNeeded();
    const box = await paper.boundingBox();
    expect(box!.x).toBeGreaterThanOrEqual(0);
    expect(box!.x + box!.width).toBeLessThanOrEqual(375);
    expect(await paper.locator('tr[data-day]').first().evaluate((r) => getComputedStyle(r).display)).toBe('flex');
    expect(await overflow(page)).toBeLessThanOrEqual(0);
  });
});
