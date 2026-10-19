# Time Card landing page

The marketing page for Tree Farm Time Card at **https://treefarm.joshnliz.com**: one
scrollytelling page that carries one trimmer through one Friday shift. Astro 7.4 (static),
GSAP 3.15 (ScrollTrigger, SplitText, Flip), vanilla TypeScript, deployed to GitHub Pages
by `.github/workflows/site.yml`.

- The spec: `../docs/landing/brief.json` (read parts with `jq`, e.g.
  `jq '.sections[] | select(.id=="voice")' ../docs/landing/brief.json`) and
  `../docs/landing/decisions.md`, which wins where they differ.
- The shared component contract: [`src/components/CONTRACT.md`](src/components/CONTRACT.md).

## Run it

Use Node 24. On the build Mac:

```sh
export PATH=/Users/jm/Developer/gh/miller-audiobookshelf/vendor/node-v24.21.0-darwin-x64/bin:$PATH
cd site
npm ci
npm run dev            # http://localhost:4321 (use your team's port: npm run dev -- --port 4330)
```

| Script | What it does |
|---|---|
| `npm run dev` | Astro dev server (port 4321 by default; pass `-- --port N`) |
| `npm run build` | Static build into `dist/` (prints any unverified Siri lines) |
| `npm run preview` | Serves `dist/` on 4321 |
| `npm run check` | `astro check` (TypeScript strict) |
| `npm test` | Vitest: ledger arithmetic, Siri wording, DayClock math, odometer |
| `npm run test:e2e` | Playwright against the built site (smoke, reduced motion, axe, overflow, nav). Build first. `PW_PORT=4330` to change the port, `PW_ALL=1` to add WebKit and Firefox |
| `npm run test:all` | check + unit + build + e2e |
| `npm run shoot -- …` | Screenshots (below) |
| `npm run og` | Rebuilds `public/og.png` from the hidden `/og/` route (commit the PNG) |
| `npm run icons` | Rebuilds the favicons from `../tools/make_icon.swift` (macOS: needs `swift` and `sips`) |

Useful URLs: `/` (motion), `/?motion=off` (the static page everyone without motion gets),
`/?motion=on` (force motion), `/lab/` (component workbenches), `/og/` (OG template).

## Look at your work: `npm run shoot`

```sh
npm run shoot -- [--url /] [--section voice] [--widths 375,1440] [--steps 6] [--reduced] \
                 [--out .shots/name] [--port 4321] [--browser chromium|webkit|firefox] \
                 [--wait 900] [--no-full] [--build] [--name name]
```

- Builds once if `dist/` is missing or older than `src/`, `public/` or the config (`--build` forces it).
- Serves `dist/` with `astro preview` on `--port` and stops it afterwards. **Use your team's port.**
- For each width it writes viewport shots stepping through the whole page, or through one
  section's scroll track with `--section <id>`, plus a full-page shot, to `.shots/<name>/`
  (git-ignored): `1440-01.png … 1440-full.png`, `375-reduced-03.png` and so on.
- `--reduced` emulates `prefers-reduced-motion: reduce` (the static page, no GSAP).
- Lab pages work too: `npm run shoot -- --url /lab/device-a/ --widths 1440 --steps 2`.

Read the PNGs. Check 375 and 1440, several scroll positions, and reduced motion.

## How the page works

- **Static first.** The server markup is each section's final state and the whole page works
  without JavaScript. An inline head script adds `html.motion` only when motion is allowed
  (no reduced-motion preference, window ≥ 560px tall, no Save-Data). Every from-state lives
  under `.motion`. If the motion bundle has not booted in 4 s, `.motion` comes off again.
- **First load** is tiny: the header script and `src/scripts/main.ts`, which imports the motion
  core (`motion.ts`: GSAP + plugins + DayClock + stage) on idle, only under `.motion`.
  Reduced-motion visitors never download GSAP.
- **Sections** use `SectionShell`: a tall track with a 100svh `position: sticky` frame (no
  ScrollTrigger pins). Copy beats sit at scroll progress `--at` (0–1). Each section's scene
  (`src/scripts/scenes/<id>.ts`) is imported and built lazily when the section is within
  1.5 viewports, inside `gsap.matchMedia` (`desk` ≥ 900px wide and ≥ 560px tall, `mob` below 900px).
- **The stage** (desktop with motion): one fixed phone. When a section becomes active its
  `[data-screens]` container moves into the stage phone (0.35 s crossfade and sheen) and its
  own figure is visually hidden but still read by screen readers. `--stage-x/-y/-w/-h` on
  `:root` give the stage phone's rect for section extras. On mobile each section shows its
  own sticky phone.
- **DayClock** (`dayclock.ts`): one shared minute drives status-bar clocks (`[data-clock]`),
  Live Activity timers (`[data-timer]`), the shift ribbon and the header DayMark. Scenes tween
  it with `day.to(tl, minute, start, end)`; only the active section's tween shows. Timers tick in
  real time for up to 5 s after scrolling stops. Pause motion stops all of it.
- **One ledger**: every number comes from `src/data/ledger.ts`, every spoken line from
  `src/data/siri.ts`. Never type a number or a Siri line by hand.

## File ownership

| Owner | Files |
|---|---|
| foundation (branch `site`) | `astro.config.mjs`, `package.json`, configs, `scripts/`, `tests/`, `src/styles/`, `src/data/`, `src/layouts/`, `src/pages/index.astro`, `src/pages/og.astro`, `src/pages/lab/index.astro`, `src/pages/lab/foundation.astro`, `src/scripts/{main,motion,stage,dayclock,util,scene,odometer,header}.ts`, `src/components/{SectionShell,Header,DayMark,AppIcon}.astro`, `src/components/app/{AppChrome,Icon,IconSprite}.astro`, `src/components/app/icons.ts`, `src/components/dev/`, `src/components/CONTRACT.md`, `.github/workflows/site.yml` |
| device-a | `src/components/phone/{Phone,StatusBar,Screen,LockScreen,LiveActivity}.astro`, `src/pages/lab/device-a.astro` |
| device-b | `src/components/phone/{DynamicIsland,SiriSnippet,SiriGlow,DictationWave}.astro`, `src/scripts/wave.ts`, `src/components/ControlsCard.astro`, `src/pages/lab/device-b.astro` |
| screens | `src/components/app/{ClockTab,TeamTab,TreeNoteSheet}.astro`, `src/pages/lab/screens.astro` |
| map | `src/components/app/TreesTab.astro`, `src/components/FieldMap.astro`, `src/scripts/fieldmap.ts`, `src/pages/lab/map.astro` |
| report | `src/components/app/ReportTab.astro`, `src/components/PaperTimeCard.astro`, `src/pages/lab/report.astro` |
| section teams | `src/sections/<PascalCaseId>.astro` and `src/scripts/scenes/<id>.ts` for their chapter; the open team also owns `src/components/Footer.astro` |

Need a change in a file you don't own (a token, a ledger value, a new glyph, a SectionShell
prop)? Ask its owner; don't edit it in your worktree.

## Real simulator captures

Recreated screens are stand-ins for real captures. To swap one in, export a 1179 × 2556
screenshot from the simulator and save it as `public/screens/<state-id>.png` (or `.webp` /
`.avif`), where `<state-id>` is the `stateId` of the matching `<Screen>` (the full registry is
in `src/components/CONTRACT.md`). The next build renders the capture in place of the HTML
recreation, with the same alt text. Capture first: `lock-1414-activity`, `trees-1415-block2`,
`report-week`.

## CI and deploy

`.github/workflows/site.yml` runs on pushes and pull requests that touch `site/**`,
`docs/landing/**`, the root README or the workflow: `npm ci`, type check, unit tests, build,
Playwright (Chromium), Lighthouse CI on mobile (median of 3 runs: performance ≥ 0.9,
accessibility, best practices and SEO ≥ 0.95), then uploads `site/dist` as the Pages
artifact. Only a push to `main` deploys (`actions/deploy-pages`, environment `github-pages`).
Lighthouse skips the `canonical` audit because CI audits `localhost` while the canonical URL
is the production domain.

Pages settings: source "GitHub Actions", custom domain `treefarm.joshnliz.com`
(`public/CNAME`), Enforce HTTPS. DNS: `treefarm` CNAME `joshmiller83.github.io`, DNS only.

## Budgets (from the brief)

HTML ≤ 75 KB gz, CSS ≤ 35 KB gz, first-load JS ≤ 6 KB gz, motion bundle ≤ 80 KB gz, fonts
≤ 120 KB (Zilla Slab 700 and Public Sans 400 preloaded; prefer Public Sans 400/600 and Plex Mono
500/600, every extra weight costs about 15 KB), images: og.png and one blurred WebP only.
Animate only transform, opacity, clip-path and stroke-dashoffset.
