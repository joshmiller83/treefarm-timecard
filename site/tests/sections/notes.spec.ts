/**
 * Section: notes (2:30 PM, on a break). The static page, the scrubbed scene's key states,
 * accessibility (static and under motion), copy clear of the header, and layout at 375 px.
 *
 * playwright.config.ts (foundation) runs only tests/e2e for now, so `npx playwright test
 * tests/sections/…` finds nothing. Until it lists tests/sections, run this spec with a config
 * that points testDir here:
 *
 *   npm run build && npx astro preview --background --port 4520
 *   printf "import c from '%s/playwright.config.ts';\nexport default { ...c, testDir: '%s/tests/sections' };\n" "$PWD" "$PWD" > /tmp/pw-sections.config.ts
 *   PW_PORT=4520 npx playwright test -c /tmp/pw-sections.config.ts --project=desktop --project=mobile
 *   npx astro preview stop
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { FLAGS, OLD_NOTE, TREE_NOTE } from '../../src/data/ledger';
import { SIRI } from '../../src/data/siri';
import { BREAK_PILL, PHONE_LABEL, WORKED_ON_BREAK, answerChips } from '../../src/sections/notes/copy';
import { plan, type Plan } from '../../src/sections/notes/plan';
import { settle, watch } from '../e2e/helpers';

const S = '#notes';
const layer = (page: Page, id: string) => page.locator(`[data-screen="${id}"]`);

/** Scrolls so the notes track is at scroll progress `p` (0–1) and lets the scrub (0.6 s) settle. */
async function progress(page: Page, p: number, wait = 1400) {
  await page.evaluate((p) => {
    const t = document.querySelector('#notes .track') as HTMLElement;
    const top = t.getBoundingClientRect().top + scrollY;
    window.scrollTo(0, top + p * (t.offsetHeight - innerHeight));
  }, p);
  await page.waitForTimeout(wait);
}

/** Opens the page with motion and walks down to the notes section, so its scene builds the normal way. */
async function openWithMotion(page: Page): Promise<Plan> {
  await page.goto('/');
  await settle(page);
  const desk = await page.evaluate(() => innerWidth >= 900 && innerHeight >= 560);
  for (const p of [-0.6, -0.3, -0.1, 0]) await progress(page, p, 250);
  return plan(desk ? 'desk' : 'mob');
}

const opacity = (page: Page, sel: string) => page.locator(sel).first().evaluate((el) => Number(getComputedStyle(el).opacity));

/** Serious and critical axe violations inside the section. */
async function axe(page: Page) {
  const r = await new AxeBuilder({ page }).include(S).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  return r.violations.filter((v) => v.impact === 'serious' || v.impact === 'critical').map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).join(' | ')}`);
}

/**
 * Copy beats whose visible pixels sit under the see-through header and ribbon: any beat with
 * an effective opacity above 0.1 whose top is above the chrome's bottom + 8 px.
 */
const underChrome = (page: Page) =>
  page.evaluate(() => {
    const grid = document.querySelector('#notes .frame-grid');
    const edge = (grid ? parseFloat(getComputedStyle(grid).paddingTop) : 59) + 8;
    const eff = (el: Element) => {
      let o = 1;
      for (let e: Element | null = el; e && e !== document.body; e = e.parentElement) o *= Number(getComputedStyle(e).opacity);
      return o;
    };
    return Array.from(document.querySelectorAll<HTMLElement>('#notes .beat'))
      .map((el) => ({ id: el.dataset.nb ?? 'head', o: eff(el.querySelector(':scope > .nb-body') ?? el), top: el.getBoundingClientRect().top }))
      .filter((b) => b.o > 0.1 && b.top < edge - 0.5)
      .map((b) => `${b.id} opacity ${b.o.toFixed(2)} at top ${Math.round(b.top)} (edge ${edge})`);
  });

test.describe('notes: the static page (reduced motion)', () => {
  test.use({ reducedMotion: 'reduce' });

  test('every beat shows its final content, with no wave and no typing', async ({ page }) => {
    const { problems } = watch(page);
    await page.goto('/');
    await page.locator(S).scrollIntoViewIfNeeded();
    await expect(page.locator('#notes-h')).toHaveText('Say what you see.');
    await expect(page.locator(S)).toHaveAttribute('aria-labelledby', 'notes-h');

    // The spoken lines, Siri's answers and the dictation are plain text.
    for (const text of [
      SIRI.breakReason.said,
      SIRI.breakReason.ask!,
      SIRI.breakReason.answer!,
      SIRI.breakReason.reply,
      SIRI.treeNote.said,
      SIRI.treeNote.reply,
      SIRI.shiftNote.said,
      SIRI.shiftNote.answer!,
      SIRI.shiftNote.reply,
    ]) {
      await expect(page.locator(S).getByText(text, { exact: true }).first()).toBeVisible();
    }
    // Spoken lines carry their speakers in text (sr-only), and the stamps a real datetime.
    const brk = ((await page.locator(`${S} [data-nb="break"]`).textContent()) ?? '').replace(/\s+/g, ' ');
    expect(brk).toContain(`You: ${SIRI.breakReason.said}`);
    expect(brk).toContain(`Siri: ${SIRI.breakReason.ask}`);
    expect(brk).toContain(`You: ${SIRI.breakReason.answer}`);
    expect(brk).toContain(`Siri: ${SIRI.breakReason.reply}`);
    const tree = ((await page.locator(`${S} [data-nb="tree"]`).textContent()) ?? '').replace(/\s+/g, ' ');
    expect(tree).toContain(`You: ${SIRI.treeNote.said}`);
    expect(tree).toContain(`Siri: ${SIRI.treeNote.reply}`);
    await expect(page.locator(`${S} .nb-stamp time`).first()).toHaveAttribute('datetime', '14:30');
    // Nothing in the copy is faded or offset.
    const faded = await page.locator(`${S} .beat, ${S} .beat *`).evaluateAll((els) =>
      els.filter((e) => Number(getComputedStyle(e).opacity) < 1).map((e) => e.outerHTML.slice(0, 80)),
    );
    expect(faded).toEqual([]);

    // Figure 1: the Live Activity crop on the break.
    const crop = page.locator(`${S} .nb-crop [role="img"]`);
    await expect(crop).toBeVisible();
    await expect(crop).toHaveAttribute('aria-label', new RegExp(BREAK_PILL));
    // Figure 2: the phone shows only its final layer, the tree note sheet over the map.
    const phone = page.locator(`${S} [data-phone][role="img"]`);
    await expect(phone).toHaveAttribute('aria-label', PHONE_LABEL);
    await expect(layer(page, 'trees-1433-note')).toBeVisible();
    for (const id of ['trees-1433-flag', 'lock-1430-break', 'lock-1433-treenote', 'lock-1436-dictation', 'lock-1444-back']) {
      await expect(layer(page, id)).toBeHidden();
    }
    await expect(page.locator(`${S} [data-wave]:visible`)).toHaveCount(0);
    await expect(page.locator(`${S} [data-screen="trees-1433-note"] [data-note-marker="2-36-7"]`)).toBeVisible();
    // Figure 3: the shift note as a bubble pair, and the strip of the time card.
    await expect(page.locator(`${S} [data-nb-bubble="you"]`)).toContainText(SIRI.shiftNote.answer!);
    await expect(page.locator(`${S} [data-nb-bubble="siri"]`)).toContainText(SIRI.shiftNote.reply);
    await expect(page.locator(`${S} [data-nb-strip]`)).toBeVisible();
    // No GSAP on the static page.
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    expect(problems).toEqual([]);
  });

  test('flags, answers and both notes use the app’s words', async ({ page }) => {
    await page.goto('/');
    const chips = page.getByRole('list', { name: 'Your answers' }).getByRole('listitem');
    await expect(chips).toHaveText(answerChips().map((c) => c.text));
    await expect(chips.last()).toHaveText(TREE_NOTE.flag);
    const notes = page.getByRole('list', { name: `Tree notes on block ${TREE_NOTE.block}` }).getByRole('listitem');
    await expect(notes).toHaveCount(2);
    await expect(notes.nth(0)).toContainText(TREE_NOTE.flag);
    await expect(notes.nth(1)).toContainText(OLD_NOTE.flag);
    await expect(notes.nth(1)).toContainText(OLD_NOTE.byline);
    // The flag vocabulary is exactly the app's: Needs attention, Dead, Replant.
    const text = ((await page.locator(`${S} .beats`).textContent()) ?? '').replace(/\s+/g, ' ');
    expect(text).toContain(`add a flag: ${FLAGS[0]}, ${FLAGS[1]} or ${FLAGS[2]}.`);
    expect(text).toContain(`stopped: ${WORKED_ON_BREAK}`);
  });

  test('axe: no serious or critical violations in the section', async ({ page }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
    expect(await axe(page)).toEqual([]);
  });
});

test.describe('notes: the scrubbed scene', () => {
  test('the break, the note on the map and back to work', async ({ page }) => {
    const { problems } = watch(page);
    const P = await openWithMotion(page);
    test.skip(!(await page.evaluate(() => document.documentElement.classList.contains('motion'))), 'motion is off here');

    // 2:16: the card as the lock-screen chapter left it.
    await progress(page, 0.01);
    await expect(layer(page, 'lock-1430-break').locator('[data-la]')).toHaveAttribute('data-state', 'tapped');
    await expect(layer(page, 'lock-1430-break').locator('[data-undo]')).toContainText('Row 36 marked');

    // Just after Siri starts the break: gold, the reason in the pill, worked time frozen.
    await progress(page, P.break.la[1] + 0.01);
    const brk = layer(page, 'lock-1430-break');
    await expect(brk.locator('[data-la]')).toHaveAttribute('data-state', 'break');
    await expect(brk.locator('[data-pill-text="break"]')).toHaveText(BREAK_PILL);
    expect(await opacity(page, '[data-screen="lock-1430-break"] [data-pill-face="break"]')).toBeGreaterThan(0.95);
    await expect(brk.locator('[data-worked-line] [data-timer]')).toHaveText(WORKED_ON_BREAK);
    await expect(brk.locator('[data-nb-card="reply"] [data-snippet-text]')).toHaveText(SIRI.breakReason.reply);

    // The sheet is up on the selected tree, its flag on the map.
    await progress(page, (P.crew.sheetUp[1] + P.crew.sheetDown[0]) / 2);
    expect(await opacity(page, '[data-screen="trees-1433-note"]')).toBe(1);
    const sheetY = await layer(page, 'trees-1433-note').locator('[data-sheet]').evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42);
    expect(Math.abs(sheetY)).toBeLessThan(1);
    await expect(layer(page, 'trees-1433-note').locator('[data-tree="2-36-7"]')).toHaveAttribute('data-selected', '');

    // The end: green again at 6:43:00 with Row 37, Row 38, Row 39 and Break.
    await progress(page, 1, 1800);
    const back = layer(page, 'lock-1444-back');
    expect(await opacity(page, '[data-screen="lock-1444-back"]')).toBe(1);
    await expect(back.locator('[data-la]')).toHaveAttribute('data-state', 'working');
    await expect(back.locator('[data-la] > .la-r2 [data-timer]')).toHaveAttribute('data-odo-text', /.*/);
    const rows = await back.locator('[data-row]').evaluateAll((els) =>
      els.slice(0, 3).map((e) => ({ text: e.textContent?.trim(), scale: new DOMMatrix(getComputedStyle(e).transform).a })),
    );
    expect(rows).toEqual([
      { text: 'Row 37', scale: 1 },
      { text: 'Row 38', scale: 1 },
      { text: 'Row 39', scale: 1 },
    ]);
    expect(await opacity(page, '[data-screen="lock-1444-back"] [data-break-btn]')).toBe(1);
    expect(await opacity(page, '[data-screen="lock-1444-back"] [data-pill-face="clock"]')).toBe(1);
    expect(problems).toEqual([]);
  });

  test('the dictation wave draws the same bars at the same progress', async ({ page }) => {
    const P = await openWithMotion(page);
    test.skip(!(await page.evaluate(() => document.documentElement.classList.contains('motion'))), 'motion is off here');
    const mid = (P.shift.wave[0] + P.shift.wave[1]) / 2;
    const bars = () =>
      layer(page, 'lock-1436-dictation')
        .locator('[data-wave-bar]')
        .evaluateAll((els) => els.map((e) => (e as HTMLElement).style.getPropertyValue('--h')));
    await progress(page, mid, 1800);
    const first = await bars();
    expect(new Set(first).size).toBeGreaterThan(3);
    await progress(page, P.crew.drop[0], 900);
    await progress(page, mid, 1800);
    expect(await bars()).toEqual(first);
  });

  test('axe under motion, at the tree note: no serious or critical violations', async ({ page }) => {
    const P = await openWithMotion(page);
    test.skip(!(await page.evaluate(() => document.documentElement.classList.contains('motion'))), 'motion is off here');
    await progress(page, P.at.tree, 1800);
    expect(await axe(page)).toEqual([]);
  });

  test('no horizontal overflow at any step', async ({ page }) => {
    await openWithMotion(page);
    for (const p of [0, 0.2, 0.4, 0.6, 0.8, 1]) {
      await progress(page, p, 500);
      const wide = await page.evaluate(() => {
        const vw = document.documentElement.clientWidth;
        const out: string[] = [];
        if (document.documentElement.scrollWidth > vw) out.push(`page ${document.documentElement.scrollWidth} > ${vw}`);
        for (const el of Array.from(document.querySelectorAll<HTMLElement>('#notes .beat, #notes .beat *'))) {
          const r = el.getBoundingClientRect();
          if (r.width && (r.right > vw + 0.5 || r.left < -0.5)) out.push(`${el.className || el.tagName} ${Math.round(r.left)}–${Math.round(r.right)}`);
        }
        return out;
      });
      expect(wide, `progress ${p}`).toEqual([]);
    }
  });
});

test.describe('notes on a phone: the phone waits for its cards', () => {
  test.skip(({ isMobile }) => !isMobile, 'mobile only');

  test('holds “Noted…” while the tree card reads, and the map while the crew card reads', async ({ page }) => {
    const { problems } = watch(page);
    const P = await openWithMotion(page);
    test.skip(!(await page.evaluate(() => document.documentElement.classList.contains('motion'))), 'motion is off here');
    expect(P.mode).toBe('mob');

    // The tree card: the lock screen with Siri's answer, never a map without the new flag.
    await progress(page, P.at.tree, 1800);
    const tree = layer(page, 'lock-1433-treenote');
    expect(await opacity(page, '[data-screen="lock-1433-treenote"]')).toBe(1);
    const lockY = await tree.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42);
    expect(Math.abs(lockY)).toBeLessThan(1);
    await expect(tree.locator('[data-nb-card="reply"] [data-snippet-text]')).toHaveText(SIRI.treeNote.reply);
    expect(await opacity(page, '[data-screen="lock-1433-treenote"] [data-nb-card="reply"] [data-snippet]')).toBeGreaterThan(0.95);

    // The crew card: the map with the flag and the note sheet; the lock screen not back yet.
    await progress(page, P.at.crew, 1800);
    expect(await opacity(page, '[data-screen="trees-1433-note"]')).toBe(1);
    expect(await opacity(page, '[data-screen="lock-1436-dictation"]')).toBe(0);
    await expect(layer(page, 'trees-1433-note').locator('[data-note-marker="2-36-7"]')).toBeVisible();
    const sheetY = await layer(page, 'trees-1433-note').locator('[data-sheet]').evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m42);
    expect(Math.abs(sheetY)).toBeLessThan(1);

    // Each Siri reply lands as its card's top reaches about 70% of the viewport.
    for (const [key, at] of [
      ['break', P.break.reply[0]],
      ['tree', P.tree.reply[0]],
      ['shift', P.shift.reply[0]],
    ] as const) {
      await progress(page, at, 900);
      const top = await page.locator(`${S} [data-nb="${key}"]`).evaluate((el) => el.getBoundingClientRect().top / innerHeight);
      expect(top, key).toBeGreaterThan(0.55);
      expect(top, key).toBeLessThan(0.85);
    }
    expect(problems).toEqual([]);
  });
});

test.describe('notes on desktop: copy never sits under the header', () => {
  test.skip(({ isMobile }) => !!isMobile, 'desktop only');

  for (const viewport of [
    { width: 1440, height: 900 },
    { width: 1280, height: 720 },
  ]) {
    test(`no beat shows above the chrome at ${viewport.width}×${viewport.height}`, async ({ page }) => {
      await page.setViewportSize(viewport);
      await openWithMotion(page);
      test.skip(!(await page.evaluate(() => document.documentElement.classList.contains('motion'))), 'motion is off here');
      const bad: string[] = [];
      for (let i = 0; i <= 50; i += 1) {
        const p = i / 50;
        await progress(page, p, 350);
        for (const b of await underChrome(page)) bad.push(`p ${p.toFixed(2)}: ${b}`);
      }
      expect(bad).toEqual([]);
    });
  }
});

test.describe('notes at 375 px, static', () => {
  test.use({ reducedMotion: 'reduce', viewport: { width: 375, height: 812 } });
  test('no horizontal overflow; the Live Activity crop follows the break', async ({ page }) => {
    await page.goto('/');
    await page.locator(S).scrollIntoViewIfNeeded();
    const wide = await page.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      return Array.from(document.querySelectorAll<HTMLElement>('#notes *'))
        .filter((el) => !el.closest('[data-phone]') && !el.closest('.sr-only'))
        .map((el) => [el, el.getBoundingClientRect()] as const)
        .filter(([, r]) => r.width > 0 && (r.right > vw + 0.5 || r.left < -0.5))
        .map(([el, r]) => `${el.className || el.tagName} ${Math.round(r.left)}–${Math.round(r.right)}`);
    });
    expect(wide).toEqual([]);
    const y = async (sel: string) => (await page.locator(sel).first().boundingBox())!.y;
    expect(await y(`${S} .nb-crop`)).toBeGreaterThan(await y(`${S} [data-nb="break"]`));
    expect(await y(`${S} .nb-crop`)).toBeLessThan(await y(`${S} [data-nb="tree"]`));
    // The phone (the tree note sheet) follows the tree and crew beats it shows.
    expect(await y(`${S} .nb-shot`)).toBeGreaterThan(await y(`${S} [data-nb="crew"]`));
    expect(await y(`${S} .nb-shot`)).toBeLessThan(await y(`${S} [data-nb="shift"]`));
    // Spoken lines never hang their quotes into the gutter on a phone.
    const lefts = await page.locator(`${S} .spoken q, ${S} .nb-you q`).evaluateAll((els) => els.map((e) => e.getBoundingClientRect().left));
    for (const l of lefts) expect(l).toBeGreaterThanOrEqual(15.5);
  });
});
