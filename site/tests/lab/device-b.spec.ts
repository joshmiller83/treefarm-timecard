/**
 * Lab: device-b. Renders every state of DynamicIsland, SiriSnippet, SiriGlow, DictationWave
 * and ControlsCard and checks the geometry and hooks in src/components/CONTRACT.md, plus how
 * they sit with device-a's lock screen and status bar.
 *
 *   npm run build && PW_PORT=4414 npx playwright test tests/lab/device-b.spec.ts --project=lab-desktop --project=lab-mobile
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';
import { SIRI } from '../../src/data/siri';
import { WAVE_MIN, waveHeights } from '../../src/scripts/wave';
import { watch } from '../e2e/helpers';

const URL = '/lab/device-b/';
const cell = (page: Page, id: string) => page.locator(`[data-lab-cell="${id}"]`);

/** Every lock screen with a Siri card in its top slot. */
const SNIPPET_CELLS = [
  'snippet-clock-in',
  'snippet-misheard',
  'snippet-misheard-no',
  'snippet-next-row',
  'snippet-back',
  'snippet-status',
  'snippet-break-ask',
  'snippet-tree-note',
  'snippet-clock-out-ask',
  'snippet-clock-out',
];
const CARD_CELLS = [...SNIPPET_CELLS, 'glow-still', 'glow-auto', 'wave-listen', 'wave-speaking', 'wave-reply', 'scrub-wave'];

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
    ...SNIPPET_CELLS,
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
    'crop-compact-live',
    'crop-expanded',
    'scrub-island',
    'scrub-wave',
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
    // '212 trees', '34 an hour', 'block 2' and 'row 35' each stay together (5 joins).
    await expect(words).toHaveCount(SIRI.howMany.reply.split(/\s+/).length - 5);
    await expect(words.first()).toHaveText('212\u00a0trees');
    await expect(words.first()).toHaveAttribute('data-word', '0');
    await expect(words.nth(2)).toHaveText('34\u00a0an\u00a0hour.');
  });

  test('wraps greedily and never starts a line with a unit split from its number', async ({ page }) => {
    for (const id of SNIPPET_CELLS) {
      const text = cell(page, id).locator('[data-snippet-text]');
      // text-wrap: pretty where the engine has it (Firefox does not yet); the line checks below hold everywhere.
      if (await text.evaluate(() => CSS.supports('text-wrap', 'pretty')))
        expect(await text.evaluate((el) => getComputedStyle(el).textWrapStyle || getComputedStyle(el).getPropertyValue('text-wrap')), id).toContain(
          'pretty',
        );
      const starts = await text.evaluate((el) => {
        const out: string[] = [];
        let top = -Infinity;
        for (const w of Array.from(el.querySelectorAll<HTMLElement>('[data-word]'))) {
          const rects = w.getClientRects();
          if (rects.length !== 1) out.push(`split: ${w.textContent}`);
          const t = rects[0]!.top;
          if (t > top + 2) out.push(w.textContent!.replace(/\u00a0/g, ' '));
          top = t;
        }
        return out;
      });
      // A unit may not open a line apart from its number ('26 / rows ahead'); 'row 14' (unit first, kept whole) may.
      for (const line of starts)
        expect(line, `${id}: a line starts with "${line}"`).not.toMatch(/^(split:|minutes?\b|hours?\b|seconds?\b|trees?\b|rows?\b(?! \d)|an hour\b)/);
    }
    // '8 hours 30 minutes' stays on one line.
    const dur = cell(page, 'snippet-clock-out').locator('[data-word]', { hasText: 'hours' });
    await expect(dur).toHaveText('8\u00a0hours\u00a030\u00a0minutes,');
  });

  test('hides the lock screen’s date, big clock and padlock while a card is in the top slot', async ({ page }) => {
    const chrome = (id: string) =>
      cell(page, id)
        .locator('[data-lock]')
        .evaluate((lock) =>
          Array.from(lock.children)
            .filter((el) => el.matches('[data-date], [data-clock], [data-padlock]'))
            .map((el) => ({ hook: el.getAttribute('class') ?? el.tagName, opacity: getComputedStyle(el).opacity })),
        );
    for (const id of CARD_CELLS) {
      const parts = await chrome(id);
      expect(parts.length, `${id} has a date and a clock`).toBeGreaterThanOrEqual(2);
      for (const p of parts) expect(p.opacity, `${id} ${p.hook}`).toBe('0');
    }
    // Without a card (the glow alone) the lock screen keeps its clock.
    for (const p of await chrome('glow-live')) expect(p.opacity, `glow-live ${p.hook}`).toBe('1');
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
    // A 12 pt stroke centred on the edge: 6 pt of it inside the screen.
    expect(still.mask).toMatch(/stroke-width=(\\?['"])12\1/);
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
  /** Each bar's --h, the middle part's height and the round caps' offsets, in pt. */
  const bars = (loc: Locator) =>
    loc.locator('[data-wave-bar]').evaluateAll((els) => {
      const pt = els[0]!.closest('.screen')!.getBoundingClientRect().width / 393;
      return els.map((el) => {
        const r = el.getBoundingClientRect();
        const mid = el.querySelector('b')!.getBoundingClientRect();
        const cap = (which: '::before' | '::after') => {
          const cs = getComputedStyle(el, which);
          return { ty: new DOMMatrixReadOnly(cs.transform).f / pt, h: parseFloat(cs.height) / pt, radius: cs.borderRadius };
        };
        return { h: Number(el.style.getPropertyValue('--h')), w: r.width / pt, left: r.left / pt, mid: mid.height / pt, top: cap('::before'), bottom: cap('::after') };
      });
    });

  test('draws 24 capsule bars, 3 pt wide with 2 pt gaps, at waveHeights(progress)', async ({ page }) => {
    const wave = cell(page, 'wave-speaking').locator('[data-wave]');
    await expect(wave.locator('[data-wave-bar]')).toHaveCount(24);
    const seed = Number(await wave.getAttribute('data-seed'));
    const progress = Number(await wave.getAttribute('data-progress'));
    const want = waveHeights(progress, seed, 24);
    const geo = await bars(wave);
    geo.forEach((g, i) => {
      expect(near(g.w, 3, 0.3), `bar ${i} width ${g.w}`).toBe(true);
      expect(g.h).toBeCloseTo(want[i]!, 3);
      if (i > 0) expect(near(g.left - geo[i - 1]!.left, 5, 0.3), `bar ${i} pitch`).toBe(true);
      // A capsule h·36 pt tall: the middle runs between the centres of two 3 pt round caps.
      expect(near(g.mid, g.h * 36 - 3, 0.2), `bar ${i} middle ${g.mid}`).toBe(true);
      expect(near(g.bottom.ty, g.h * 18 - 1.5, 0.1), `bar ${i} bottom cap ${g.bottom.ty}`).toBe(true);
      expect(near(g.top.ty, -(g.h * 18 - 1.5), 0.1), `bar ${i} top cap ${g.top.ty}`).toBe(true);
      expect(near(g.top.h, 3, 0.1) && g.top.radius === '50%').toBe(true);
    });
  });

  test('types the transcript as pre-split words, and rests as round dots at progress 1', async ({ page }) => {
    const speaking = cell(page, 'wave-speaking');
    const t = (await speaking.locator('[data-transcript]').textContent())!.replace(/\s+/g, ' ').trim();
    expect(t).toBe(SIRI.shiftNote.answer);
    await expect(speaking.locator('[data-transcript] [data-word]')).toHaveCount(SIRI.shiftNote.answer.split(' ').length);
    await page.locator('[data-scrub]').evaluate((el) => {
      (el as HTMLInputElement).value = '1';
      el.dispatchEvent(new Event('input', { bubbles: true }));
    });
    for (const g of await bars(cell(page, 'scrub-wave').locator('[data-wave]'))) {
      expect(g.h).toBeCloseTo(WAVE_MIN, 3);
      // 3 pt wide, 3.6 pt tall: a dot, not a square.
      expect(near(g.mid, WAVE_MIN * 36 - 3, 0.1)).toBe(true);
    }
  });

  test('shows Listening… before there is a transcript', async ({ page }) => {
    await expect(cell(page, 'wave-listen').locator('[data-listening]')).toHaveText('Listening…');
    await expect(cell(page, 'wave-listen').locator('[data-transcript]')).toHaveCount(0);
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
      // The camera lens stays put at x 241, y 29.5 pt whatever the size.
      const lens = await boxPt(island.locator('[data-island-lens]'));
      expect(near(lens.x + lens.w / 2, 241, 0.5) && near(lens.y + lens.h / 2, 29.5, 0.5), `lens ${lens.x + lens.w / 2}, ${lens.y + lens.h / 2}`).toBe(true);
      expect(near(lens.w, 11, 0.2)).toBe(true);
    });
  }

  test('compact keeps its content off the camera cutout (x 133.5–259.5)', async ({ page }) => {
    for (const id of ['island-compact', 'island-app']) {
      const c = cell(page, id).locator('[data-island-compact]');
      const lead = await boxPt(c.locator('.isl-lead'));
      const trail = await boxPt(c.locator('.isl-trail'));
      expect(lead.x, `${id} lead left`).toBeGreaterThanOrEqual(71.5 + 6);
      expect(lead.x + lead.w, `${id} lead right`).toBeLessThanOrEqual(129.5);
      expect(trail.x, `${id} trail left`).toBeGreaterThanOrEqual(263.5);
      expect(trail.x + trail.w, `${id} trail right`).toBeLessThanOrEqual(321.5 - 8);
      // Both on the camera's centre line.
      expect(near(lead.y + lead.h / 2, 29.5, 1), `${id} lead centre ${lead.y + lead.h / 2}`).toBe(true);
      expect(near(trail.y + trail.h / 2, 29.5, 1), `${id} trail centre ${trail.y + trail.h / 2}`).toBe(true);
    }
  });

  test('expanded: badge and pill sit on the camera line, the pill clear of the cutout', async ({ page }) => {
    const exp = cell(page, 'island-expanded').locator('[data-island-expanded]');
    const pill = await boxPt(exp.locator('.isl-pill'));
    const badge = await boxPt(exp.locator('.isl-badge'));
    expect(pill.x, `pill left ${pill.x}`).toBeGreaterThanOrEqual(265.5);
    expect(near(pill.y + pill.h / 2, 29.5, 0.5), `pill centre ${pill.y + pill.h / 2}`).toBe(true);
    expect(near(badge.y + badge.h / 2, 29.5, 0.5), `badge centre ${badge.y + badge.h / 2}`).toBe(true);
    expect(badge.x + badge.w).toBeLessThanOrEqual(133.5);
    // The same solid pill as the Live Activity's 'On the clock'.
    const colors = await exp.locator('.isl-pill').evaluate((el) => [getComputedStyle(el).backgroundColor, getComputedStyle(el).color]);
    expect(colors).toEqual(['rgb(46, 122, 78)', 'rgb(255, 255, 255)']);
  });

  test('the status bar yields: the time clears the island, only the battery stays', async ({ page }) => {
    for (const id of ['island-compact', 'island-app']) {
      const screen = cell(page, id).locator('.screen');
      const res = await screen.evaluate((sc) => {
        const pt = sc.getBoundingClientRect().width / 393;
        const s = sc.getBoundingClientRect();
        const island = sc.querySelector('[data-island]')!.getBoundingClientRect();
        const bar = sc.querySelector('[data-statusbar]')!;
        const seen = (el: Element) => {
          let o = 1;
          for (let e: Element | null = el; e && e !== bar.parentElement; e = e.parentElement) {
            const cs = getComputedStyle(e);
            if (cs.visibility === 'hidden' || cs.display === 'none') return 0;
            o *= Number(cs.opacity);
          }
          return o;
        };
        const time = bar.querySelector('[data-clock]')!.getBoundingClientRect();
        const hits = Array.from(bar.querySelectorAll('*'))
          .filter((el) => el.children.length === 0 && seen(el) > 0.01)
          .map((el) => ({ el, r: el.getBoundingClientRect() }))
          .filter(({ r }) => r.width > 0 && r.right > island.left && r.left < island.right && r.bottom > island.top && r.top < island.bottom)
          .map(({ el }) => el.outerHTML.slice(0, 60));
        return {
          timeRight: (time.right - s.left) / pt,
          timeLeft: (time.left - s.left) / pt,
          islandLeft: (island.left - s.left) / pt,
          hits,
          timeSeen: seen(bar.querySelector('[data-clock]')!),
        };
      });
      expect(res.timeSeen, `${id} time visible`).toBeGreaterThan(0.99);
      expect(res.timeRight, `${id} time right ${res.timeRight}`).toBeLessThanOrEqual(res.islandLeft - 4);
      expect(res.timeLeft, `${id} time left ${res.timeLeft}`).toBeGreaterThanOrEqual(10);
      expect(res.hits, `${id}: status glyphs under the island`).toEqual([]);
    }
    // Expanded, the island covers the bar and the bar fades out.
    const sb = await cell(page, 'island-expanded').locator('[data-statusbar]').evaluate((el) => getComputedStyle(el).opacity);
    expect(sb).toBe('0');
    // At rest nothing yields.
    const rest = cell(page, 'island-rest').locator('[data-statusbar]');
    expect(await rest.locator('[data-wifi]').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    expect(await rest.locator('[data-clock]').evaluate((el) => getComputedStyle(el).translate)).toMatch(/^(none|0px)$/);
  });

  test('compact shows the row and the time; expanded shows place, timer and 40 pt buttons', async ({ page }) => {
    const compact = cell(page, 'island-compact').locator('[data-island-compact]');
    await expect(compact).toContainText('Row 37');
    await expect(compact.locator('[data-island-time]')).toHaveText('6:29');
    await expect(compact.locator('[data-island-time]')).toHaveAttribute('data-timer', 'fixed');
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

  test('live: the compact time is a DayClock timer clipped to H:MM', async ({ page }) => {
    const island = cell(page, 'crop-compact-live').locator('[data-island]');
    const time = island.locator('[data-island-time]');
    await expect(time).toHaveAttribute('data-timer', 'worked');
    await expect(island.locator('[data-island-expanded] [data-timer]')).toHaveAttribute('data-timer', 'worked');
    // DayClock writes H:MM:SS; only H:MM shows.
    const fit = await time.evaluate((el) => {
      const probe = document.createElement('span');
      probe.textContent = '6:29';
      probe.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap';
      el.appendChild(probe);
      const w = probe.getBoundingClientRect().width;
      probe.remove();
      return { text: el.textContent, box: el.getBoundingClientRect().width, hm: w, overflow: el.scrollWidth > el.clientWidth };
    });
    expect(fit.text).toBe('6:29:10');
    expect(fit.overflow).toBe(true);
    expect(Math.abs(fit.box - fit.hm)).toBeLessThan(1);
  });

  test('scrubbing the lab slider morphs the island, yields the status bar and moves the wave', async ({ page }) => {
    const island = cell(page, 'scrub-island').locator('[data-island]');
    const bar = cell(page, 'scrub-island').locator('[data-statusbar]');
    const slider = page.locator('[data-scrub]');
    const scrub = (v: string) =>
      slider.evaluate((el, value) => {
        (el as HTMLInputElement).value = value;
        el.dispatchEvent(new Event('input', { bubbles: true }));
      }, v);
    const css = (loc: Locator, prop: string) => loc.evaluate((el, p) => getComputedStyle(el).getPropertyValue(p), prop);
    const firstBar = cell(page, 'scrub-wave').locator('[data-wave-bar]').first();
    const before = await firstBar.evaluate((el) => el.style.getPropertyValue('--h'));
    await scrub('0');
    let b = await boxPt(island);
    expect(near(b.w, 126, 1)).toBe(true);
    expect(await css(bar.locator('[data-wifi]'), 'opacity')).toBe('1');
    expect(await css(bar.locator('[data-clock]'), 'translate')).toMatch(/^(none|0px( 0px)?)$/);
    await scrub('0.5');
    b = await boxPt(island);
    expect(near(b.w, 250, 1)).toBe(true);
    expect(await css(bar.locator('[data-wifi]'), 'opacity')).toBe('0');
    expect(await css(bar.locator('[data-clock]'), 'translate')).not.toMatch(/^(none|0px)/);
    expect(await css(bar, 'opacity')).toBe('1');
    await scrub('1');
    b = await boxPt(island);
    expect(near(b.w, 371, 1) && near(b.h, 160, 1)).toBe(true);
    expect(await island.locator('[data-island-expanded]').evaluate((el) => getComputedStyle(el).opacity)).toBe('1');
    expect(await css(bar, 'opacity')).toBe('0');
    await scrub('0.3');
    const after = await firstBar.evaluate((el) => el.style.getPropertyValue('--h'));
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

  test('the edge sketch fades out inside its own box, never clipped by the card', async ({ page }) => {
    for (const id of ['controls-wide', 'controls-narrow']) {
      const geo = await cell(page, id).evaluate((c) => {
        const sketch = c.querySelector('.cc-sketch')!;
        const action = c.querySelector('.cc-action')!.getBoundingClientRect();
        const cs = getComputedStyle(sketch);
        return {
          mask: cs.maskImage || cs.getPropertyValue('-webkit-mask-image'),
          bottom: sketch.getBoundingClientRect().bottom,
          clip: action.bottom,
        };
      });
      expect((geo.mask.match(/linear-gradient/g) ?? []).length, id).toBe(2);
      expect(geo.bottom, `${id} sketch bottom`).toBeLessThanOrEqual(geo.clip + 0.5);
    }
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
