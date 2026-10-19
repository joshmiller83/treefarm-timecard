/**
 * Screenshot tool: look at the page the way a visitor scrolls it.
 *
 *   npm run shoot -- [--url /] [--section voice] [--widths 375,1440] [--steps 6]
 *                    [--reduced] [--out .shots/name] [--port 4321] [--browser chromium]
 *                    [--wait 900] [--no-full] [--build] [--selector 'header'] [--scale 2]
 *
 * - Builds once if dist/ is missing or older than src/ or public/ (or with --build).
 * - Serves dist with `astro preview` on --port (stops it when done). If something already
 *   answers on --port it is reused as is (a warning says so: it may be another build).
 *   Under an AI agent Astro 7.4 starts preview as a background server; this script stops it
 *   with `astro preview stop` when done.
 * - For each width: viewport shots stepping through the whole page, or through one section's
 *   scroll track with --section, plus a full-page shot. --reduced emulates
 *   prefers-reduced-motion (the static page).
 * - --selector shoots just that element at each step (e.g. the header); --scale sets the DPR.
 * - Writes PNGs to .shots/<name>/ (git-ignored) and prints their paths.
 */
import { spawn, spawnSync, type ChildProcess } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { chromium, firefox, webkit, type Page } from '@playwright/test';

const site = resolve(fileURLToPath(new URL('..', import.meta.url)));

const { values: args } = parseArgs({
  options: {
    url: { type: 'string', default: '/' },
    section: { type: 'string' },
    widths: { type: 'string', default: '375,1440' },
    steps: { type: 'string', default: '6' },
    reduced: { type: 'boolean', default: false },
    out: { type: 'string' },
    port: { type: 'string', default: '4321' },
    browser: { type: 'string', default: 'chromium' },
    wait: { type: 'string', default: '900' },
    'no-full': { type: 'boolean', default: false },
    build: { type: 'boolean', default: false },
    name: { type: 'string' },
    selector: { type: 'string' },
    scale: { type: 'string' },
  },
});

const HEIGHTS: Record<number, number> = { 320: 640, 375: 812, 390: 844, 768: 1024, 1024: 768, 1280: 800, 1440: 900, 1920: 1080 };
const widths = args.widths.split(',').map((w) => Number(w.trim())).filter(Boolean);
const steps = Math.max(1, Number(args.steps));
const settle = Number(args.wait);
const port = Number(args.port);
const base = `http://localhost:${port}`;
const name = args.name ?? args.section ?? (args.url === '/' ? 'page' : args.url.replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, ''));
const outDir = resolve(site, args.out ?? join('.shots', name));

function newestMtime(dir: string): number {
  let newest = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    newest = Math.max(newest, entry.isDirectory() ? newestMtime(p) : statSync(p).mtimeMs);
  }
  return newest;
}

function buildIfNeeded() {
  const index = join(site, 'dist', 'index.html');
  const stale =
    args.build ||
    !existsSync(index) ||
    Math.max(newestMtime(join(site, 'src')), newestMtime(join(site, 'public')), statSync(join(site, 'astro.config.mjs')).mtimeMs) >
      statSync(index).mtimeMs;
  if (!stale) return;
  console.log('Building…');
  const r = spawnSync(process.execPath, [join(site, 'node_modules', 'astro', 'bin', 'astro.mjs'), 'build'], { cwd: site, stdio: 'inherit' });
  if (r.status !== 0) throw new Error('astro build failed');
}

const astroBin = join(site, 'node_modules', 'astro', 'bin', 'astro.mjs');

async function answers(): Promise<boolean> {
  try {
    return (await fetch(base + '/')).ok;
  } catch {
    return false;
  }
}

/** True when this run started the server (so it stops it afterwards). */
let ownServer = false;

async function startPreview(): Promise<ChildProcess | null> {
  if (await answers()) {
    console.warn(`shoot: reusing the server already on port ${port} (if it serves another build, stop it first)`);
    return null;
  }
  ownServer = true;
  const child = spawn(process.execPath, [join(site, 'node_modules', 'astro', 'bin', 'astro.mjs'), 'preview', '--port', String(port)], {
    cwd: site,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if (await answers()) return child;
    await new Promise((r) => setTimeout(r, 200));
  }
  stopPreview(child);
  throw new Error(`astro preview did not start on port ${port}`);
}

/** Kills the child and, if this run started the server, stops this project's background preview too. */
function stopPreview(child: ChildProcess | null) {
  child?.kill();
  if (ownServer) {
    ownServer = false;
    spawnSync(process.execPath, [astroBin, 'preview', 'stop'], { cwd: site, stdio: 'ignore' });
  }
}

const pause = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function scrollRange(page: Page): Promise<[number, number]> {
  return page.evaluate((id) => {
    const vh = innerHeight;
    if (!id) return [0, Math.max(0, document.documentElement.scrollHeight - vh)];
    const el = document.getElementById(id);
    if (!el) throw new Error(`No section #${id}`);
    const track = el.querySelector('.track') ?? el;
    const top = track.getBoundingClientRect().top + scrollY;
    const h = (track as HTMLElement).offsetHeight;
    return [Math.max(0, top - (h > vh ? 0 : vh * 0.3)), Math.max(top, top + h - vh)];
  }, args.section ?? null);
}

let server: ChildProcess | null = null;
process.on('exit', () => stopPreview(server));
setTimeout(() => {
  console.error('shoot: timed out after 5 minutes');
  process.exit(2);
}, 300_000).unref();

async function main() {
  buildIfNeeded();
  mkdirSync(outDir, { recursive: true });
  server = await startPreview();
  const engine = { chromium, firefox, webkit }[args.browser as 'chromium'] ?? chromium;
  const browser = await engine.launch();
  const written: string[] = [];
  try {
    for (const width of widths) {
      const height = HEIGHTS[width] ?? Math.round(width * 0.625);
      const context = await browser.newContext({
        viewport: { width, height },
        deviceScaleFactor: args.scale ? Number(args.scale) : width < 900 ? 2 : 1,
        reducedMotion: args.reduced ? 'reduce' : 'no-preference',
        hasTouch: width < 900,
        isMobile: width < 900 && args.browser === 'chromium',
      });
      const page = await context.newPage();
      page.on('pageerror', (e) => console.warn(`[page error] ${e.message}`));
      await page.goto(base + args.url, { waitUntil: 'load' });
      await page.evaluate(() => document.fonts.ready);
      await page
        .evaluate(() =>
          Promise.race([(window as { __tf?: { ready: Promise<void> } }).__tf?.ready, new Promise((r) => setTimeout(r, 4000))]),
        )
        .catch(() => undefined);
      await pause(1500);
      const tag = `${width}${args.reduced ? '-reduced' : ''}`;
      const [from, to] = await scrollRange(page);
      for (let i = 0; i < steps; i += 1) {
        const y = steps === 1 ? from : Math.round(from + ((to - from) * i) / (steps - 1));
        await page.evaluate((top) => window.scrollTo(0, top), y);
        await pause(settle);
        const file = join(outDir, `${tag}-${String(i + 1).padStart(2, '0')}.png`);
        if (args.selector) await page.locator(args.selector).first().screenshot({ path: file });
        else await page.screenshot({ path: file });
        written.push(file);
      }
      if (!args['no-full'] && !args.selector) {
        // content-visibility: auto skips far sections, which a full-page capture would show blank.
        await page.addStyleTag({ content: '.sec { content-visibility: visible !important; }' });
        await page.evaluate(() => window.scrollTo(0, 0));
        await pause(settle);
        const file = join(outDir, `${tag}-full.png`);
        if (args.section) {
          const box = await page.locator(`#${args.section}`).boundingBox();
          if (box) await page.screenshot({ path: file, fullPage: true, scale: 'css', clip: { x: 0, y: box.y, width, height: Math.min(box.height, 16000) } });
        } else {
          await page.screenshot({ path: file, fullPage: true, scale: 'css' });
        }
        written.push(file);
      }
      await context.close();
    }
  } finally {
    await browser.close();
    stopPreview(server);
  }
  console.log(written.join('\n'));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
