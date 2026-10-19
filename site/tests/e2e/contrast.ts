import { createRequire } from 'node:module';
import type { Page } from '@playwright/test';

/**
 * Pixel-sampled contrast: text over gradients, tints and photos (which axe reports as
 * 'incomplete'). The text is made transparent for one screenshot of its box, so every pixel
 * of that shot is the background it sits on; the text's own colour (with its opacity chain)
 * is then checked against each of those pixels. Returns the worst ratio (5th percentile,
 * so a stray anti-aliased edge of a neighbour doesn't decide it).
 */
const UPNG = createRequire(import.meta.url)('upng-js') as {
  decode(buf: ArrayBuffer): { width: number; height: number };
  toRGBA8(img: { width: number; height: number }): ArrayBuffer[];
};

const lum = (r: number, g: number, b: number) => {
  const c = [r, g, b].map((v) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * c[0]! + 0.7152 * c[1]! + 0.0722 * c[2]!;
};
const ratio = (a: number, b: number) => (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);

export interface ContrastResult {
  selector: string;
  ratio: number;
  fontPx: number;
  bold: boolean;
  /** WCAG AA: 3 for large text (24px, or 18.66px bold), 4.5 otherwise. */
  needed: number;
}

export async function contrastOf(page: Page, selector: string, index = 0): Promise<ContrastResult | null> {
  const info = await page.evaluate(
    ({ selector, index }) => {
      const el = document.querySelectorAll<HTMLElement>(selector)[index];
      if (!el) return null;
      const r = el.getBoundingClientRect();
      if (r.width < 1 || r.height < 1 || r.bottom < 0 || r.top > innerHeight) return null;
      const cs = getComputedStyle(el);
      let alpha = 1;
      for (let n: Element | null = el; n; n = n.parentElement) alpha *= Number(getComputedStyle(n).opacity);
      const m = cs.color.match(/[\d.]+/g)!.map(Number);
      el.setAttribute('data-contrast-probe', '');
      return {
        box: { x: Math.max(0, r.left), y: Math.max(0, r.top), width: Math.min(innerWidth, r.right) - Math.max(0, r.left), height: Math.min(innerHeight, r.bottom) - Math.max(0, r.top) },
        rgb: [m[0]!, m[1]!, m[2]!] as [number, number, number],
        a: (m[3] ?? 1) * alpha,
        fontPx: parseFloat(cs.fontSize),
        bold: Number(cs.fontWeight) >= 600,
      };
    },
    { selector, index },
  );
  if (!info || info.box.width < 1 || info.box.height < 1) return null;
  const style = await page.addStyleTag({
    content: '[data-contrast-probe], [data-contrast-probe] * { color: transparent !important; -webkit-text-fill-color: transparent !important; text-decoration-color: transparent !important; }',
  });
  const png = await page.screenshot({ clip: info.box, animations: 'disabled' });
  await style.evaluate((s) => (s as Element).remove());
  await page.evaluate((selector) => document.querySelectorAll('[data-contrast-probe]').forEach((e) => e.removeAttribute('data-contrast-probe')), selector);
  const img = UPNG.decode(png.buffer.slice(png.byteOffset, png.byteOffset + png.byteLength) as ArrayBuffer);
  const px = new Uint8Array(UPNG.toRGBA8(img)[0]!);
  const ratios: number[] = [];
  const step = Math.max(1, Math.floor((img.width * img.height) / 4000));
  for (let i = 0; i < img.width * img.height; i += step) {
    const [br, bg, bb] = [px[i * 4]!, px[i * 4 + 1]!, px[i * 4 + 2]!];
    // The text as it renders: its colour composited over this pixel at its opacity.
    const tr = info.rgb[0] * info.a + br * (1 - info.a);
    const tg = info.rgb[1] * info.a + bg * (1 - info.a);
    const tb = info.rgb[2] * info.a + bb * (1 - info.a);
    ratios.push(ratio(lum(tr, tg, tb), lum(br, bg, bb)));
  }
  ratios.sort((a, b) => a - b);
  const worst = ratios[Math.floor(ratios.length * 0.05)] ?? 21;
  const large = info.fontPx >= 24 || (info.bold && info.fontPx >= 18.66);
  return { selector, ratio: Math.round(worst * 100) / 100, fontPx: info.fontPx, bold: info.bold, needed: large ? 3 : 4.5 };
}
