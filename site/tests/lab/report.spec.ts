/**
 * The report lab (/lab/report/): ReportTab and PaperTimeCard in every state.
 * Runs in both Playwright projects (desktop 1440 and mobile 375), and in WebKit and Firefox with PW_ALL=1.
 */
import AxeBuilder from '@axe-core/playwright';
import { expect, test, type Page } from '@playwright/test';
import { watch } from '../e2e/helpers';

const URL = '/lab/report/';
const COLUMNS = ['Date', 'In', 'Out', 'Trees', 'Hours', 'Breaks', 'Notes'];
const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri'];
const STATES = ['report-week', 'lab-report-pick-sheet', 'lab-report-pick', 'lab-report-last-week', 'lab-report-month'];

async function open(page: Page) {
  await page.goto(URL);
  await page.evaluate(() => document.fonts.ready);
}

/** The first page card (the 720px slot; it stacks on a phone). */
const card = (page: Page) => page.locator('[data-lab-paper="720"] [data-paper]');
/** The 343px card: stacked day blocks at every window width. */
const stacked = (page: Page) => page.locator('[data-lab-paper="343"] [data-paper]');
/** The ReportTab preview in the 760px stage phone, where the clock-out Flip runs. */
const stageMini = (page: Page) => page.locator('section[aria-labelledby="sizes-h"] .lab-cell:first-child [data-paper-mini]');

test('shows every ReportTab state and the paper with no errors', async ({ page }) => {
  const { problems } = watch(page);
  await open(page);
  await expect(page.locator('h1')).toHaveText('report');
  for (const id of STATES) {
    const phone = page.locator(`[data-lab-state="${id}"] [data-phone][role="img"]`);
    await expect(phone).toBeVisible();
    expect((await phone.getAttribute('aria-label'))?.length ?? 0).toBeGreaterThan(40);
    await expect(phone.locator(`[data-screen="${id}"][data-final]`)).toHaveCount(1);
  }
  await expect(page.locator('[data-paper]')).toHaveCount(4);
  expect(problems).toEqual([]);
});

test('the paper is a real table: caption, column and row headers, totals in tfoot', async ({ page }) => {
  await open(page);
  const table = card(page).locator('table');
  await expect(table).toHaveCount(1);
  await expect(table.locator('caption')).toHaveText('Example time card for Alex, Mon, Oct 12 – Fri, Oct 16');
  await expect(table.locator('thead th[scope="col"]')).toHaveText(COLUMNS);
  await expect(table.locator('tbody tr')).toHaveCount(5);
  await expect(table.locator('tbody th[scope="row"]')).toHaveText(['Mon, Oct 12', 'Tue, Oct 13', 'Wed, Oct 14', 'Thu, Oct 15', 'Fri, Oct 16']);
  await expect(table.locator('tfoot [data-totals]')).toHaveText('39:55 hours · 1,347 trees');
  await expect(table.locator('tfoot th[scope="row"]')).toContainText('Total');
  // The accessible table survives the stacked layout's display changes.
  await expect(page.getByRole('table', { name: 'Example time card for Alex, Mon, Oct 12 – Fri, Oct 16' }).first()).toBeVisible();
  await expect(page.getByRole('columnheader', { name: 'Breaks' }).first()).toBeAttached();
  await expect(card(page)).toContainText('Breaks are listed, not counted.');
  await expect(card(page)).toContainText('Prepared Fri, Oct 16 at 4:31 PM');
  // A valid <time>: the whole moment, with a machine-readable date and time.
  const prepared = card(page).locator('.tc-prepared time');
  await expect(prepared).toHaveText('Fri, Oct 16 at 4:31 PM');
  await expect(prepared).toHaveAttribute('datetime', '2026-10-16T16:31');
});

test('Friday prints from the ledger, with breaks listed but not counted', async ({ page }) => {
  await open(page);
  const fri = card(page).locator('tr[data-day="fri"]');
  await expect(fri.locator('th')).toHaveText('Fri, Oct 16');
  await expect(fri).toContainText('7:02 AM');
  await expect(fri).toContainText('4:31 PM');
  await expect(fri.locator('[data-cell="fri-trees"]')).toHaveText('290');
  await expect(fri.locator('[data-cell="fri-hours"]')).toHaveText('8:30');
  await expect(fri.locator('.c-breaks')).toHaveText('Water 9:45–10:00; Lunch 12:01–12:31; Sharpening shears 2:30–2:44');
  await expect(fri.locator('.c-notes')).toHaveText('Rows past 30 are tall. Slower going.');
  // Machine-readable times.
  await expect(fri.locator('time[datetime="2026-10-16T07:02"]')).toHaveCount(1);
  await expect(fri.locator('time[datetime="PT8H30M"]')).toHaveCount(1);
});

test('every row keeps seven cells for screen readers, empty ones saying None, at every layout', async ({ page }) => {
  await open(page);
  for (const paper of [card(page), stacked(page)]) {
    const table = paper.getByRole('table');
    for (const date of ['Mon, Oct 12', 'Tue, Oct 13', 'Wed, Oct 14', 'Thu, Oct 15', 'Fri, Oct 16']) {
      const row = table.getByRole('row', { name: new RegExp(`^${date}`) });
      await expect(row.getByRole('rowheader'), date).toHaveAccessibleName(date);
      await expect(row.getByRole('cell'), date).toHaveCount(6);
    }
    // Wednesday has no breaks but a note: 'None' under Breaks, the note under Notes.
    const wed = table.getByRole('row', { name: /^Wed, Oct 14/ }).getByRole('cell');
    await expect(wed.nth(4)).toHaveAccessibleName('None');
    await expect(wed.nth(5)).toHaveAccessibleName('Rain after 1.');
    // Monday has breaks but no note.
    const mon = table.getByRole('row', { name: /^Mon, Oct 12/ }).getByRole('cell');
    await expect(mon.nth(4)).toHaveAccessibleName('Lunch 12:00–12:30');
    await expect(mon.nth(5)).toHaveAccessibleName('None');
  }
});

test('the stacked card’s generated separators and labels stay out of the cells’ names', async ({ page }) => {
  await open(page);
  const fri = stacked(page).getByRole('row', { name: /^Fri, Oct 16/ }).getByRole('cell');
  const names = ['7:02 AM', '4:31 PM', '290', '8:30', 'Water 9:45–10:00; Lunch 12:01–12:31; Sharpening shears 2:30–2:44', 'Rows past 30 are tall. Slower going.'];
  for (const [i, name] of names.entries()) await expect(fri.nth(i)).toHaveAccessibleName(name);
  // …while the eye still reads '7:02 AM – 4:31 PM · 8:30 h · 290 trees'.
  await expect(stacked(page).locator('tr[data-day="fri"]')).toHaveCSS('display', 'flex');
});

test('in the stacked card, Wednesday’s note sits where the other days’ first detail line does', async ({ page }) => {
  await open(page);
  const gap = (day: string, sel: string) =>
    stacked(page)
      .locator(`tr[data-day="${day}"]`)
      .evaluate((tr, s) => tr.querySelector(s)!.getBoundingClientRect().top - tr.querySelector('.c-in')!.getBoundingClientRect().bottom, sel);
  const wed = await gap('wed', '.c-notes');
  const mon = await gap('mon', '.c-breaks');
  expect(Math.abs(wed - mon)).toBeLessThanOrEqual(1);
});

test('a break entry never splits from its time', async ({ page }) => {
  await open(page);
  // Stacked: each entry is one line box; lines break only between entries.
  const pieces = await stacked(page)
    .locator('.tc-brk')
    .evaluateAll((els) => els.map((e) => ({ text: e.textContent, lines: new Set([...e.getClientRects()].map((r) => Math.round(r.top))).size })));
  expect(pieces.length).toBe(7);
  for (const p of pieces) expect(p.lines, p.text ?? '').toBe(1);
  // Tighter columns (640px, desktop windows): a wrapped entry hangs its time under its reason.
  const narrow = page.locator('[data-lab-paper="640"] [data-paper]');
  if ((await narrow.boundingBox())!.width >= 600) {
    const hangs = await narrow.locator('.tc-brk').evaluateAll((els) =>
      els.map((e) => {
        const box = e.getBoundingClientRect();
        const time = e.querySelector('.tc-span')!.getBoundingClientRect();
        return { text: e.textContent, wrapped: time.top > box.top + 2, indent: time.left - box.left };
      }),
    );
    expect(hangs.some((h) => h.wrapped)).toBe(true);
    for (const h of hangs.filter((x) => x.wrapped)) expect(h.indent, h.text ?? '').toBeGreaterThan(6);
  }
});

test('keeps the hooks scenes animate (CONTRACT.md)', async ({ page }) => {
  await open(page);
  const p = card(page);
  for (const hook of ['[data-paper-shadow]', '[data-paper-band]', '[data-totals-rule]', '[data-totals]']) {
    await expect(p.locator(hook), hook).toHaveCount(1);
  }
  for (const d of DAYS) {
    await expect(p.locator(`tr[data-day="${d}"]`)).toHaveCount(1);
    await expect(p.locator(`[data-cell="${d}-trees"] [data-flash]`)).toHaveCount(1);
    await expect(p.locator(`[data-cell="${d}-hours"] [data-flash]`)).toHaveCount(1);
  }
  // The gold flash rests invisible; the shadow layer rests visible.
  await expect(p.locator('[data-cell="fri-trees"] [data-flash]')).toHaveCSS('opacity', '0');
  await expect(p.locator('[data-paper-shadow]')).toHaveCSS('opacity', '1');

  const tab = page.locator('[data-lab-state="report-week"]');
  await expect(tab.locator('[data-range-chip]')).toHaveCount(4);
  for (const slug of ['this-week', 'last-week', 'this-month', 'pick-dates']) await expect(tab.locator(`[data-range-chip="${slug}"]`)).toHaveCount(1);
  await expect(tab.locator('[data-range-chip][data-selected]')).toHaveAttribute('data-range-chip', 'this-week');
  await expect(tab.locator('[data-range-chip="this-week"]')).toHaveText('This week');
  await expect(tab.locator('[data-paper-thumb]')).toHaveCount(1);
  await expect(tab.locator('[data-export="pdf"]')).toHaveText('Export PDF');
  await expect(tab.locator('[data-export="csv"]')).toHaveText('CSV');
  await expect(tab.locator('[data-tab="report"].is-active')).toHaveCount(1);
  // The miniature carries no page hooks, so scenes never grab the wrong paper.
  await expect(tab.locator('[data-paper], [data-day], [data-totals]')).toHaveCount(0);
});

test('the ReportTab shows the range, totals and an accurate preview', async ({ page }) => {
  await open(page);
  const tab = page.locator('[data-lab-state="report-week"] [data-app="report"]');
  await expect(tab).toContainText('Mon, Oct 12 – Fri, Oct 16');
  await expect(tab.locator('[data-report-total="hours"]')).toContainText('39:55');
  await expect(tab.locator('[data-report-total="trees"]')).toContainText('1,347');
  await expect(tab.locator('[data-report-total="days"]')).toContainText('5');
  await expect(tab.locator('[data-paper-thumb]')).toContainText('39:55 hours · 1,347 trees');
  // The screen is the app's own UI: no marketing line under the preview (the page says it).
  await expect(tab).not.toContainText('Pay is never printed');
  // Mock text is presentational: no tables, headings or buttons inside the phone.
  await expect(page.locator('[data-phone] table, [data-phone] h1, [data-phone] h2, [data-phone] h3, [data-phone] button')).toHaveCount(0);

  const pick = page.locator('[data-lab-state="lab-report-pick-sheet"]');
  await expect(pick.locator('[data-range-chip][data-selected]')).toHaveAttribute('data-range-chip', 'pick-dates');
  await expect(pick.locator('[data-date-sheet]')).toContainText('Pick dates');
  await expect(pick.locator('[data-date-sheet]')).toContainText('October 2026');
  await expect(pick.locator('[data-date-sheet] .is-from')).toHaveText('12');
  await expect(pick.locator('[data-date-sheet] .is-to')).toHaveText('16');
  // The From/To separator is a border, which every engine draws at least one device pixel thick.
  const rule = pick.locator('[data-date-sheet] .rt-row').nth(1);
  expect(parseFloat(await rule.evaluate((e) => getComputedStyle(e).borderTopWidth))).toBeGreaterThan(0);

  // Ranges without example shifts draw a preview instead of inventing numbers.
  const last = page.locator('[data-lab-state="lab-report-last-week"]');
  await expect(last).toContainText('Mon, Oct 5 – Sun, Oct 11');
  await expect(last.locator('[data-report-total="hours"]')).not.toContainText(/\d/);
  await expect(last.locator('[data-paper-thumb]')).not.toContainText(/hours ·/);
});

test('never prints pay: no pay column, no currency', async ({ page }) => {
  await open(page);
  const headers = await page.locator('[data-paper] th, [data-paper-mini] .tc-th').allInnerTexts();
  expect(headers.length).toBeGreaterThan(0);
  for (const h of headers) expect(h).not.toMatch(/pay|rate|wage|amount|\$/i);
  const text = await page.locator('main').innerText();
  expect(text).not.toContain('$');
  const phones = await page.locator('[data-phone]').allInnerTexts();
  for (const t of phones) expect(t).not.toMatch(/\$|•••/);
});

test('the preview is the paper in miniature (same proportions, for the Flip)', async ({ page }, info) => {
  test.skip(info.project.name.includes('mobile'), 'the page card stacks at phone width');
  await open(page);
  const big = await card(page).boundingBox();
  const ratio = (b: { width: number; height: number }) => b.width / b.height;
  // The 760px stage phone is where the clock-out Flip runs; the real-size phone is the lab's 910px.
  for (const [name, mini] of [
    ['760 stage', stageMini(page)],
    ['910 real size', page.locator('[data-lab-state="report-week"] [data-paper-mini]')],
  ] as const) {
    const box = await mini.boundingBox();
    expect(Math.abs(ratio(big!) / ratio(box!) - 1), name).toBeLessThan(0.015);
  }
});

test('the miniature’s double rule stays double at every phone size', async ({ page, browserName }) => {
  // Real browsers draw a thin border as one device pixel (Chrome at 2x reports 0.5px). Emulated
  // Chromium and Firefox at a higher deviceScaleFactor round borders to whole CSS pixels instead,
  // so they only model a real screen at 1x; WebKit models every scale.
  const dpr = await page.evaluate(() => devicePixelRatio);
  test.skip(browserName !== 'webkit' && dpr > 1, 'emulated border snapping differs from real screens above 1x');
  await open(page);
  const gaps = await page.locator('[data-paper-mini] .tc-rule').evaluateAll((els) =>
    els.map((e) => {
      const s = getComputedStyle(e);
      return e.getBoundingClientRect().height - parseFloat(s.borderTopWidth) - parseFloat(s.borderBottomWidth);
    }),
  );
  expect(gaps.length).toBeGreaterThanOrEqual(8);
  const device = await page.evaluate(() => 1 / devicePixelRatio);
  for (const g of gaps) expect(g).toBeGreaterThanOrEqual(device - 0.02);
});

test('stacks into day blocks under 600px, with no horizontal scroll', async ({ page }) => {
  await open(page);
  const narrow = page.locator('[data-lab-paper="343"] [data-paper]');
  const fri = narrow.locator('tr[data-day="fri"]');
  await expect(fri).toHaveCSS('display', 'flex');
  // The stacked line reads '7:02 AM – 4:31 PM · 8:30 h · 290 trees'.
  const parts = await fri.evaluate((tr) => {
    const css = (sel: string, pseudo: string) => getComputedStyle(tr.querySelector(sel)!, pseudo).content;
    return { out: css('.c-out', '::before'), hours: css('.c-hours', '::after'), trees: css('.c-trees', '::after'), breaks: css('.c-breaks', '::before') };
  });
  expect(parts.out).toContain('–');
  expect(parts.hours).toContain('h');
  expect(parts.trees).toContain('trees');
  expect(parts.breaks).toMatch(/Breaks/);
  // The gold flash hugs the number and paints behind every bit of text in the cell.
  for (const key of ['fri-trees', 'fri-hours']) {
    const hit = await narrow.locator(`[data-cell="${key}"]`).evaluate((cell) => {
      const flash = cell.querySelector<HTMLElement>('[data-flash]')!;
      const value = cell.querySelector('.tc-v')!;
      flash.style.opacity = '1';
      flash.style.pointerEvents = 'auto';
      const c = cell.getBoundingClientRect();
      const v = value.getBoundingClientRect();
      const f = flash.getBoundingClientRect();
      const y = v.top + v.height / 2;
      const result = {
        // On the number: the text is in front of the flash.
        onValue: document.elementFromPoint(v.left + v.width / 2, y) === flash,
        // On the ' h' or ' trees' suffix at the cell's end: never the flash.
        onSuffix: document.elementFromPoint(c.right - 2, y) === flash,
        // On the ' · ' before the number.
        onSeparator: document.elementFromPoint(c.left + 3, y) === flash,
        hugs: f.left >= v.left - 6 && f.right <= v.right + 6,
      };
      flash.style.opacity = '';
      flash.style.pointerEvents = '';
      return result;
    });
    expect(hit, key).toEqual({ onValue: false, onSuffix: false, onSeparator: false, hugs: true });
  }
  // Column headers stay for screen readers but take no room.
  const head = await narrow.locator('thead').boundingBox();
  expect(head!.width).toBeLessThanOrEqual(1);
  // Nothing in the card is wider than the card (the sheet clips, so compare every box).
  const overflow = await narrow.evaluate((el) => el.scrollWidth - el.clientWidth);
  expect(overflow).toBeLessThanOrEqual(0);
  const outside = await narrow.locator('.tc-main').evaluate((main) => {
    const box = main.getBoundingClientRect();
    return [...main.querySelectorAll('*')]
      .filter((e) => e.getClientRects().length && e.getBoundingClientRect().width > 1)
      .filter((e) => e.getBoundingClientRect().right > box.right + 0.5 || e.getBoundingClientRect().left < box.left - 0.5)
      .map((e) => `${e.className}: ${e.textContent}`);
  });
  expect(outside).toEqual([]);
  // Against the configured width: a phone browser zooms out to fit, which would hide overflow.
  const pageWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  expect(pageWidth).toBeLessThanOrEqual(page.viewportSize()!.width);
});

test('the wide card keeps the table layout', async ({ page }, info) => {
  test.skip(info.project.name.includes('mobile'), 'desktop widths only');
  await open(page);
  await expect(card(page).locator('tr[data-day="fri"]')).toHaveCSS('display', 'table-row');
  await expect(card(page).locator('thead')).toBeVisible();
});

test.describe('reduced motion', () => {
  test.use({ reducedMotion: 'reduce' });
  test('renders the same final states', async ({ page }) => {
    const { problems } = watch(page);
    await open(page);
    await expect(page.locator('html')).not.toHaveClass(/(^|\s)motion(\s|$)/);
    await expect(page.locator('[data-screen="report-week"][data-final]')).toBeVisible();
    await expect(card(page).locator('tfoot [data-totals]')).toBeVisible();
    expect(problems).toEqual([]);
  });
});

test('axe: no serious or critical violations', async ({ page }) => {
  await open(page);
  const results = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'best-practice']).analyze();
  const bad = results.violations
    .filter((v) => v.impact === 'serious' || v.impact === 'critical')
    .map((v) => `${v.id} (${v.impact}): ${v.nodes.map((n) => n.target.join(' ')).slice(0, 5).join(' | ')}`);
  expect(bad).toEqual([]);
});
