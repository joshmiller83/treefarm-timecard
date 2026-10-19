/**
 * Lab: device-b. Renders every state of DynamicIsland, SiriSnippet, SiriGlow, DictationWave
 * and ControlsCard and checks the geometry and hooks in src/components/CONTRACT.md.
 *
 *   npm run build && PW_PORT=4414 npx playwright test tests/lab/device-b.spec.ts
 * (the Playwright config must include tests/lab; see the device-b notes).
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';
import { SIRI } from '../../src/data/siri';
import { WAVE_MIN, waveHeights } from '../../src/scripts/wave';
import { watch } from '../e2e/helpers';

const URL = '/lab/device-b/';
const cell = (page: Page, id: string) => page.locator(`[data-lab-cell="${id}"]`);

/** The pt scale of the screen a hook sits in (screen width / 393). */
async function ptOf(loc: Locator): Promise<number> {
  return loc.evaluate((el) => {
    const screen = el.closest('.screen');
    if (!screen) throw new Error('not inside a .screen');
    return screen.getBoundingClientRect().width / 393;
  });
}

/** A hook's box in pt, relative to its screen. */
async function boxPt(loc: Locator) {
  return loc.evaluate((el) => {
    const screen = el.closest('.screen')!.getBoundingClientRect();
    const pt = screen.width / 393;
    const r = el.getBoundingClientRect();
    const radius = parseFloat(getComputedStyle(el).borderTopLeftRadius);
    return {
      x: (r.left - screen.left) / pt,
      y: (r.top - screen.top) / pt,
      w: r.width / pt,
      h: r.height / pt,
      radius: radius / pt,
      screenW: 393,
    };
  });
}

const near = (a: number, b: number, tol = 0.75) => Math.abs(a - b) <= tol;

test.beforeEach(async ({ page }) => {
  await page.goto(URL);
  await page.evaluate(() => document.fonts.ready);
});

test('renders every state with no console errors, failed requests or stubs', async ({ page }) => {
  const { problems } = watch(page);
  await page.goto(URL);
  await page.evaluate(() => document.fonts.ready);
  await expect(page.locator('h1')).toHaveText('device-b');
  for (const id of [
    'snippet-clock-in',
    'snippet-misheard',
    'snippet-misheard-no',
    'snippet-status',
    'snippet-clock-out-ask',
    'snippet-clock-out',
    'glow-live',
    'glow-thinking',
    'glow-still',
    'glow-auto',
    'wave-listen',
    'wave-speaking',
    'wave-reply',
    'island-rest',
    'island-compact',
    'island-expanded',
    'island-app',
    'crop-compact',
    'crop-expanded',
    'controls-wide',
    'controls-narrow',
    'controls-plain',
  ]) {
    await expect(cell(page, id), id).toBeVisible();
  }
  // None of device-b's components is still a foundation stub.
  for (const stub of ['DynamicIsland', 'SiriSnippet', 'SiriGlow', 'DictationWave', 'ControlsCard']) {
    await expect(page.locator(`[data-stub="${stub}"]`)).toHaveCount(0);
    await expect(page.getByText(`${stub} · stub`, { exact: false })).toHaveCount(0);
  }
  expect(problems).toEqual([]);
});

test.describe('SiriSnippet', () => {
  test('sits at y 64 pt, 361 pt wide, radius 26, with the header and the exact Siri line', async ({ page }) => {
    const snip = cell(page, 'snippet-clock-in').locator('[data-snippet]');
    const b = await boxPt(snip);
    expect(near(b.x, 16), `x ${b.x}`).toBe(true);
    expect(near(b.y, 64), `y ${b.y}`).toBe(true);
    expect(near(b.w, 361), `w ${b.w}`).toBe(true);
    expect(near(b.radius, 26), `radius ${b.radius}`).toBe(true);
    await expect(snip).toContainText('TIME CARD');
    const text = (await snip.locator('[data-snippet-text]').textContent())!.replace(/ /g, ' ').replace(/\s+/g, ' ').trim();
    expect(text).toBe(SIRI.clockIn.reply);
    // 17 pt white reply text.
    const pt = await ptOf(snip);
    const fs = await snip.locator('[data-snippet-text]').evaluate((el) => parseFloat(getComputedStyle(el).fontSize));
    expect(near(fs / pt, 17, 0.1)).toBe(true);
  });

  test('is karaoke-ready: the reply is pre-split into word spans', async ({ page }) => {
    const words = cell(page, 'snippet-status').locator('[data-snippet-text] [data-word]');
    const n = SIRI.howMany.reply.split(/\s+/).length - 2; // 'block 2' and 'row 35' stay together
    await expect(words).toHaveCount(n);
    await expect(words.first()).toHaveText('212');
    await expect(words.first()).toHaveAttribute('data-word', '0');
  });

  test('shows 40 pt Yes / No chips; only the chosen one has the gold ring', async ({ page }) => {
    const plain = cell(page, 'snippet-misheard');
    const chosen = cell(page, 'snippet-misheard-no');
    for (const c of [plain, chosen]) {
      await expect(c.locator('[data-choice]')).toHaveCount(2);
      await expect(c.locator('[data-choice="Yes"]')).toHaveText('Yes');
      await expect(c.locator('[data-choice="No"]')).toHaveText('No');
      const b = await boxPt(c.locator('[data-choice="Yes"]'));
      expect(near(b.h, 40), `chip h ${b.h}`).toBe(true);
    }
    const yesBg = await plain.locator('[data-choice="Yes"]').evaluate((el) => getComputedStyle(el).backgroundColor);
    expect(yesBg).toBe('rgb(46, 122, 78)');
    const ring = (c: Locator, which: string) =>
      c.locator(`[data-choice="${which}"] [data-choice-ring]`).evaluate((el) => getComputedStyle(el).opacity);
    expect(await ring(plain, 'Yes')).toBe('0');
    expect(await ring(plain, 'No')).toBe('0');
    expect(await ring(chosen, 'No')).toBe('1');
    expect(await ring(chosen, 'Yes')).toBe('0');
    expect(await ring(cell(page, 'snippet-clock-out-ask'), 'Yes')).toBe('1');
  });

  test('has no chips when there are no choices', async ({ page }) => {
    await expect(cell(page, 'snippet-clock-out').locator('[data-choice]')).toHaveCount(0);
  });
});

test.describe('SiriGlow', () => {
  test('covers the whole screen and its ring covers the screen diagonal at any rotation', async ({ page }) => {
    const glow = cell(page, 'glow-live').locator('[data-glow]');
    const geo = await glow.evaluate((el) => {
      const s = el.closest('.screen')!.getBoundingClientRect();
      const g = el.getBoundingClientRect();
      const ring = el.querySelector('[data-glow-ring]')!.getBoundingClientRect();
      return { s: { w: s.width, h: s.height }, g: { w: g.width, h: g.height, dx: g.left - s.left, dy: g.top - s.top }, ring: ring.width };
    });
    expect(geo.g.dx).toBeCloseTo(0, 0);
    expect(geo.g.dy).toBeCloseTo(0, 0);
    expect(geo.g.w).toBeCloseTo(geo.s.w, 0);
    expect(geo.g.h).toBeGreaterThanOrEqual(geo.s.h - 1);
    expect(geo.ring).toBeGreaterThan(Math.hypot(geo.s.w, geo.s.h));
  });

  test('uses the edge mask with a bloom when live and a thin faint border when still', async ({ page }) => {
    const mask = (id: string) =>
      cell(page, id)
        .locator('[data-glow]')
        .evaluate((el) => {
          const cs = getComputedStyle(el);
          return { mask: cs.maskImage || cs.getPropertyValue('-webkit-mask-image'), opacity: cs.opacity };
        });
    const live = await mask('glow-live');
    const still = await mask('glow-still');
    expect(live.mask).toContain('feGaussianBlur');
    expect(live.opacity).toBe('1');
    expect(still.mask).not.toContain('feGaussianBlur');
    expect(Number(still.opacity)).toBeLessThan(1);
    // The 'thinking' ring is rotated by transform only.
    const rot = await cell(page, 'glow-thinking')
      .locator('[data-glow-ring]')
      .evaluate((el) => getComputedStyle(el).transform);
    expect(rot).not.toBe('none');
  });

  test('defaults to the faint border without html.motion and the full glow with it', async ({ page }) => {
    const auto = cell(page, 'glow-auto').locator('[data-glow]');
    const read = () => auto.evaluate((el) => getComputedStyle(el).maskImage || getComputedStyle(el).getPropertyValue('-webkit-mask-image'));
    expect(await read()).not.toContain('feGaussianBlur');
    await page.evaluate(() => document.documentElement.classList.add('motion'));
    expect(await read()).toContain('feGaussianBlur');
  });
});

test.describe('DictationWave', () => {
  test('draws 24 bars, 3 pt wide with 2 pt gaps, at waveHeights(progress)', async ({ page }) => {
    const wave = cell(page, 'wave-speaking').locator('[data-wave]');
    const bars = wave.locator('[data-wave-bar]');
    await expect(bars).toHaveCount(24);
    const seed = Number(await wave.getAttribute('data-seed'));
    const progress = Number(await wave.getAttribute('data-progress'));
    const want = waveHeights(progress, seed, 24);
    const geo = await bars.evaluateAll((els) => {
      const pt = els[0]!.closest('.screen')!.getBoundingClientRect().width / 393;
      return els.map((el) => {
        const m = new DOMMatrixReadOnly(getComputedStyle(el).transform);
        return { w: el.getBoundingClientRect().width / pt, left: el.getBoundingClientRect().left / pt, scaleY: m.d };
      });
    });
    geo.forEach((g, i) => {
      expect(near(g.w, 3, 0.3), `bar ${i} width ${g.w}`).toBe(true);
      expect(g.scaleY).toBeCloseTo(want[i]!, 2);
      if (i > 0) expect(near(g.left - geo[i - 1]!.left, 5, 0.3), `bar ${i} pitch`).toBe(true);
    });
  });

  test('types the transcript as pre-split words, and rests as dots at progress 1', async ({ page }) => {
    const speaking = cell(page, 'wave-speaking');
    const t = (await speaking.locator('[data-transcript]').textContent())!.replace(/\s+/g, ' ').trim();
    expect(t).toBe(SIRI.shiftNote.answer);
    await expect(speaking.locator('[data-transcript] [data-word]')).toHaveCount(SIRI.shiftNote.answer.split(' ').length);
    const scales = await cell(page, 'wave-reply')
      .locator('[data-wave-bar]')
      .evaluateAll((els) => els.map((el) => new DOMMatrixReadOnly(getComputedStyle(el).transform).d));
    for (const s of scales) expect(s).toBeCloseTo(WAVE_MIN, 3);
  });
});

test.describe('DynamicIsland', () => {
  const sizes = { rest: [126, 37, 18.5], compact: [250, 37, 18.5], expanded: [371, 160, 44] } as const;

  for (const [size, [w, h, r]] of Object.entries(sizes)) {
    test(`${size}: ${w} × ${h} pt at y 11, centred, radius ${r}`, async ({ page }) => {
      const island = cell(page, `island-${size}`).locator('[data-island]');
      await expect(island).toHaveAttribute('data-size', size);
      const b = await boxPt(island);
      expect(near(b.w, w), `w ${b.w}`).toBe(true);
      expect(near(b.h, h), `h ${b.h}`).toBe(true);
      expect(near(b.y, 11), `y ${b.y}`).toBe(true);
      expect(near(b.x + b.w / 2, 393 / 2), `centre ${b.x + b.w / 2}`).toBe(true);
      expect(near(b.radius, r), `radius ${b.radius}`).toBe(true);
      // Centred without a transform, so scenes can tween width and keep transforms free.
      expect(await island.evaluate((el) => getComputedStyle(el).transform)).toBe('none');
      const op = (sel: string) => island.locator(sel).evaluate((el) => getComputedStyle(el).opacity);
      expect(await op('[data-island-compact]')).toBe(size === 'compact' ? '1' : '0');
      expect(await op('[data-island-expanded]')).toBe(size === 'expanded' ? '1' : '0');
    });
  }

  test('compact shows the row and the time; expanded shows place, timer and 40 pt buttons', async ({ page }) => {
    const compact = cell(page, 'island-compact').locator('[data-island-compact]');
    await expect(compact).toContainText('Row 37');
    await expect(compact).toContainText('6:29');
    const exp = cell(page, 'island-expanded').locator('[data-island-expanded]');
    await expect(exp).toContainText('North field · Block 2');
    await expect(exp.locator('[data-timer]')).toHaveText('6:29:10');
    await expect(exp.locator('[data-timer]')).toHaveAttribute('data-timer', 'fixed');
    await expect(exp.locator('[data-island-row="37"]')).toHaveText('Row 37');
    await expect(exp.locator('[data-island-row="38"]')).toHaveText('Row 38');
    await expect(exp.locator('[data-island-break]')).toHaveText('Break');
    const b = await boxPt(exp.locator('[data-island-break]'));
    expect(near(b.h, 40), `button h ${b.h}`).toBe(true);
    // Every button sits inside the island.
    const island = await boxPt(cell(page, 'island-expanded').locator('[data-island]'));
    expect(b.y + b.h).toBeLessThanOrEqual(island.y + island.h);
    // Timer digits use Plex Mono with tabular figures.
    const font = await exp.locator('[data-timer]').evaluate((el) => getComputedStyle(el).fontVariantNumeric);
    expect(font).toContain('tabular-nums');
  });

  test('scrubbing the lab slider morphs the island and moves the wave', async ({ page }) => {
    const panel = page.locator('.scrub');
    const island = panel.locator('[data-island]');
    const slider = page.locator('[data-scrub]');
    const scrub = (v: string) =>
      slider.evaluate((el, value) => {
        (el as HTMLInputElement).value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
      }, v);
    const before = await panel.locator('[data-wave-bar]').first().evaluate((el) => getComputedStyle(el).transform);
    await scrub('0.5');
    let b = await boxPt(island);
    expect(near(b.w, 250, 1)).toBe(true);
    await scrub('1');
    b = await boxPt(island);
    expect(near(b.w, 371, 1) && near(b.h, 160, 1)).toBe(true);
    expect(await island.locator('[data-island-expanded]').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    await scrub('0.3');
    const after = await panel.locator('[data-wave-bar]').first().evaluate((el) => getComputedStyle(el).transform);
    expect(after).not.toBe(before);
  });
});

test.describe('ControlsCard', () => {
  test('is real text: three 64 px round tiles and the Action button label', async ({ page }) => {
    const card = cell(page, 'controls-wide').locator('[data-controls]');
    for (const [id, label] of [
      ['next-row', 'Next row'],
      ['break', 'Break'],
      ['clock-in', 'Clock in'],
    ]) {
      const tile = card.locator(`[data-control="${id}"]`);
      await expect(tile).toHaveText(label!);
      const circle = await tile.locator('.cc-circle').boundingBox();
      expect(circle!.width).toBeCloseTo(64, 0);
      expect(circle!.height).toBeCloseTo(64, 0);
    }
    await expect(card).toContainText('Action button');
    await expect(card.locator('[data-action-label]')).toContainText('Next row');
    await expect(card.getByRole('list', { name: 'Control Center' })).toBeVisible();
  });

  test('highlights the Action button in gold only when asked', async ({ page }) => {
    const glow = (id: string) => cell(page, id).locator('[data-action-button]');
    await expect(glow('controls-wide')).toBeVisible();
    expect(await glow('controls-wide').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    await expect(glow('controls-plain')).toBeHidden();
    const fill = await cell(page, 'controls-wide').locator('[data-action-key]').evaluate((el) => getComputedStyle(el).fill);
    expect(fill).toBe('rgb(226, 166, 68)');
  });

  test('fills its container at desktop and mobile widths', async ({ page }) => {
    for (const id of ['controls-wide', 'controls-narrow']) {
      const [cardW, cellW] = await cell(page, id).evaluate((el) => [
        el.querySelector('[data-controls]')!.getBoundingClientRect().width,
        el.getBoundingClientRect().width,
      ]);
      expect(cardW, id).toBeGreaterThan(cellW - 1);
      expect(cardW, id).toBeGreaterThan(280);
    }
  });
});

test('axe: no serious or critical violations on the lab page', async ({ page }) => {
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  const bad = results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
  expect(bad).toEqual([]);
});

test('no horizontal overflow', async ({ page }) => {
  expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)).toBeLessThanOrEqual(0);
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('the static lab page shows every final layer and the faint glow', async ({ page }) => {
    await page.goto(URL);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    const mask = await cell(page, 'glow-auto')
      .locator('[data-glow]')
      .evaluate((el) => getComputedStyle(el).maskImage || getComputedStyle(el).getPropertyValue('-webkit-mask-image'));
    expect(mask).not.toContain('feGaussianBlur');
    await expect(cell(page, 'island-expanded').locator('[data-island-expanded]')).toBeVisible();
    // Nothing in the ControlsCard (it sits in copy beats) is faded on the static page.
    const faded = await page
      .locator('[data-controls], [data-controls] *')
      .evaluateAll((els) => els.filter((e) => Number(getComputedStyle(e).opacity) < 1).map((e) => e.outerHTML.slice(0, 80)));
    expect(faded).toEqual([]);
  });
});
