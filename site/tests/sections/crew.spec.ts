/**
 * THE CREW chapter (2:47 PM · Block 3): present, complete without motion, labelled for
 * screen readers, aligned to the stage phone on desktop and inside the viewport at 375.
 * Runs against the built site, like tests/e2e.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { AT, AT_MOB } from '../../src/sections/crew/schedule';
import { settle, watch } from '../e2e/helpers';

const CONFLICT = 'Row 12 was shaped by Sam on Oct 16.';
const LINES = [
  'No signal at the back of the field? Keep working. Time Card saves your marks on your phone and syncs when you’re back in range.',
  'If two people mark the same tree, the first one counts, and the other phone says so:',
  'Farm owners and crew leads are admins. They invite people with a code, set up fields and blocks, and see everyone’s hours and reports.',
  'Workers see only their own hours and pay.',
  'The crew shares one small server that your farm runs itself.',
];
const squash = (s: string) => s.replace(/\s+/g, ' ').trim();
const overflow = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);

/** Scrolls so the crew track's scrubbed progress is p (0–1) and lets the scrub settle. */
async function toProgress(page: Page, p: number, wait = 900) {
  await page.evaluate((p) => {
    const track = document.querySelector<HTMLElement>('#crew .track')!;
    const top = track.getBoundingClientRect().top + scrollY;
    window.scrollTo(0, Math.round(top + p * (track.offsetHeight - innerHeight)));
  }, p);
  await page.waitForTimeout(wait);
}

/** Computed opacity of the first element matching sel. */
const opacityOf = (page: Page, sel: string) => page.locator(sel).first().evaluate((e) => Number(getComputedStyle(e).opacity));

const LAYER = (id: string) => `[data-crew-screens] > [data-screen="${id}"]`;
const PEEK = (id: string) => `[data-crew-peek-screens] > [data-screen="${id}"]`;
const TEAM = PEEK('team-1500');

async function seriousIn(page: Page) {
  const r = await new AxeBuilder({ page }).include('#crew').withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  return r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`);
}

test.describe('reduced motion: the composed static chapter', () => {
  test.use({ reducedMotion: 'reduce' });

  test('shows the heading, all five lines, the message and three labelled phones', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    const sec = page.locator('#crew');
    await sec.scrollIntoViewIfNeeded();
    await expect(page.getByRole('region', { name: 'One map for the whole crew.' })).toBeVisible();
    await expect(sec.locator('.eyebrow')).toHaveText(/2:47 PM · Block 3/i);
    const text = squash(await sec.locator('.beats').innerText());
    for (const line of LINES) expect(text).toContain(line);
    // The conflict message is real page text, exactly.
    const quote = sec.locator('.beats q');
    await expect(quote).toHaveText(CONFLICT);
    await expect(quote).toBeVisible();
    // Three phones, each one image with its own label; the figure and its caption show.
    const phones = sec.locator('figure [data-phone][role="img"]');
    await expect(phones).toHaveCount(3);
    for (let i = 0; i < 3; i += 1) {
      await phones.nth(i).scrollIntoViewIfNeeded();
      await expect(phones.nth(i)).toBeVisible();
    }
    await expect(sec.getByRole('img', { name: /no signal: No Service, rows 11 and 12 in gold, and the line Offline · 2 changes waiting/ })).toBeVisible();
    await expect(sec.getByRole('img', { name: new RegExp(`back in range: Synced, and the message ${CONFLICT.replace('.', '\\.')}`) })).toBeVisible();
    await expect(sec.getByRole('img', { name: /owner’s phone: the Team tab with this week’s hours, Alex 38:24, Sam 36:50, Rosa 31:15/ })).toBeVisible();
    await expect(sec.locator('figcaption')).toContainText(CONFLICT);
    await expect(sec.locator('figcaption')).toBeVisible();
    // The motion-only extras (second phone, wires) are not there at all.
    await expect(sec.locator('[data-crew-peek]')).toBeHidden();
    // The static mock of each state is the final one.
    await expect(sec.locator('[data-screen="trees-1500-synced"] [data-banner]').first()).toHaveText(CONFLICT);
    expect(await overflow(page)).toBeLessThanOrEqual(0);
    expect(problems).toEqual([]);
  });

  test('has no serious accessibility problems', async ({ page }) => {
    await page.goto('/');
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    await page.locator('#crew').scrollIntoViewIfNeeded();
    expect(await seriousIn(page)).toEqual([]);
  });

  test('never shows pay, an invite code or the crew server’s hostname', async ({ page }) => {
    await page.goto('/');
    const html = await page.locator('#crew').innerHTML();
    expect(html).not.toMatch(/\$\s?\d|joshnliz|expires|code:\s*[A-Z0-9]{4,}/i);
  });
});

test.describe('with motion', () => {
  test.skip(({ viewport }) => !viewport || viewport.width < 900, 'desktop stage only');

  test('scrubs the story and keeps the second phone on the stage phone after resizing', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/?motion=on');
    await settle(page);
    await expect(page.locator('html')).toHaveClass(/stage-on/);
    await toProgress(page, 0.05, 300);
    await toProgress(page, 0.3);
    const stage = page.locator('[data-stage] [data-phone]');
    // The section's screens are on the stage; the offline line shows after Alex's first mark.
    await expect(stage.locator('[data-screen="trees-1456-offline"] [data-sync-line]')).toBeVisible();
    await toProgress(page, 0.6, 1200);
    const banner = stage.locator('[data-screen="trees-1500-synced"] [data-banner]');
    await expect(banner).toHaveText(CONFLICT);
    expect(Number(await banner.evaluate((e) => getComputedStyle(e).opacity))).toBeGreaterThan(0.9);
    // The rig the second phone hangs on sits exactly on the stage phone (both carry the same
    // camera pull), resized mid-chapter to 1024, 1280 and 1440.
    for (const [w, h] of [
      [1024, 768],
      [1280, 800],
      [1440, 900],
    ] as const) {
      await page.setViewportSize({ width: w, height: h });
      await page.waitForTimeout(500);
      await toProgress(page, 0.24, 900); // between taps: no haptic shake on the stage phone
      const [rig, ph] = await Promise.all([page.locator('[data-crew-rig]').boundingBox(), stage.boundingBox()]);
      expect(rig && ph, `${w}`).toBeTruthy();
      for (const k of ['x', 'y', 'width', 'height'] as const) expect(Math.abs(rig![k] - ph![k]), `${w} ${k}`).toBeLessThanOrEqual(1.5);
      // The second phone peeks out from behind it, on screen, clear of the copy column.
      const peek = await page.locator('[data-crew-peek] [data-phone]').boundingBox();
      const copy = await page.locator('#crew .beat[data-beat="1"]').boundingBox();
      expect(peek!.x, `${w} peek on screen`).toBeGreaterThan(0);
      expect(peek!.x, `${w} peek left of the stage phone`).toBeLessThan(ph!.x);
      expect(peek!.x, `${w} peek clear of the copy`).toBeGreaterThan(copy!.x + copy!.width);
      expect(await overflow(page)).toBeLessThanOrEqual(0);
    }
    // At the end the second phone and the wires are gone and the stage phone is at rest.
    await toProgress(page, 1, 1200);
    expect(Number(await page.locator('[data-crew-peek]').evaluate((e) => getComputedStyle(e).opacity))).toBeLessThan(0.05);
    expect(await stage.evaluate((e) => getComputedStyle(e).transform)).toMatch(/none|matrix\(1, 0, 0, 1, 0, 0\)/);
    expect(problems).toEqual([]);
  });

  test('has no serious accessibility problems mid-story', async ({ page }) => {
    await page.goto('/?motion=on');
    await settle(page);
    for (const p of [0.3, 0.55, 0.75, 0.86]) {
      await toProgress(page, p);
      expect(await seriousIn(page), `at ${p}`).toEqual([]);
    }
  });

  test('scrubbed forward slowly, the Team tab’s rows wait for their turn', async ({ page }) => {
    await page.goto('/?motion=on');
    await settle(page);
    await toProgress(page, 0.55);
    // A slow forward scrub, the way most people read: a little at a time.
    for (let p = 0.56; p <= AT.rows[0] - 0.006; p += 0.01) await toProgress(page, p, 90);
    await toProgress(page, AT.rows[0] - 0.006, 900);
    for (const sel of ['[data-team-row]', '[data-team-total]', '[data-invite]', '[data-fields-row]']) {
      const ops = await page.locator(`${TEAM} ${sel}`).evaluateAll((els) => els.map((e) => Number(getComputedStyle(e).opacity)));
      expect(ops.length, sel).toBeGreaterThan(0);
      for (const o of ops) expect(o, `${sel} before the rows`).toBeLessThan(0.05);
    }
    for (let p = AT.rows[0]; p <= AT.invite[0] - 0.006; p += 0.01) await toProgress(page, p, 90);
    await toProgress(page, AT.invite[0] - 0.006, 900);
    for (const sel of ['[data-invite]', '[data-fields-row]']) expect(await opacityOf(page, `${TEAM} ${sel}`), `${sel} before its window`).toBeLessThan(0.05);
    const rows = await page.locator(`${TEAM} [data-team-row]`).evaluateAll((els) => els.map((e) => Number(getComputedStyle(e).opacity)));
    for (const o of rows) expect(o, 'rows in').toBeGreaterThan(0.95);
  });

  test('cuts to the Team tab, holds the banner, and never shows a half-faded phone in front', async ({ page }) => {
    await page.goto('/?motion=on');
    await settle(page);
    // The banner arrives early and holds.
    for (const p of [AT.banner[1] + 0.004, AT.bannerOut[0] - 0.004]) {
      await toProgress(page, p);
      expect(await opacityOf(page, `[data-stage] ${LAYER('trees-1500-synced')} [data-banner]`), `banner at ${p}`).toBeGreaterThan(0.9);
    }
    // Sam's map → the Team tab is a cut: one or the other, never both at once.
    for (const [p, s, t] of [
      [AT.teamCut - 0.004, 1, 0],
      [AT.teamCut + 0.004, 0, 1],
    ] as const) {
      await toProgress(page, p);
      expect(await opacityOf(page, PEEK('sam-1449-trees')), `Sam’s map at ${p}`).toBe(s);
      expect(await opacityOf(page, TEAM), `Team tab at ${p}`).toBe(t);
    }
    // The exit: while the second phone is in front of yours it stays opaque.
    await toProgress(page, 0.86);
    for (let p = AT.exit[0]; p <= AT.exit[1] + 0.001; p += 0.01) {
      await toProgress(page, p, 700);
      const { z, o } = await page.locator('[data-crew-peek]').evaluate((e) => ({ z: Number(getComputedStyle(e).zIndex), o: Number(getComputedStyle(e).opacity) }));
      if (z > 0) expect(o, `peek in front at ${p.toFixed(2)}`).toBeGreaterThan(0.98);
    }
  });

  test('keeps the owner’s name tag off the server when it lights up, on a short laptop screen', async ({ page }) => {
    await page.setViewportSize({ width: 1366, height: 657 });
    await page.goto('/?motion=on');
    await settle(page);
    await toProgress(page, 0.7, 400);
    await toProgress(page, AT.serverLit[1]);
    const [tag, srv] = await Promise.all([page.locator('[data-crew-chip="owner"]').boundingBox(), page.locator('[data-crew-server-in] [data-server-glyph]').boundingBox()]);
    const overlap = !!tag && !!srv && tag.x < srv.x + srv.width && srv.x < tag.x + tag.width && tag.y < srv.y + srv.height && srv.y < tag.y + tag.height;
    const tagOpacity = await opacityOf(page, '[data-crew-chip="owner"]');
    expect(!overlap || tagOpacity < 0.05, 'tag over the server').toBe(true);
    expect(await opacityOf(page, '[data-crew-server-in] [data-server-glyph]')).toBeGreaterThan(0.95);
  });
});

test.describe('at 375 with motion', () => {
  test.skip(({ viewport }) => !viewport || viewport.width >= 900, 'mobile only');

  test('keeps both phones inside the viewport through the whole track', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/?motion=on');
    await settle(page);
    for (const p of [0, 0.1, 0.25, 0.4, 0.58, 0.75, 0.85, 1]) {
      await toProgress(page, p, 500);
      expect(await overflow(page), `at ${p}`).toBeLessThanOrEqual(0);
      const box = await page.locator('[data-crew-peek] [data-phone]').boundingBox();
      if (box && box.width > 0) {
        expect(box.x, `peek left at ${p}`).toBeGreaterThanOrEqual(0);
        expect(box.x + box.width, `peek right at ${p}`).toBeLessThanOrEqual(375);
      }
    }
    // Mid-story the copy card quotes the message and the section phone is labelled.
    await expect(page.locator('#crew .beats q')).toHaveText(CONFLICT);
    await expect(page.locator('#crew figure [data-phone][role="img"]').first()).toHaveAttribute('aria-label', /Synced/);
    expect(problems).toEqual([]);
  });

  /** Each event of the story, at its own progress, and what has to be in view for it. */
  const A = AT_MOB;
  const mid = (w: readonly [number, number]) => (w[0] + w[1]) / 2;
  const EVENTS: Array<[string, number, string]> = [
    ['the bars go', A.barsOut[1], `${LAYER('trees-1447-block3')} [data-statusbar]`],
    ['Sam taps row 12', A.tap.sam, `${PEEK('sam-1449-trees')} [data-row-label="12"]`],
    ['Sam’s row 12 turns gold', A.samFill[1], `${PEEK('sam-1449-trees')} [data-map-row="12"]`],
    ['Sam’s change goes up', mid(A.packetSam), '[data-packet="sam"]'],
    ['you tap row 11', A.tap.row11, `${LAYER('trees-1456-offline')} [data-row-label="11"]`],
    ['row 11 turns gold', A.fill11[1], `${LAYER('trees-1456-offline')} [data-map-row="11"]`],
    ['you tap row 12', A.tap.row12, `${LAYER('trees-1456-offline')} [data-row-label="12"]`],
    ['2 changes waiting', A.count[1], `${LAYER('trees-1456-offline')} [data-sync-line]`],
    ['the bars come back', A.barsIn[1], `${LAYER('trees-1456-offline')} [data-statusbar]`],
    ['your changes go up', mid(A.packetsUp), '[data-packet="alex-2"]'],
    ['the server takes them', mid(A.pulseSync), '[data-crew-server-in] [data-server-glyph]'],
    ['Sam’s row comes down', mid(A.packetDown), '[data-packet="down-alex"]'],
    ['Synced', A.syncedIn[1], `${LAYER('trees-1500-synced')} [data-sync-line]`],
    ['row 12 turns green', A.green[1], `${LAYER('trees-1500-synced')} [data-map-row="12"]`],
    ['the banner', A.banner[1], `${LAYER('trees-1500-synced')} [data-banner]`],
    ['the banner holds', A.banner[1] + 0.03, `${LAYER('trees-1500-synced')} [data-banner]`],
    ['the Team tab’s rows', A.rows[1], `${PEEK('team-1500')} [data-team-row]`],
    ['Invite someone', A.invite[1], `${PEEK('team-1500')} [data-invite]`],
    ['the server lights up', A.serverLit[1], '[data-crew-server-in] [data-server-glyph]'],
  ];

  for (const [w, h] of [
    [375, 812],
    [320, 640],
  ] as const) {
    test(`plays every event where the copy cards leave the phone clear (${w} × ${h})`, async ({ page }) => {
      test.setTimeout(120_000);
      await page.setViewportSize({ width: w, height: h });
      await page.goto('/?motion=on');
      await settle(page);
      await expect(page.locator('html')).toHaveClass(/motion/);
      await toProgress(page, 0, 600);
      for (const [name, p, sel] of EVENTS) {
        await toProgress(page, p, 800);
        const hit = await page.evaluate((sel) => {
          const cards = Array.from(document.querySelectorAll('#crew .beat:not(.beat-head)')).map((e) => e.getBoundingClientRect());
          const els = Array.from(document.querySelectorAll(sel)).filter((e) => e.getBoundingClientRect().width > 0);
          if (!els.length) return 'missing';
          for (const e of els) {
            const r = e.getBoundingClientRect();
            if (r.bottom < 0 || r.top > innerHeight) return `off screen (${Math.round(r.top)})`;
            for (const c of cards) if (r.left < c.right && c.left < r.right && r.top < c.bottom && c.top < r.bottom) return `under a card (${Math.round(r.top)}–${Math.round(r.bottom)} vs ${Math.round(c.top)}–${Math.round(c.bottom)})`;
          }
          return '';
        }, sel);
        expect(hit, `${name} at ${p.toFixed(3)}`).toBe('');
      }
    });
  }
});
