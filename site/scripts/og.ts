/**
 * Renders the Open Graph image from the hidden /og route into public/og.png.
 *   npm run og        (builds first if needed; serves dist on --port, default 4321)
 * Commit the PNG: the site build never depends on this script.
 */
import { spawn, spawnSync } from 'node:child_process';
import { statSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { chromium } from '@playwright/test';

// upng-js is CommonJS: quantize the screenshot to a 256-color palette so og.png stays under 120 KB.
const UPNG = createRequire(import.meta.url)('upng-js') as {
  decode(buf: ArrayBuffer): { width: number; height: number };
  toRGBA8(img: unknown): ArrayBuffer[];
  encode(frames: ArrayBuffer[], w: number, h: number, colors: number): ArrayBuffer;
};
const site = resolve(fileURLToPath(new URL('..', import.meta.url)));
const { values } = parseArgs({ options: { port: { type: 'string', default: '4321' } } });
const port = Number(values.port);
const astro = join(site, 'node_modules', 'astro', 'bin', 'astro.mjs');

const build = spawnSync(process.execPath, [astro, 'build'], { cwd: site, stdio: 'inherit' });
if (build.status !== 0) process.exit(1);

const server = spawn(process.execPath, [astro, 'preview', '--port', String(port)], { cwd: site, stdio: 'ignore' });
process.on('exit', () => server.kill());
try {
  const deadline = Date.now() + 20000;
  for (;;) {
    try {
      if ((await fetch(`http://localhost:${port}/og/`)).ok) break;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error('preview did not start');
    await new Promise((r) => setTimeout(r, 200));
  }
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  await page.goto(`http://localhost:${port}/og/`, { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  const out = join(site, 'public', 'og.png');
  const shot = await page.locator('[data-og]').screenshot();
  await browser.close();
  const img = UPNG.decode(shot.buffer.slice(shot.byteOffset, shot.byteOffset + shot.byteLength) as ArrayBuffer);
  writeFileSync(out, Buffer.from(UPNG.encode(UPNG.toRGBA8(img), img.width, img.height, 256)));
  console.log(`wrote public/og.png (${Math.round(statSync(out).size / 1024)} KB)`);
} finally {
  server.kill();
}
