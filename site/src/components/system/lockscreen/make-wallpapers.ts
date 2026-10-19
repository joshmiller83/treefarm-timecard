/**
 * Writes the lock-screen wallpapers and the pre-blurred twin behind the Live Activity:
 *
 *   node src/components/system/lockscreen/make-wallpapers.ts
 *
 * - dawn-rows.svg, dusk-rows.svg: from wallpaper.ts (wallpaper.test.ts fails if they drift).
 * - dawn-rows-blur.webp: the dawn wallpaper rendered in Chromium, blurred the way iOS blurs
 *   a wallpaper under a Live Activity, at a third of the 3x pixel size (a blur this wide
 *   has no detail to lose), encoded as WebP. The brief allows one blurred WebP of 12 KB or less.
 *
 * Run it after changing wallpaper.ts, then commit the outputs.
 */
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { WALLPAPERS, WP, wallpaperSVG } from './wallpaper.ts';

const here = dirname(fileURLToPath(import.meta.url));

for (const id of WALLPAPERS) {
  const svg = wallpaperSVG(id);
  writeFileSync(join(here, `${id}.svg`), svg);
  console.log(`${id}.svg  ${svg.length} bytes`);
}

/** Twin size: 393 × 852 pt at 1x; the browser scales it up under heavy blur. */
const SCALE = 1;
const BLUR = 22; // pt: iOS's lock-screen material is a wide, soft blur

const browser = await chromium.launch();
const page = await browser.newPage();
const svg = wallpaperSVG('dawn-rows');
const dataUrl: string = await page.evaluate(
  async ({ svg, w, h, scale, blur }) => {
    const img = new Image();
    img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
    await img.decode();
    const W = Math.round(w * scale);
    const H = Math.round(h * scale);
    // 1. A padded copy: the wallpaper stretched behind itself, so the blur has no clear edges.
    const pad = Math.round(blur * 3 * scale);
    const big = document.createElement('canvas');
    big.width = W + pad * 2;
    big.height = H + pad * 2;
    const b = big.getContext('2d')!;
    b.drawImage(img, 0, 0, big.width, big.height);
    b.drawImage(img, pad, pad, W, H);
    // 2. Blur it into the exact screen rect, so the twin lines up with the wallpaper.
    const canvas = document.createElement('canvas');
    canvas.width = W;
    canvas.height = H;
    const ctx = canvas.getContext('2d')!;
    ctx.filter = `blur(${blur * scale}px) saturate(1.25)`;
    ctx.drawImage(big, -pad, -pad);
    return canvas.toDataURL('image/webp', 0.72);
  },
  { svg, w: WP.w, h: WP.h, scale: SCALE, blur: BLUR },
);
await browser.close();

const webp = Buffer.from(dataUrl.split(',')[1]!, 'base64');
writeFileSync(join(here, 'dawn-rows-blur.webp'), webp);
console.log(`dawn-rows-blur.webp  ${webp.length} bytes`);
