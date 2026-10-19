import { expect, test } from '@playwright/test';
import { SECTION_IDS, scrollThrough, settle, watch } from './helpers';

test('has the title, the nine chapters in order, and no errors', async ({ page }) => {
  const { problems } = watch(page);
  await page.goto('/');
  await settle(page);
  await expect(page).toHaveTitle('Time Card · A hands-free time card for Christmas tree trimmers');
  const ids = await page.locator('main > section').evaluateAll((els) => els.map((e) => e.id));
  expect(ids).toEqual(SECTION_IDS);
  await expect(page.locator('h1')).toHaveCount(1);
  await expect(page.locator('h1')).toHaveText('Keep your gloves on.');
  for (const id of SECTION_IDS) await expect(page.locator(`#${id}`)).toHaveAttribute('aria-labelledby', `${id}-h`);
  await scrollThrough(page);
  expect(problems).toEqual([]);
});

test('boots the motion core when motion is allowed', async ({ page }) => {
  const { problems } = watch(page);
  await page.goto('/');
  await settle(page);
  await expect(page.locator('html')).toHaveClass(/motion-ready/);
  await expect(page.locator('html')).not.toHaveClass(/motion-failed/);
  expect(problems).toEqual([]);
});

test('tells the truth: status in the hero and header, no prices, GitHub-only links', async ({ page }) => {
  await page.goto('/');
  const status = 'In development · TestFlight beta coming';
  await expect(page.locator('#hero')).toContainText(status);
  await expect(page.locator('header .pill-status')).toContainText('In development');
  const text = await page.evaluate(() => document.body.innerText);
  // No dollar figures anywhere (the brief's text scan for '$').
  expect(text).not.toContain('$');
  expect(text).not.toMatch(/\b(download|get the app|join the beta)\b/i);
  const hrefs = await page.locator('a[href]').evaluateAll((as) => as.map((a) => (a as HTMLAnchorElement).href));
  for (const href of hrefs) {
    const u = new URL(href);
    if (u.origin === new URL(page.url()).origin) continue;
    expect(u.hostname, href).toBe('github.com');
    expect(u.pathname.startsWith('/joshmiller83/treefarm-timecard'), href).toBe(true);
  }
  expect(hrefs.some((h) => h.startsWith('mailto:'))).toBe(false);
});

test('has the meta, social and structured data', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('link[rel=canonical]')).toHaveAttribute('href', 'https://treefarm.joshnliz.com/');
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', 'https://treefarm.joshnliz.com/og.png');
  await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute('content', 'summary_large_image');
  // No viewport-fit=cover: nothing on the page pads for the notch, so iOS keeps it in the safe area.
  await expect(page.locator('meta[name="viewport"]')).toHaveAttribute('content', 'width=device-width, initial-scale=1');
  const ld = JSON.parse((await page.locator('script[type="application/ld+json"]').textContent()) ?? '{}');
  const types = ld['@graph'].map((n: { '@type': string }) => n['@type']);
  expect(types).toEqual(['SoftwareSourceCode']);
  const json = JSON.stringify(ld);
  expect(json).not.toMatch(/aggregateRating|offers|review|price/i);
  for (const path of ['/og.png', '/favicon.svg', '/favicon.ico', '/apple-touch-icon.png', '/robots.txt', '/sitemap-index.xml', '/CNAME']) {
    const res = await page.request.get(path);
    expect(res.status(), path).toBe(200);
  }
  const sitemap = await (await page.request.get('/sitemap-0.xml')).text();
  expect(sitemap).toContain('https://treefarm.joshnliz.com/');
  expect(sitemap).not.toContain('/lab');
  expect(sitemap).not.toContain('/og');
});

test('a bad URL gets the page’s own 404, with the ways back', async ({ page }) => {
  const res = await page.goto('/no-such-row/');
  expect(res?.status()).toBe(404);
  await expect(page.locator('h1')).toHaveText('This row isn’t on the map.');
  await expect(page.getByRole('link', { name: 'Back to Time Card' })).toHaveAttribute('href', '/');
  await expect(page.getByRole('link', { name: /The code on GitHub/ })).toHaveAttribute('href', 'https://github.com/joshmiller83/treefarm-timecard');
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', 'noindex, nofollow');
});
