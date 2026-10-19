/**
 * The screens team's lab: /lab/screens/ shows every state of the Clock tab, the Team tab and the
 * tree note sheet. These tests check the ledger values, the CONTRACT.md hooks, geometry in pt,
 * that pay never shows, and accessibility.
 *
 * Run (until playwright.config's testDir includes tests/lab):
 *   npm run build && npx playwright test -c <a config with testDir: 'tests/lab'>
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Locator, type Page } from '@playwright/test';
import { watch } from '../e2e/helpers';

const URL = '/lab/screens/';

async function open(page: Page) {
  await page.goto(URL);
  await page.evaluate(() => document.fonts.ready);
}

/** Size of an element in the phone's pt space. */
async function pt(el: Locator) {
  return el.evaluate((node) => {
    const screen = node.closest('.screen') as HTMLElement;
    const unit = screen.clientWidth / 393;
    const r = node.getBoundingClientRect();
    return { w: r.width / unit, h: r.height / unit };
  });
}

const screen = (page: Page, id: string) => page.locator(`[data-screen="${id}"]`);

test('renders every state with no console errors', async ({ page }) => {
  const { problems } = watch(page);
  await open(page);
  const phones = page.locator('main [data-phone][role="img"]');
  await expect(phones).toHaveCount(13);
  for (const label of await phones.evaluateAll((els) => els.map((e) => e.getAttribute('aria-label') ?? ''))) {
    expect(label.length).toBeGreaterThan(20);
  }
  // No stubs left in the screens team's components.
  await expect(page.locator('[data-stub="ClockTab"], [data-stub="TeamTab"], [data-stub="TreeNoteSheet"]')).toHaveCount(0);
  expect(problems).toEqual([]);
});

test('phones show at real device size on a wide window', async ({ page }) => {
  test.skip((page.viewportSize()?.width ?? 0) < 900, 'Phones scale down to fit narrow windows.');
  await open(page);
  const width = await page.locator('.screen').first().evaluate((el) => el.getBoundingClientRect().width);
  expect(Math.abs(width - 393)).toBeLessThan(2);
});

test.describe('Clock tab at 3:40 PM', () => {
  test('status card, now working and trees read from the ledger', async ({ page }) => {
    await open(page);
    const s = screen(page, 'lab-clock-top');
    const card = s.locator('[data-status-card]');
    await expect(card).toHaveAttribute('data-phase', 'working');
    await expect(card).toContainText('On the clock');
    await expect(card.locator('[data-timer="worked"]')).toHaveAttribute('data-odo-text', '7:39:00');
    await expect(card).toContainText('Clocked in at 7:02 AM');
    await expect(card.locator('[data-status-btn="break"]')).toHaveText('Break');
    await expect(card.locator('[data-status-btn="clock-out"]')).toHaveText('Clock out');

    const now = s.locator('[data-now-working]');
    await expect(now).toContainText('Block 2 · Row 39');
    await expect(now).toContainText('North field');
    await expect(now.locator('[data-now-row]')).toHaveText(['Row39', 'Row40', 'Row41'].map((t) => new RegExp(t.replace('Row', 'Row\\s*'))));
    await expect(now.locator('[data-now-break]')).toHaveText('Break');

    await expect(s.locator('[data-trees]')).toHaveText('260');
    await expect(s.locator('[data-trees-card]')).toContainText('2,460 of 8,540 trees shaped in North field');
    await expect(s.locator('[data-field-pct]')).toHaveText('29%');
  });

  test('pace rows and the week chart match the brief, pay hidden', async ({ page }) => {
    await open(page);
    const s = screen(page, 'lab-clock-top');
    const row = (id: string) => s.locator(`[data-pace-row="${id}"]`);
    await expect(s.locator('[data-segment="today"]')).toHaveClass(/is-on/);
    await expect(row('trees-hour')).toHaveText(/^\s*34\s*trees an hour\s*$/);
    await expect(row('per-tree')).toHaveText(/^\s*1:46\s*a tree\s*$/);
    await expect(row('pay')).toHaveText(/^\s*Pay per tree\s*•••\s*$/);
    await expect(row('best')).toHaveText('Best day · Thu, Oct 15 · 318 trees');
    await expect(row('left')).toHaveText('About 179 hours left in North field at your pace');

    const hours = s.locator('[data-hours-card]');
    const days = { mon: '8:37', tue: '8:18', wed: '5:45', thu: '8:45', fri: '7:39' };
    for (const [key, hm] of Object.entries(days)) {
      await expect(hours.locator(`[data-bar="${key}"]`)).toHaveCount(1);
      await expect(hours.locator(`[data-day="${key}"]`)).toContainText(hm);
    }
    await expect(hours.locator('[data-day="fri"]')).toHaveClass(/is-today/);
    await expect(hours.locator('[data-pay]')).toHaveText('•••');
    await expect(hours.locator('[data-pay-toggle]')).toHaveText('Show pay');
    await expect(s.locator('[data-shift-notes]')).toContainText('Rows past 30 are tall. Slower going.');
  });

  test('every CONTRACT.md hook is there', async ({ page }) => {
    await open(page);
    const s = screen(page, 'lab-clock-top');
    for (const sel of [
      '[data-app="clock"]',
      '[data-scroll-layer]',
      '[data-tool="settings"]',
      '[data-tab="clock"]',
      '[data-status-card]',
      '[data-timer]',
      '[data-now-working]',
      '[data-trees]',
      '[data-pace-card]',
      '[data-hours-card]',
      '[data-pay]',
      '[data-pay-toggle]',
    ]) {
      await expect(s.locator(sel), sel).toHaveCount(1);
    }
    for (const id of ['trees-hour', 'per-tree', 'pay', 'best', 'left']) {
      await expect(s.locator(`[data-pace-row="${id}"] [data-pace-rule]`), id).toHaveCount(1);
    }
    // Row buttons must not reuse the Live Activity's data-row hook (they share a screens container).
    await expect(s.locator('[data-row]')).toHaveCount(0);
  });

  test('gold rules rest at scaleY(0) unless highlighted; bars grow from the baseline', async ({ page }) => {
    await open(page);
    const rules = (id: string) =>
      screen(page, id)
        .locator('[data-pace-rule]')
        .evaluateAll((els) => els.map((e) => getComputedStyle(e).transform));
    expect(new Set(await rules('lab-clock-top'))).toEqual(new Set(['matrix(1, 0, 0, 0, 0, 0)']));
    expect((await rules('lab-clock-pace')).filter((t) => t === 'none')).toHaveLength(3);

    // Scoped: the status bar's signal bars also use data-bar ("1"–"4").
    const origins = await screen(page, 'lab-clock-top')
      .locator('[data-hours-card] [data-bar]')
      .evaluateAll((els) => els.map((e) => [parseFloat(getComputedStyle(e).transformOrigin.split(' ')[1]!), e.getBoundingClientRect().height]));
    expect(origins).toHaveLength(5);
    for (const [y, h] of origins) expect(Math.abs(y! - h!)).toBeLessThan(0.5);
  });

  test('the scroll layer is a long page and nothing spills past the screen', async ({ page }) => {
    await open(page);
    const s = screen(page, 'lab-clock-top');
    const layer = await pt(s.locator('[data-scroll-layer]'));
    expect(layer.h).toBeGreaterThan(1700);
    expect(layer.h).toBeLessThan(2000);
    const spills = await page.evaluate(() => {
      const out: string[] = [];
      for (const scr of document.querySelectorAll<HTMLElement>('.screen')) {
        const box = scr.getBoundingClientRect();
        for (const el of scr.querySelectorAll<HTMLElement>('[data-scroll-layer] *, [data-sheet] *')) {
          const r = el.getBoundingClientRect();
          if (r.width && (r.right > box.right + 0.5 || r.left < box.left - 0.5)) out.push(`${el.className}`);
        }
      }
      return out;
    });
    expect(spills).toEqual([]);

    // Lines that must stay on one line at every phone size (text does not scale perfectly).
    for (const sel of ['[data-trees-card] .sc-sub', '[data-status-card] .st-meta', '[data-pace-row="best"]', '[data-team-total]']) {
      for (const el of await page.locator(sel).all()) {
        const lines = await el.evaluate((n) => {
          const cs = getComputedStyle(n);
          const content = n.getBoundingClientRect().height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
          return content / parseFloat(cs.lineHeight);
        });
        expect(lines, sel).toBeLessThan(1.5);
      }
    }
  });

  test('a crop scrolls the layer to the pace card', async ({ page }) => {
    await open(page);
    const t = await screen(page, 'lab-clock-pace').locator('[data-scroll-layer]').evaluate((el) => getComputedStyle(el).transform);
    expect(t).toMatch(/^matrix\(1, 0, 0, 1, 0, -\d+/);
  });
});

test.describe('Clock tab at other moments', () => {
  test('break, lunch and off-the-clock states', async ({ page }) => {
    await open(page);
    const brk = page.locator('[data-screen="lab-clock-873"]');
    await expect(brk.locator('[data-status-card]')).toHaveAttribute('data-phase', 'break');
    await expect(brk.locator('[data-break-line]')).toContainText('Break started 2:30 PM · Sharpening shears');
    await expect(brk.locator('[data-timer]')).toHaveAttribute('data-odo-text', '6:43:00');
    await expect(brk.locator('[data-now-working]')).toContainText('Row 37 is next when you’re back.');
    await expect(brk.locator('[data-status-btn="back"]')).toHaveText('Back to work');

    const lunch = page.locator('[data-screen="lab-clock-730"]');
    await expect(lunch.locator('[data-status-card]')).toHaveAttribute('data-phase', 'lunch');
    await expect(lunch.locator('[data-break-line]')).toContainText('Lunch started 12:01 PM');

    const off = page.locator('[data-screen="lab-clock-1000"]');
    await expect(off.locator('[data-status-card]')).toHaveAttribute('data-phase', 'off');
    await expect(off.locator('[data-status-card]')).toContainText('Last clocked out at 4:31 PM.');
    await expect(off.locator('[data-now-working]')).toHaveCount(0);
  });
});

test.describe('Team tab', () => {
  test('this week from the ledger, invite and fields, no codes or pay', async ({ page }) => {
    await open(page);
    const s = screen(page, 'lab-team');
    const rows = { Alex: ['38:24', '1,297'], Sam: ['36:50', '1,214'], Rosa: ['31:15', '1,046'] };
    for (const [name, [hours, trees]] of Object.entries(rows)) {
      const row = s.locator(`[data-team-row="${name}"]`);
      await expect(row).toContainText(name);
      await expect(row.locator('[data-hours]')).toHaveText(hours!);
      await expect(row.locator('[data-trees]')).toHaveText(trees!);
    }
    await expect(s.locator('[data-team-total]')).toHaveText('3 people · 106:29 h · 3,557 trees');
    await expect(s.locator('[data-invite]')).toHaveText('Invite someone');
    await expect(s.locator('[data-fields-row]')).toContainText('Fields & blocks');
    await expect(s.locator('[data-app="team"]')).not.toContainText(/code|expire|pay/i);
  });
});

test.describe('Tree note sheet', () => {
  test('reads like the brief and keeps its geometry', async ({ page }) => {
    await open(page);
    const s = screen(page, 'lab-note');
    const sheet = s.locator('[data-sheet]');
    await expect(sheet).toContainText('Block 2 · Row 36 · Tree 7');
    await expect(sheet.locator('[data-flag-chip]')).toHaveText('Needs attention');
    await expect(sheet.locator('[data-note-text]')).toHaveText('Leader’s broken. Needs a stake.');
    await expect(sheet.locator('[data-note-byline]')).toContainText('Alex · Today 2:33 PM');
    await expect(sheet.locator('[data-add-note]')).toHaveText('Add note');
    expect(Math.abs((await pt(sheet.locator('[data-add-note]'))).h - 50)).toBeLessThan(0.75);

    // 55% of the screen, floating 6 pt in from the edges, over the tab bar.
    const geo = await sheet.evaluate((el) => {
      const scr = el.closest('.screen') as HTMLElement;
      const a = scr.getBoundingClientRect();
      const b = el.getBoundingClientRect();
      return { frac: (b.height + 6 * (a.width / 393)) / a.height, inset: (b.left - a.left) / (a.width / 393) };
    });
    expect(geo.frac).toBeCloseTo(0.55, 2);
    expect(geo.inset).toBeCloseTo(6, 0);
    const tabbarZ = await s.locator('[data-tabbar]').evaluate((el) => Number(getComputedStyle(el).zIndex));
    expect(Number(await sheet.evaluate((el) => getComputedStyle(el).zIndex))).toBeGreaterThan(tabbarZ);
  });

  test('the flag vocabulary is exactly the three flags', async ({ page }) => {
    await open(page);
    await expect(page.locator('.chips .sc-flag')).toHaveText(['Needs attention', 'Dead', 'Replant']);
    const flags = await page.locator('[data-sheet] .sc-flag').allTextContents();
    for (const f of flags) expect(['Needs attention', 'Dead', 'Replant']).toContain(f.trim());
  });
});

test('no dollar sign or currency figure anywhere', async ({ page }) => {
  await open(page);
  const text = await page.evaluate(() => document.body.innerText);
  expect(text).not.toMatch(/[$€£]/);
});

test('no horizontal page overflow', async ({ page }) => {
  await open(page);
  const over = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
  expect(over).toBeLessThanOrEqual(0);
});

test('axe: no serious or critical violations', async ({ page }) => {
  await open(page);
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  const bad = results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id}: ${v.nodes.map((n) => n.target.join(' ')).slice(0, 3).join(' | ')}`);
  expect(bad).toEqual([]);
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('the static lab shows the final layers with no errors', async ({ page }) => {
    const { problems } = watch(page);
    await open(page);
    await expect(page.locator('html')).not.toHaveClass(/motion/);
    await expect(screen(page, 'lab-clock-top')).toBeVisible();
    await expect(screen(page, 'lab-note').locator('[data-sheet]')).toBeVisible();
    expect(problems).toEqual([]);
  });
});
