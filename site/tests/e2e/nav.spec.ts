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
