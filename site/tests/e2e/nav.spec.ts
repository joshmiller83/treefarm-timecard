import { expect, test } from '@playwright/test';
import { SECTION_IDS, settle } from './helpers';

test('header chapter links reach every section', async ({ page, isMobile }) => {
  await page.goto('/');
  await settle(page);
  const toggle = page.locator('.shift-toggle');
  for (const id of ['pace', 'voice', 'open']) {
    if (isMobile) {
      await toggle.click();
      await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    }
    await page.locator(`a[data-chapter-link="${id}"]`).click();
    await expect(page).toHaveURL(new RegExp(`#${id}$`));
    if (isMobile) await expect(toggle).toHaveAttribute('aria-expanded', 'false');
    const top = await page.locator(`#${id}`).evaluate((el) => el.getBoundingClientRect().top);
    expect(Math.abs(top)).toBeLessThan(120);
  }
  await expect(page.locator('a[data-chapter-link]')).toHaveCount(SECTION_IDS.length);
});

test('the chapter list works by keyboard', async ({ page, isMobile }) => {
  test.skip(!isMobile, 'the disclosure is the mobile pattern');
  await page.goto('/');
  const toggle = page.locator('.shift-toggle');
  await toggle.focus();
  await page.keyboard.press('Enter');
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  await page.keyboard.press('Escape');
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
  await expect(toggle).toBeFocused();
});

test('pause motion toggles and remembers', async ({ page, isMobile }) => {
  test.skip(isMobile, 'same control on both');
  await page.goto('/');
  const pause = page.locator('[data-pause-toggle]');
  await expect(pause).toBeVisible();
  await expect(pause).toHaveAttribute('aria-pressed', 'false');
  await pause.click();
  await expect(pause).toHaveAttribute('aria-pressed', 'true');
  await expect(page.locator('html')).toHaveClass(/paused/);
  await page.reload();
  await expect(page.locator('html')).toHaveClass(/paused/);
  await expect(page.locator('[data-pause-toggle]')).toHaveAttribute('aria-pressed', 'true');
});

test('the header turns light over the light closing section', async ({ page }) => {
  await page.goto('/');
  await settle(page);
  await page.locator('#open').evaluate((el) => window.scrollTo(0, el.getBoundingClientRect().top + scrollY + 200));
  await page.waitForTimeout(400);
  await expect(page.locator('[data-header]')).toHaveAttribute('data-theme', 'light');
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(400);
  await expect(page.locator('[data-header]')).toHaveAttribute('data-theme', 'dark');
});

test.describe('reduced motion (the static page)', () => {
  test.use({ reducedMotion: 'reduce' });

  const landed = (page: import('@playwright/test').Page, id: string) =>
    page.evaluate((id) => {
      const top = document.getElementById(id)!.getBoundingClientRect().top;
      const pad = parseFloat(getComputedStyle(document.documentElement).scrollPaddingTop) || 0;
      return { top: Math.round(top), pad: Math.round(pad) };
    }, id);

  test('every chapter link lands its chapter under the header', async ({ page, isMobile }) => {
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    const toggle = page.locator('.shift-toggle');
    // Down the page and back up, so far sections are still unrendered stand-ins when we jump.
    for (const id of [...SECTION_IDS.slice(1), 'hero', 'clock-out', 'voice']) {
      if (isMobile) {
        await toggle.click();
        await expect(toggle).toHaveAttribute('aria-expanded', 'true');
      }
      await page.locator(`a[data-chapter-link="${id}"]`).click();
      await expect(page).toHaveURL(new RegExp(`#${id}$`));
      await page.waitForTimeout(250);
      const { top, pad } = await landed(page, id);
      // The hero starts under the header at the top of the page: it lands at scroll 0.
      if (id === 'hero') expect(await page.evaluate(() => scrollY)).toBeLessThanOrEqual(1);
      else expect(Math.abs(top - pad), `${id}: top ${top}, scroll-padding ${pad}`).toBeLessThan(24);
    }
  });

  test('a shared link to a chapter opens on that chapter', async ({ page }) => {
    for (const id of ['crew', 'pace', 'open']) {
      await page.goto(`/#${id}`);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForLoadState('load');
      await page.waitForTimeout(300);
      const { top, pad } = await landed(page, id);
      expect(Math.abs(top - pad), `${id}: top ${top}, scroll-padding ${pad}`).toBeLessThan(24);
    }
  });

  test('the hero’s walk-through link lands on the first chapter', async ({ page }) => {
    await page.goto('/');
    await page.getByRole('link', { name: 'Walk through a shift' }).click();
    await expect(page).toHaveURL(/#voice$/);
    await page.waitForTimeout(250);
    const { top, pad } = await landed(page, 'voice');
    expect(Math.abs(top - pad)).toBeLessThan(24);
  });
});

for (const name of ['iPhone 15 landscape', 'iPhone SE landscape'] as const) {
  test(`${name}: every chapter in the open panel can be reached`, async ({ page, browserName }, info) => {
    test.skip(!/mobile/.test(info.project.name), 'phone projects');
    const { devices } = await import('@playwright/test');
    await page.setViewportSize(devices[name].viewport);
    await page.goto('/');
    await page.evaluate(() => document.fonts.ready);
    const toggle = page.locator('.shift-toggle');
    await toggle.click();
    await expect(toggle).toHaveAttribute('aria-expanded', 'true');
    const last = page.locator('a[data-chapter-link]').last();
    await last.scrollIntoViewIfNeeded();
    const box = (await last.boundingBox())!;
    const vh = devices[name].viewport.height;
    expect(box.y + box.height, `${browserName}: the last chapter link ends inside the screen`).toBeLessThanOrEqual(vh);
    if (name === 'iPhone 15 landscape') {
      // No scrolling needed on the larger phone: all nine show at once.
      const all = await page.locator('a[data-chapter-link]').evaluateAll((els) => els.map((e) => e.getBoundingClientRect().bottom));
      expect(Math.max(...all)).toBeLessThanOrEqual(vh);
    }
    await last.click();
    await expect(page).toHaveURL(/#open$/);
  });
}

test('the chapter panel closes when keyboard focus leaves it', async ({ page, isMobile }) => {
  test.skip(!isMobile, 'the disclosure is the mobile pattern');
  await page.goto('/');
  const toggle = page.locator('.shift-toggle');
  await toggle.focus();
  await page.keyboard.press('Enter');
  await expect(toggle).toHaveAttribute('aria-expanded', 'true');
  // Tab through the nine links and out of the panel.
  for (let i = 0; i < 10; i += 1) await page.keyboard.press('Tab');
  await expect(toggle).toHaveAttribute('aria-expanded', 'false');
});

test('pause motion says what it does in each state, and is a 44px target', async ({ page }) => {
  await page.goto('/');
  const pause = page.locator('[data-pause-toggle]');
  await expect(pause).toHaveAccessibleName('Pause motion');
  const box = (await pause.boundingBox())!;
  expect(box.width).toBeGreaterThanOrEqual(44);
  expect(box.height).toBeGreaterThanOrEqual(44);
  await pause.click();
  await expect(pause).toHaveAttribute('aria-pressed', 'true');
  await expect(pause).toHaveAccessibleName('Pause motion');
  await expect(pause.locator('.tip-on')).toHaveText('Motion paused · Resume');
  await expect(pause.locator('.tip-on')).toBeAttached();
  expect(await pause.locator('.tip-off').evaluate((e) => getComputedStyle(e).display)).toBe('none');
  await pause.click();
});

test('the header pill says a beta is coming at every width', async ({ page }) => {
  test.setTimeout(120_000);
  for (const width of [320, 375, 414, 600, 1440]) {
    await page.setViewportSize({ width, height: 800 });
    await page.goto('/');
    const text = (await page.locator('header .pill-status').innerText()).replace(/\s+/g, ' ');
    expect(text, `${width}px`).toMatch(/In development/);
    expect(text, `${width}px`).toMatch(/beta coming/i);
    // The pill fits the bar.
    const box = (await page.locator('header .pill-status').boundingBox())!;
    expect(box.height, `${width}px`).toBeLessThanOrEqual(48);
  }
});
