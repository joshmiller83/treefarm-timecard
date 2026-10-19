/**
 * device-a lab: the phone frame, status bar, screen layers, lock screen and Live Activity.
 * Geometry is checked in points: each phone's screen is 393 pt wide, so 1 pt = width / 393.
 *
 * Runs against the built site, at 1440 × 900 and 375 × 812, as the lab-desktop and
 * lab-mobile projects of playwright.config.ts:
 *   npm run build && npm run test:e2e -- --project=lab-desktop --project=lab-mobile
 * Those projects (testDir tests/lab) are the foundation owner's to add to the config; until
 * they land, this suite is not part of CI.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';

const URL = '/lab/device-a/';

function watch(page: Page) {
  const problems: string[] = [];
  page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text()}`));
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()}`));
  page.on('response', (r) => r.status() >= 400 && problems.push(`HTTP ${r.status()}: ${r.url()}`));
  return problems;
}

async function open(page: Page) {
  await page.goto(URL);
  await page.evaluate(() => document.fonts.ready);
}

type Box = { x: number; y: number; width: number; height: number };
const box = async (l: Locator): Promise<Box> => {
  const b = await l.boundingBox();
  if (!b) throw new Error('no box');
  return b;
};

/** A phone cell's screen rect and the size of one point in CSS px. */
async function screenOf(cell: Locator) {
  const s = await box(cell.locator('.screen').first());
  return { s, u: s.width / 393 };
}

const cell = (page: Page, id: string) => page.locator(`[data-lab-state="${id}"]`);

/** Row numbers whose buttons are inside the strip's clip (fully or mostly). */
async function visibleRows(la: Locator) {
  return la.evaluate((el) => {
    const strip = el.querySelector('[data-strip]')!.getBoundingClientRect();
    return Array.from(el.querySelectorAll<HTMLElement>('[data-row]'))
      .filter((b) => {
        const r = b.getBoundingClientRect();
        const inside = Math.min(r.right, strip.right) - Math.max(r.left, strip.left);
        return inside > r.width * 0.5 && getComputedStyle(b).transform !== 'matrix(0, 0, 0, 1, 0, 0)';
      })
      .map((b) => Number(b.dataset.row));
  });
}

test('renders every state with no errors, labeled phones and hidden mock internals', async ({ page }) => {
  const problems = watch(page);
  await open(page);
  const states = page.locator('[data-lab-state]');
  expect(await states.count()).toBeGreaterThanOrEqual(12);
  const phones = page.locator('main [data-phone][role="img"]');
  const n = await phones.count();
  expect(n).toBeGreaterThanOrEqual(12);
  for (let i = 0; i < n; i += 1) {
    const p = phones.nth(i);
    expect((await p.getAttribute('aria-label'))?.length ?? 0).toBeGreaterThan(20);
    await expect(p.locator('.phone-body')).toHaveAttribute('aria-hidden', 'true');
  }
  // The decorative stage phone is hidden from assistive tech altogether.
  await expect(page.locator('[data-phone][data-variant="stage"]')).toHaveAttribute('aria-hidden', 'true');
  expect(problems).toEqual([]);
});

test('tells the truth: no clock-out button, no pay, no dollar sign', async ({ page }) => {
  await open(page);
  const cards = await page.locator('[data-la]').allInnerTexts();
  expect(cards.length).toBeGreaterThan(10);
  for (const t of cards) {
    expect(t.toLowerCase()).not.toContain('clock out');
    expect(t).not.toMatch(/\$|pay/i);
  }
  const text = await page.evaluate(() => document.body.innerText);
  expect(text).not.toContain('$');
});

test('the screen is 393 × 852 pt in a 420 × 879 frame; the island is 126 × 37 pt at y 11', async ({ page }) => {
  await open(page);
  const c = cell(page, 'lab-a-1414-tapped');
  const phone = await box(c.locator('[data-phone]'));
  const { s, u } = await screenOf(c);
  expect(s.width / s.height).toBeCloseTo(393 / 852, 3);
  expect(phone.width / phone.height).toBeCloseTo(420 / 879, 3);
  expect((s.x - phone.x) / u).toBeCloseTo(13.5, 0);
  const island = await box(c.locator('[data-island-rest]'));
  expect(island.width / u).toBeCloseTo(126, 0);
  expect(island.height / u).toBeCloseTo(37, 0);
  expect((island.y - s.y) / u).toBeCloseTo(11, 0);
  expect(island.x + island.width / 2).toBeCloseTo(s.x + s.width / 2, 0);
  const radius = await c.locator('.screen').evaluate((el) => parseFloat(getComputedStyle(el).borderTopLeftRadius));
  expect(radius / u).toBeCloseTo(55, 0);
});

test('Live Activity geometry: 361 pt wide, bottom at y 760, ≤ 160 pt, 46 pt buttons 8 pt apart', async ({ page }) => {
  await open(page);
  const ids = ['lab-a-0702', 'lab-a-1201', 'lab-a-1414', 'lab-a-1414-tapped', 'lab-a-1430', 'lab-a-1631'];
  for (const id of ids) {
    const c = cell(page, id);
    const { s, u } = await screenOf(c);
    const la = c.locator('[data-la]');
    const b = await box(la);
    expect((b.x - s.x) / u, id).toBeCloseTo(16, 0);
    expect(b.width / u, id).toBeCloseTo(361, 0);
    expect((b.y + b.height - s.y) / u, id).toBeCloseTo(760, 0);
    expect(b.height / u, id).toBeLessThanOrEqual(160.5);
    const radius = await la.evaluate((el) => parseFloat(getComputedStyle(el).borderTopLeftRadius));
    expect(radius / u, id).toBeCloseTo(24, 0);
    // Buttons: 46 pt tall, radius 14, and 8 pt between neighbours (layout boxes: on a break
    // the row buttons are collapsed with scaleX(0), which does not change their layout).
    const m = await la.evaluate((el) => {
      const a = el.querySelector<HTMLElement>('[data-row]')!;
      const track = el.querySelector<HTMLElement>('[data-strip-track]')!;
      const brk = el.querySelector<HTMLElement>('[data-break-btn]')!;
      const cs = getComputedStyle(a);
      return {
        w: parseFloat(cs.width),
        h: parseFloat(cs.height),
        gap: parseFloat(getComputedStyle(track).columnGap),
        r: parseFloat(cs.borderTopLeftRadius),
        brk: parseFloat(getComputedStyle(brk).width),
      };
    });
    expect(m.h / u, id).toBeCloseTo(46, 0);
    expect(m.gap / u, id).toBeCloseTo(8, 0);
    expect(m.r / u, id).toBeCloseTo(14, 0);
    expect(m.brk, id).toBeCloseTo(m.w, 1);
    expect(m.w / u, id).toBeCloseTo(77.25, 0);
  }
});

test('every hook the scenes rely on is present', async ({ page }) => {
  await open(page);
  const c = cell(page, 'lab-a-1414');
  for (const sel of [
    '[data-phone]',
    '.phone-body .screen',
    '[data-island-rest]',
    '[data-rim]',
    '[data-sheen]',
    '[data-shadow]',
    '.screens[data-screens] > .layer[data-state="lab-a-1414"][data-screen="lab-a-1414"][data-final]',
    '[data-lock]',
    '[data-wallpaper]',
    '[data-date]',
    '.lock-clock[data-clock]',
    '[data-dim]',
    '[data-activity-slot] [data-la]',
    '[data-statusbar] [data-clock]',
    '[data-bar="1"]',
    '[data-bar="4"]',
    '[data-no-service]',
    '[data-wifi]',
    '[data-la][data-state="working"]',
    '[data-la-material]',
    '[data-la-break]',
    '[data-pill] [data-pill-text]',
    '[data-pill-face="clock"] [data-pill-text="clock"]',
    '[data-pill-face="break"] [data-pill-text="break"]',
    '[data-place]',
    '.odo[data-timer][data-odo]',
    '[data-worked-line] [data-timer]',
    '[data-trees-line] .odo[data-trees][data-odo]',
    '[data-field] > [data-fieldbar]',
    '[data-undo] [data-undo-row]',
    '[data-lock-quick]',
    '[data-home-indicator]',
    '[data-strip] > [data-strip-track] > [data-row="36"]',
    '[data-row="39"]',
    '[data-break-btn]',
    '[data-back-btn]',
  ]) {
    expect(await c.locator(sel).count(), sel).toBeGreaterThan(0);
  }
  // Frozen crops: fixed timers and clock (live ones would be driven by DayClock).
  await expect(c.locator('.la-timer')).toHaveAttribute('data-timer', 'fixed');
  await expect(c.locator('.lock-clock')).toHaveAttribute('data-clock', 'fixed');
});

test('states read from the ledger', async ({ page }) => {
  await open(page);
  const la = (id: string) => cell(page, id).locator('[data-la]');
  const timer = (id: string) => la(id).locator('.la-timer');

  await expect(timer('lab-a-0702')).toHaveAttribute('data-odo-text', '0:00:00');
  await expect(la('lab-a-0702').locator('[data-trees]')).toHaveAttribute('data-odo-text', '0');
  // The field bar: scaleX = fieldPct (26% at clock-in), with no visible percent (the app shows none).
  const bar = await la('lab-a-0702').locator('[data-fieldbar]').evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).a);
  expect(bar).toBeCloseTo(0.2564, 3);
  for (const t of await page.locator('[data-la]').allInnerTexts()) expect(t).not.toContain('%');
  expect(await visibleRows(la('lab-a-0702'))).toEqual([14, 15, 16]);
  await expect(la('lab-a-0702').locator('[data-place]')).toHaveText('North field · Block 2');

  await expect(la('lab-a-1201')).toHaveAttribute('data-state', 'lunch');
  await expect(la('lab-a-1201').locator('[data-pill-face="break"]')).toHaveText('On lunch');
  await expect(la('lab-a-1201').locator('[data-pill-face="clock"]')).toHaveCSS('opacity', '0');
  await expect(la('lab-a-1201').locator('[data-worked-line]')).toHaveText('4:44:00 worked');
  await expect(la('lab-a-1201').locator('[data-back-btn]')).toHaveText('Back to work');
  await expect(la('lab-a-1201').locator('[data-back-btn]')).toHaveCSS('clip-path', 'none');
  await expect(la('lab-a-1201').locator('[data-break-btn]')).toHaveCSS('opacity', '0');
  expect(await visibleRows(la('lab-a-1201'))).toEqual([]);
  // Collapsed rows grow back from the left unless a scene picks another origin.
  for (const r of await la('lab-a-1201').locator('[data-row]').all()) {
    expect(await r.evaluate((el) => getComputedStyle(el).transformOrigin.split(' ')[0])).toBe('0px');
  }
  // The timer turns gold on lunch and break.
  await expect(timer('lab-a-1201')).toHaveCSS('color', 'rgb(226, 166, 68)');
  await expect(timer('lab-a-1414')).toHaveCSS('color', 'rgb(255, 255, 255)');

  await expect(timer('lab-a-1414')).toHaveAttribute('data-odo-text', '6:27:00');
  await expect(la('lab-a-1414').locator('[data-trees]')).toHaveAttribute('data-odo-text', '220');
  await expect(la('lab-a-1414').locator('[data-undo]')).toHaveCSS('opacity', '0');
  expect(await visibleRows(la('lab-a-1414'))).toEqual([36, 37, 38]);

  await expect(la('lab-a-1414-tapped')).toHaveAttribute('data-state', 'tapped');
  await expect(la('lab-a-1414-tapped').locator('[data-undo]')).toHaveText('Row 36 marked · Undo');
  await expect(la('lab-a-1414-tapped').locator('[data-undo]')).toHaveCSS('opacity', '1');
  await expect(la('lab-a-1414-tapped').locator('[data-trees]')).toHaveAttribute('data-odo-text', '230');
  expect(await visibleRows(la('lab-a-1414-tapped'))).toEqual([37, 38, 39]);

  await expect(la('lab-a-1430').locator('[data-pill-face="break"]')).toHaveText('On break · Sharpening shears');
  await expect(la('lab-a-1430').locator('[data-worked-line]')).toHaveText('6:43:00 worked');
  // The long reason pill and the place share row 1 without truncating.
  await expect(la('lab-a-1430').locator('[data-place]')).toHaveText('North field · Block 2');
  expect(await la('lab-a-1430').locator('[data-place]').evaluate((el) => el.scrollWidth <= el.clientWidth + 0.5)).toBe(true);
  expect(await la('lab-a-0702').locator('[data-place]').evaluate((el) => el.scrollWidth <= el.clientWidth + 0.5)).toBe(true);

  await expect(timer('lab-a-1631')).toHaveAttribute('data-odo-text', '8:30:00');
  await expect(la('lab-a-1631').locator('[data-trees]')).toHaveAttribute('data-odo-text', '290');
  expect(await visibleRows(la('lab-a-1631'))).toEqual([42, 43, 44]);

  // The quiet lock screen has no activity at all.
  await expect(cell(page, 'lab-a-1631-quiet').locator('[data-la]')).toHaveCount(0);
});

test('the lock screen: no status-bar time, date and clock where iOS puts them, wallpaper inlined', async ({ page }) => {
  await open(page);
  const c = cell(page, 'lab-a-0702');
  const { s, u } = await screenOf(c);
  await expect(c.locator('[data-statusbar] .sb-left')).toHaveCSS('visibility', 'hidden');
  await expect(c.locator('[data-date]')).toHaveText('Friday, October 16');
  await expect(c.locator('.lock-clock')).toHaveText('7:02');
  const date = await box(c.locator('[data-date]'));
  const clock = await box(c.locator('.lock-clock'));
  expect((date.y - s.y) / u).toBeCloseTo(70, 0);
  expect((clock.y - s.y) / u).toBeCloseTo(92, 0);
  const fontSize = await c.locator('.lock-clock').evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
  expect(fontSize / u).toBeCloseTo(92, 0);
  const wp = await c.locator('[data-wallpaper]').evaluate((el) => getComputedStyle(el).backgroundImage);
  expect(wp).toContain('data:image/svg+xml');
  // The flashlight and camera buttons sit below the card, inside the screen.
  const la = await box(c.locator('[data-la]'));
  for (const btn of await c.locator('.lock-btn').all()) {
    const b = await box(btn);
    expect(b.y).toBeGreaterThan(la.y + la.height);
    expect(b.width / u).toBeCloseTo(50, 0);
  }
});

test('No Service fits the right ear without touching the island', async ({ page }) => {
  await open(page);
  const strips = page.locator('.bar-strip').filter({ has: page.locator('.sb--offline') });
  expect(await strips.count()).toBe(2);
  for (const strip of await strips.all()) {
    const u = (await box(strip)).width / 393;
    const island = await box(strip.locator('.bar-island'));
    const text = await box(strip.locator('[data-no-service]'));
    expect(text.x - (island.x + island.width)).toBeGreaterThan(3 * u);
    await expect(strip.locator('[data-no-service]')).toHaveCSS('opacity', '1');
    await expect(strip.locator('[data-wifi]')).toHaveCSS('opacity', '0');
  }
});

test('the field bar reads as a bar: a visible track on both materials', async ({ page }) => {
  await open(page);
  // Track over card, as WCAG computes it (an empty track must not vanish into the card).
  const ratios = await page.evaluate(() => {
    type RGBA = [number, number, number, number];
    const rgba = (c: string): RGBA => {
      const [r = 0, g = 0, b = 0, a = 1] = (c.match(/[\d.]+/g) ?? []).map(Number);
      return [r, g, b, a];
    };
    const lum = ([r, g, b]: RGBA) => {
      const f = (v: number) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
      return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
    };
    const over = (top: RGBA, under: RGBA): RGBA => {
      const mix = (t: number, u: number) => t * top[3] + u * (1 - top[3]);
      return [mix(top[0], under[0]), mix(top[1], under[1]), mix(top[2], under[2]), 1];
    };
    return Array.from(document.querySelectorAll<HTMLElement>('[data-lab-state] [data-la]')).map((la) => {
      const onBreak = la.dataset.state === 'break' || la.dataset.state === 'lunch';
      const twin: RGBA = [23, 38, 28, 1]; // the dawn twin's darkest band behind the card
      const mat = rgba(getComputedStyle(la.querySelector<HTMLElement>(onBreak ? '[data-la-break]' : '[data-la-material]')!).backgroundColor);
      const card = over(mat, twin);
      const track = over(rgba(getComputedStyle(la.querySelector<HTMLElement>('[data-field]')!).backgroundColor), card);
      const hi = Math.max(lum(track), lum(card));
      const lo = Math.min(lum(track), lum(card));
      return (hi + 0.05) / (lo + 0.05);
    });
  });
  expect(ratios.length).toBeGreaterThan(5);
  for (const r of ratios) expect(r).toBeGreaterThan(1.45);
});

test('the strip falls back to overflow: hidden where overflow: clip is missing', async ({ page }) => {
  await open(page);
  const fallback = await page.evaluate(() => {
    const rules = (list: CSSRuleList): CSSRule[] => Array.from(list).flatMap((r) => ('cssRules' in r ? [r, ...rules((r as CSSGroupingRule).cssRules)] : [r]));
    return Array.from(document.styleSheets)
      .flatMap((sh) => rules(sh.cssRules))
      .filter((r): r is CSSSupportsRule => r instanceof CSSSupportsRule && /not\s*\(overflow:\s*clip\)/.test(r.conditionText))
      .some((r) => /la-strip[^{]*\{[^}]*overflow:\s*hidden/.test(r.cssText));
  });
  expect(fallback).toBe(true);
});

test('battery: red at 20% and below, as iOS draws it', async ({ page }) => {
  await open(page);
  const low = page.locator('[data-statusbar][data-battery-low]');
  await expect(low).toHaveCount(1);
  await expect(low).toHaveAttribute('data-battery', '20');
  await expect(low.locator('.sb-battery rect').nth(1)).toHaveAttribute('fill', '#FF3B30');
  const normal = page.locator('[data-statusbar]:not([data-battery-low]) .sb-battery rect:nth-of-type(2)');
  for (const r of await normal.all()) await expect(r).toHaveAttribute('fill', 'currentColor');
});

test.describe('play-through (reduced motion: each step lands at once)', () => {
  test.use({ reducedMotion: 'reduce' });

  test('a tap advances the strip by one button plus the gap; Break and Back swap the card', async ({ page }) => {
    const problems = watch(page);
    await open(page);
    const play = page.locator('[data-play]');
    const la = play.locator('[data-la]');
    const before38 = await box(la.locator('[data-row="38"]'));
    const r36 = await box(la.locator('[data-row="36"]'));
    const r37 = await box(la.locator('[data-row="37"]'));
    const step = r37.x - r36.x;

    await play.getByRole('button', { name: 'Tap Row 36' }).click();
    await expect(play.locator('[data-play-log]')).toContainText('Row 36 marked');
    const after39 = await box(la.locator('[data-row="39"]'));
    expect(after39.x).toBeCloseTo(before38.x, 0);
    const after36 = await box(la.locator('[data-row="36"]'));
    expect(after36.x).toBeCloseTo(r36.x - step, 0);
    expect(await visibleRows(la)).toEqual([37, 38, 39]);
    await expect(la.locator('[data-trees]')).toHaveAttribute('data-odo-text', '230');
    await expect(la.locator('[data-undo]')).toHaveCSS('opacity', '1');

    await play.getByRole('button', { name: 'Tap Break' }).click();
    await expect(la).toHaveAttribute('data-state', 'break');
    await expect(la.locator('.la-timer')).toHaveAttribute('data-odo-text', '0:00:00');
    await expect(la.locator('[data-back-btn]')).toHaveCSS('clip-path', /inset\(0(px)? 0(%|px)? 0(px)? 0(px)?\)|none/);
    expect(await visibleRows(la)).toEqual([]);

    await play.getByRole('button', { name: 'Back to work' }).click();
    await expect(la).toHaveAttribute('data-state', 'tapped');
    expect(await visibleRows(la)).toEqual([37, 38, 39]);
    expect(problems).toEqual([]);
  });

  test('the static page has no motion class and every phone is drawn', async ({ page }) => {
    await open(page);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    for (const p of await page.locator('[data-lab-state] [data-phone]').all()) {
      const b = await box(p);
      expect(b.height).toBeGreaterThan(300);
    }
  });
});

test('captures: with no file in public/screens, each Screen renders its recreation', async ({ page }) => {
  await open(page);
  await expect(page.locator('.layer[data-capture]')).toHaveCount(0);
  await expect(page.locator('.layer img.capture')).toHaveCount(0);
  expect(await page.locator('.layer[data-screen] [data-lock], .layer[data-screen] [data-app]').count()).toBeGreaterThan(10);
});

test('no horizontal overflow', async ({ page }) => {
  await open(page);
  const over = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  expect(over).toBeLessThanOrEqual(0);
});

test('keyboard: the play controls are reachable and labeled', async ({ page }) => {
  await open(page);
  const buttons = page.locator('[data-play] button');
  expect(await buttons.count()).toBe(6);
  await buttons.first().focus();
  await expect(buttons.first()).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.locator('[data-play-log]')).toContainText('Row 36 marked');
});

test('axe: no serious or critical violations', async ({ page }) => {
  await open(page);
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  const bad = results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
  expect(bad).toEqual([]);
});
