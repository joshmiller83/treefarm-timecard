import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright runs against the built site (astro preview), like production.
 *   npm run build && npm run test:e2e
 * The page's tests live in tests/e2e and tests/sections (one spec per chapter), both run by the
 * page projects (desktop, mobile); the component workbenches' tests in tests/lab (lab-desktop,
 * lab-mobile), one spec per shared component team. One chapter:
 *   npm run test:e2e -- --project=desktop --project=mobile tests/sections/voice.spec.ts
 * One team's lab:
 *   npm run test:e2e -- --project=lab-desktop --project=lab-mobile tests/lab/device-a.spec.ts
 * PW_PORT overrides the port (default 4321). PW_ALL=1 adds WebKit and Firefox projects (page and lab).
 */
const port = Number(process.env.PW_PORT ?? 4321);
const all = !!process.env.PW_ALL;
/** The page projects run tests/e2e and tests/sections; the lab projects run tests/lab. */
const page = { testMatch: /(e2e|sections)\/.*\.spec\.ts$/ };

export default defineConfig({
  testDir: 'tests',
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
    { name: 'desktop', ...page, use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'mobile', ...page, use: { ...devices['Pixel 7'], viewport: { width: 375, height: 812 } } },
    { name: 'lab-desktop', testDir: 'tests/lab', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } } },
    { name: 'lab-mobile', testDir: 'tests/lab', use: { ...devices['Pixel 7'], viewport: { width: 375, height: 812 } } },
    ...(all
      ? [
          { name: 'webkit-mobile', ...page, use: { ...devices['iPhone 15'], viewport: { width: 375, height: 812 } } },
          { name: 'firefox-desktop', ...page, use: { ...devices['Desktop Firefox'], viewport: { width: 1440, height: 900 } } },
          { name: 'lab-webkit-mobile', testDir: 'tests/lab', use: { ...devices['iPhone 15'], viewport: { width: 375, height: 812 } } },
          { name: 'lab-firefox-desktop', testDir: 'tests/lab', use: { ...devices['Desktop Firefox'], viewport: { width: 1440, height: 900 } } },
        ]
      : []),
  ],
});
