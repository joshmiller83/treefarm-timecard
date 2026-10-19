import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright runs against the built site (astro preview), like production.
 *   npm run build && npm run test:e2e
 * PW_PORT overrides the port (default 4321). PW_ALL=1 adds WebKit and Firefox projects.
 */
const port = Number(process.env.PW_PORT ?? 4321);
const all = !!process.env.PW_ALL;

export default defineConfig({
  testDir: 'tests/e2e',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  use: {
    baseURL: `http://localhost:${port}`,
    trace: 'retain-on-failure',
  },
  webServer: {
    command: `npx astro preview --port ${port}`,
    url: `http://localhost:${port}/`,
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'mobile', use: { ...devices['Pixel 7'], viewport: { width: 375, height: 812 } } },
    ...(all
      ? [
          { name: 'webkit-mobile', use: { ...devices['iPhone 15'], viewport: { width: 375, height: 812 } } },
          { name: 'firefox-desktop', use: { ...devices['Desktop Firefox'], viewport: { width: 1440, height: 900 } } },
        ]
      : []),
  ],
});
