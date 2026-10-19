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
/**
 * Timing-sensitive specs (long animation frames; axe at 24 scroll positions) run alone, one
 * test at a time, after every other project has finished: on a machine busy with parallel
 * workers their frames run long and axe runs stretch for reasons that are not the page's.
 * A failure elsewhere skips them (project dependencies); run them on their own with
 * `--project=desktop-solo --project=mobile-solo --no-deps`.
 */
const solo = /e2e\/(perf|a11y-scroll)\.spec\.ts$/;
/** The page projects run tests/e2e and tests/sections; the lab projects run tests/lab. */
const page = { testMatch: /(e2e|sections)\/.*\.spec\.ts$/, testIgnore: solo };
const devicesFor = {
  desktop: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 900 } },
  mobile: { ...devices['Pixel 7'], viewport: { width: 375, height: 812 } },
  'webkit-mobile': { ...devices['iPhone 15'], viewport: { width: 375, height: 812 } },
  'firefox-desktop': { ...devices['Desktop Firefox'], viewport: { width: 1440, height: 900 } },
};
const pageProjects = (all ? ['desktop', 'mobile', 'webkit-mobile', 'firefox-desktop'] : ['desktop', 'mobile']) as Array<keyof typeof devicesFor>;
const labProjects = [
  { name: 'lab-desktop', testDir: 'tests/lab', use: devicesFor.desktop },
  { name: 'lab-mobile', testDir: 'tests/lab', use: devicesFor.mobile },
  ...(all
    ? [
        { name: 'lab-webkit-mobile', testDir: 'tests/lab', use: devicesFor['webkit-mobile'] },
        { name: 'lab-firefox-desktop', testDir: 'tests/lab', use: devicesFor['firefox-desktop'] },
      ]
    : []),
];
const rest = [...pageProjects, ...labProjects.map((p) => p.name)];

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
    ...pageProjects.map((name) => ({ name, ...page, use: devicesFor[name] })),
    ...labProjects,
    // One after another, each after everything else: `<name>-solo`.
    ...pageProjects.map((name, i) => ({
      name: `${name}-solo`,
      testMatch: solo,
      workers: 1,
      fullyParallel: false,
      dependencies: [...rest, ...pageProjects.slice(0, i).map((n) => `${n}-solo`)],
      use: devicesFor[name],
    })),
  ],
});
