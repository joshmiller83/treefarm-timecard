/**
 * VOICE section: content, the static transcript, the scrubbed clock and the acceptance checks
 * from the brief (jq '.sections[] | select(.id=="voice") | .acceptance' docs/landing/brief.json).
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { SIRI } from '../../src/data/siri';
import { breakAt, fmtClock, fmtHMS, workedAt } from '../../src/data/ledger';
import { place, type PartId } from '../../src/sections/voice/model';

const SAID = [SIRI.misheard.said, SIRI.nextRow.said, SIRI.takeLunch.said, SIRI.backToWork.said, SIRI.howMany.said];
const REPLIES = [SIRI.misheard.reply, SIRI.nextRow.reply, SIRI.backToWork.reply, SIRI.howMany.reply];
const PAY = 'On a locked phone, Siri only says your pay out loud if you allow it.';
const norm = (s: string | null) => (s ?? '').replace(/ /g, ' ').replace(/\s+/g, ' ').trim();

async function serious(page: Page) {
  const results = await new AxeBuilder({ page })
    .include('#voice')
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice'])
    .analyze();
  return results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
}

const overflow = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

test.describe('reduced motion: a static transcript', () => {
  test.use({ reducedMotion: 'reduce' });

  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
  });

  test('every line is there, word for word, at full opacity', async ({ page }) => {
    const voice = page.locator('#voice');
    await voice.scrollIntoViewIfNeeded();
    await expect(page.getByRole('heading', { level: 2, name: 'Say it. Keep cutting.' })).toBeVisible();
    await expect(voice.locator('.beat-head .eyebrow')).toHaveText(/7:18 AM · Voice first/i);

    // Five commands, each naming Time Card, plus the "No." answer.
    const said = (await voice.locator('.x-you q').allTextContents()).map(norm);
    expect(said).toEqual([SAID[0], SIRI.misheard.answer, ...SAID.slice(1)]);
    for (const s of SAID) expect(s).toContain('Time Card');

    // Siri's replies match siri.ts exactly.
    expect((await voice.locator('.x-reply').allTextContents()).map(norm)).toEqual(REPLIES);
    expect(await voice.locator('time').allTextContents()).toEqual(['7:18 AM', '7:19 AM', '12:01 PM', '12:31 PM', '2:01 PM']);

    // The pay privacy rule is real text.
    await expect(voice.getByText(PAY)).toBeVisible();
    await expect(voice.getByText('Nothing changed.')).toBeVisible();

    // Everything is visible, and nothing in the section is faded.
    for (const loc of [voice.locator('.x-part'), voice.locator('.x-reply'), voice.locator('.x-said')]) {
      const n = await loc.count();
      for (let i = 0; i < n; i += 1) {
        await loc.nth(i).scrollIntoViewIfNeeded();
        await expect(loc.nth(i)).toBeVisible();
      }
    }
    const faded = await voice.locator('.beat, .beat *, figure, figure *').evaluateAll((els) =>
      els
        .filter((e) => !e.closest('[data-phone]') && Number(getComputedStyle(e).opacity) < 1)
        .map((e) => e.outerHTML.slice(0, 90)),
    );
    expect(faded).toEqual([]);
  });

  test('one phone at 2:01 in its pocket, and the Live Activity at lunch', async ({ page }) => {
    const voice = page.locator('#voice');
    const phone = voice.getByRole('img', { name: /2:01 PM.*pocket/ });
    await phone.scrollIntoViewIfNeeded();
    await expect(phone).toBeVisible();
    expect(norm(await phone.getAttribute('aria-label'))).toContain(norm(SIRI.howMany.reply));
    await expect(voice.locator('[data-screen="lock-1401-status"]')).toBeVisible();
    await expect(voice.locator('[data-screen="lock-1401-status"] [data-snippet]')).toBeVisible();
    await expect(voice.locator('.x-device [data-pocket]')).toBeVisible();
    // The caption is not under the pocket.
    const cap = await voice.locator('.x-shot figcaption').boundingBox();
    const pocket = await voice.locator('.x-device .pocket-clip').boundingBox();
    expect(cap!.y).toBeGreaterThanOrEqual(pocket!.y + pocket!.height - 1);

    const lunch = voice.getByRole('img', { name: /On lunch/ });
    await lunch.scrollIntoViewIfNeeded();
    await expect(lunch).toBeVisible();
    await expect(voice.getByText('On lunch: the lock screen turns gold.')).toBeVisible();
    await expect(voice.getByRole('list', { name: 'More to say:' }).getByRole('listitem')).toHaveCount(4);
  });

  test('axe: no serious or critical violations', async ({ page }) => {
    expect(await serious(page)).toEqual([]);
  });

  test('no horizontal overflow at 375', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.locator('#voice').scrollIntoViewIfNeeded();
    expect(await overflow(page)).toBeLessThanOrEqual(0);
  });
});

test.describe('with motion', () => {
  test.use({ reducedMotion: 'no-preference' });

  /** Boots the motion core, pauses the idle tick (so clocks hold still) and returns error sinks. */
  async function boot(page: Page) {
    const errors: string[] = [];
    page.on('pageerror', (e) => errors.push(e.message));
    page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.waitForFunction(() => !!(window as { __tf?: unknown }).__tf, null, { timeout: 8000 });
    await page.evaluate(() => (window as unknown as { __tf: { ready: Promise<void> } }).__tf.ready);
    await page.locator('[data-pause-toggle]').first().click();
    // Let the fonts-ready refresh land before aiming at trigger positions.
    await page.waitForTimeout(400);
    return errors;
  }

  /** Scrolls so that a part's own progress is `u`, and waits for the scrub to settle (re-aiming if a refresh moved the triggers). */
  async function scrubTo(page: Page, part: PartId, u: number) {
    const desk = (page.viewportSize()?.width ?? 0) >= 900;
    const { src, p } = place(part, u, desk);
    for (let attempt = 0; attempt < 4; attempt += 1) {
      const y = await page.evaluate(
        ({ src, p, desk }) => {
          const sec = document.getElementById('voice')!;
          const trigger = sec.querySelector(desk ? `[data-x="${src}"]` : `[data-part="${src}"]`);
          const tf = (window as unknown as { __tf: { ScrollTrigger: { getAll(): Array<{ trigger: Element; start: number; end: number }> } } }).__tf;
          const st = tf.ScrollTrigger.getAll().find((s) => s.trigger === trigger);
          if (!st) throw new Error(`no trigger for ${src}`);
          return st.start + p * (st.end - st.start);
        },
        { src, p, desk },
      );
      await page.evaluate((top) => window.scrollTo(0, top), Math.round(y));
      // Scrub .6 s: wait until every timeline has caught up with its trigger.
      await page.waitForFunction(
        () => {
          const tf = (window as unknown as { __tf: { ScrollTrigger: { getAll(): Array<{ progress: number; animation?: { progress(): number } }> } } }).__tf;
          return tf.ScrollTrigger.getAll().every((s) => !s.animation || Math.abs(s.animation.progress() - s.progress) < 0.0005);
        },
        null,
        { timeout: 5000 },
      );
      await page.waitForTimeout(150);
      const actual = await page.evaluate(
        ({ src, desk }) => {
          const sec = document.getElementById('voice')!;
          const trigger = sec.querySelector(desk ? `[data-x="${src}"]` : `[data-part="${src}"]`);
          const tf = (window as unknown as { __tf: { ScrollTrigger: { getAll(): Array<{ trigger: Element; animation?: { progress(): number } }> } } }).__tf;
          return tf.ScrollTrigger.getAll().find((s) => s.trigger === trigger)?.animation?.progress() ?? -1;
        },
        { src, desk },
      );
      if (Math.abs(actual - p) < 0.004) return;
    }
    throw new Error(`could not scrub ${part} to ${u}`);
  }

  /** The top visible screen layer's readings, with the DayClock minute. */
  const read = (page: Page) =>
    page.evaluate(() => {
      const tf = (window as unknown as { __tf: { day: { now(): { min: number } } } }).__tf;
      const layers = Array.from(document.querySelectorAll<HTMLElement>('[data-screen^="lock-"]')).filter((l) =>
        /^lock-(0718|0719|1201|1231|1401)/.test(l.dataset.screen ?? ''),
      );
      const top = layers.filter((l) => Number(getComputedStyle(l).opacity) > 0.99).pop()!;
      const la = top.querySelector('[data-la]')!;
      return {
        min: tf.day.now().min,
        layer: top.dataset.screen,
        clock: top.querySelector('[data-lock] > [data-clock]')!.textContent,
        barClock: top.querySelector('[data-statusbar] [data-clock]')!.textContent,
        timer: la.querySelector('.odo[data-timer]')!.getAttribute('data-odo-text'),
        state: la.getAttribute('data-state'),
        trees: la.querySelector('[data-trees]')!.getAttribute('data-odo-text'),
        rows: Array.from(la.querySelectorAll('[data-row]')).map((r) => r.textContent!.trim()),
        track: getComputedStyle(la.querySelector('[data-strip-track]')!).transform,
        worked: la.querySelector('[data-worked-line]')!.textContent!.replace(/\s+/g, ' ').trim(),
        workedOpacity: getComputedStyle(la.querySelector('[data-worked-line]')!).opacity,
        pill: (() => {
          const f = la.querySelector<HTMLElement>('[data-pill-face="break"]')!;
          const cs = getComputedStyle(f);
          return { opacity: cs.opacity, bg: cs.backgroundColor, color: cs.color, text: f.textContent!.trim() };
        })(),
      };
    });

  const ledgerTimer = (min: number) => {
    const b = breakAt(min);
    return fmtHMS(b ? b.seconds : workedAt(min));
  };

  test('the clocks always match the ledger at the current day.min', async ({ page }) => {
    const errors = await boot(page);
    const spots: Array<[PartId, number, string, string, string]> = [
      ['misheard', 0.5, 'lock-0718-misheard', '7:18', '0:16:00'],
      ['next', 0.6, 'lock-0719-next', '7:19', '0:17:00'],
      ['lunchB', 0.25, 'lock-1231-back', '12:31', '0:30:00'],
      ['status', 0.6, 'lock-1401-status', '2:01', '6:14:00'],
    ];
    for (const [part, u, layer, clock, timer] of spots) {
      await scrubTo(page, part, u);
      const r = await read(page);
      expect(r.layer, `${part} ${u}`).toBe(layer);
      expect(r.clock).toBe(fmtClock(r.min));
      expect(r.barClock).toBe(fmtClock(r.min));
      expect(r.timer).toBe(ledgerTimer(r.min));
      expect([r.clock, r.timer]).toEqual([clock, timer]);
    }
    // And somewhere in the middle of the morning's time-lapse.
    await scrubTo(page, 'lunchA', 0.15);
    const mid = await read(page);
    expect(mid.clock).toBe(fmtClock(mid.min));
    expect(mid.timer).toBe(ledgerTimer(mid.min));
    expect(errors).toEqual([]);
  });

  test('the misheard check changes nothing on the Live Activity after .6', async ({ page }) => {
    await boot(page);
    const at = async (u: number) => {
      await scrubTo(page, 'misheard', u);
      return page.evaluate(() => {
        const la = document.querySelector('[data-screen="lock-0718-misheard"] [data-la]')!;
        return {
          trees: la.querySelector('[data-trees]')!.getAttribute('data-odo-text'),
          rows: Array.from(la.querySelectorAll('[data-row]')).map((r) => [r.textContent!.trim(), getComputedStyle(r).transform]),
          track: getComputedStyle(la.querySelector('[data-strip-track]')!).transform,
          pill: la.querySelector('[data-pill-face="clock"]')!.textContent!.trim(),
        };
      });
    };
    const first = await at(0.6);
    expect(first.trees).toBe('0');
    for (const u of [0.7, 0.8, 0.9, 1]) expect(await at(u)).toEqual(first);
  });

  test('lunch: gold #E2A644 with #2A1C04 text, worked frozen at 4:44:00', async ({ page }) => {
    await boot(page);
    await scrubTo(page, 'lunchB', 0.2);
    const r = await read(page);
    expect(r.state).toBe('lunch');
    expect(r.pill).toEqual({ opacity: '1', bg: 'rgb(226, 166, 68)', color: 'rgb(42, 28, 4)', text: 'On lunch' });
    expect(r.worked).toBe('4:44:00 worked');
    expect(r.workedOpacity).toBe('1');
    // Back at 12:31 the card turns green again and worked time picks up.
    // (Before .55: on desktop the 2:01 exchange starts moving the clock at about .58.)
    await scrubTo(page, 'lunchB', 0.55);
    const back = await read(page);
    expect(back.state).toBe('working');
    expect(back.timer).toBe('4:44:00');
    expect(back.rows.slice(0, 3)).toEqual(['Row 30', 'Row 31', 'Row 32']);
  });

  test('karaoke lights the line, the reply appears, the pay rule stays in the DOM', async ({ page }) => {
    await boot(page);
    const said = page.locator('[data-part="status"] [data-turn="said"] .w');
    const reply = page.locator('[data-part="status"] .x-reply .w');
    await scrubTo(page, 'status', 0.05);
    expect(Number(await said.first().evaluate((e) => getComputedStyle(e).opacity))).toBeCloseTo(0.25, 2);
    expect(Number(await reply.last().evaluate((e) => getComputedStyle(e).opacity))).toBe(0);
    await scrubTo(page, 'status', 0.9);
    for (const loc of [said.last(), reply.last()]) expect(Number(await loc.evaluate((e) => getComputedStyle(e).opacity))).toBe(1);
    await expect(page.locator('#voice').getByText(PAY)).toBeAttached();
  });

  test('the section starts and ends with the phone at rest, and nothing overflows', async ({ page }) => {
    const errors = await boot(page);
    const sec = page.locator('#voice');
    await sec.scrollIntoViewIfNeeded();
    const range = await page.evaluate(() => {
      const tr = document.querySelector('#voice .track') as HTMLElement;
      const top = tr.getBoundingClientRect().top + scrollY;
      return [top - innerHeight, top + tr.offsetHeight];
    });
    for (let i = 0; i <= 12; i += 1) {
      await page.evaluate((y) => window.scrollTo(0, y), Math.round(range[0]! + ((range[1]! - range[0]!) * i) / 12));
      await page.waitForTimeout(80);
      expect(await overflow(page), `step ${i}`).toBeLessThanOrEqual(0);
    }
    // At the end the pocket is away and the full 2:01 lock screen shows.
    const end = await page.evaluate(() => {
      const tr = document.querySelector('#voice .track') as HTMLElement;
      return tr.getBoundingClientRect().top + scrollY + tr.offsetHeight - innerHeight;
    });
    await page.evaluate((y) => window.scrollTo(0, y), Math.round(end));
    await page.waitForTimeout(900);
    const r = await read(page);
    expect(r.layer).toBe('lock-1401-status');
    expect(r.trees).toBe('212');
    const pocketY = await page.evaluate(() => {
      const desk = innerWidth >= 900;
      const p = document.querySelector<HTMLElement>(desk ? '#voice .x-stage-pocket [data-pocket]' : '#voice .x-device [data-pocket]')!;
      return getComputedStyle(p).transform;
    });
    expect(pocketY).not.toBe('none');
    expect(pocketY).not.toMatch(/matrix\(1, 0, 0, 1, 0, 0\)/);
    expect(errors).toEqual([]);
  });
});
