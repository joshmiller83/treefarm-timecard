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
