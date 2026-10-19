import type { Page } from '@playwright/test';

export const SECTION_IDS = ['hero', 'voice', 'lock-screen', 'field', 'notes', 'crew', 'pace', 'clock-out', 'open'];

/** Collects console errors, page errors and failed requests while a test runs. */
export function watch(page: Page) {
  const problems: string[] = [];
  const requests: string[] = [];
  page.on('console', (m) => {
    if (m.type() === 'error') problems.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
  page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()} ${r.failure()?.errorText ?? ''}`));
  page.on('response', (r) => {
    if (r.status() >= 400) problems.push(`HTTP ${r.status()}: ${r.url()}`);
  });
  page.on('request', (r) => requests.push(r.url()));
  return { problems, requests };
}

/** Waits for the motion core (if this page runs it) to boot and build the first scenes. */
export async function settle(page: Page) {
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(async () => {
    const root = document.documentElement;
    if (!root.classList.contains('motion')) return;
    const t0 = performance.now();
    while (!(window as { __tf?: unknown }).__tf && performance.now() - t0 < 5000) await new Promise((r) => setTimeout(r, 50));
    const tf = (window as { __tf?: { ready: Promise<void> } }).__tf;
    if (tf) await Promise.race([tf.ready, new Promise((r) => setTimeout(r, 4000))]);
  });
}

/** Scrolls through the whole page in steps (builds every lazy scene). */
export async function scrollThrough(page: Page, steps = 12) {
  const h = await page.evaluate(() => document.documentElement.scrollHeight - innerHeight);
  for (let i = 0; i <= steps; i += 1) {
    await page.evaluate((y) => window.scrollTo(0, y), Math.round((h * i) / steps));
    await page.waitForTimeout(120);
  }
}
