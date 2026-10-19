import { readFileSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { WALLPAPERS, wallpaperSVG } from './wallpaper.ts';

const here = dirname(fileURLToPath(import.meta.url));

describe('lock-screen wallpapers', () => {
  for (const id of WALLPAPERS) {
    it(`${id}.svg is current (run make-wallpapers.ts after editing wallpaper.ts)`, () => {
      expect(readFileSync(join(here, `${id}.svg`), 'utf8')).toBe(wallpaperSVG(id));
    });

    it(`${id} stays under Vite's 4 KB inline limit (one copy in the page CSS, no request)`, () => {
      expect(wallpaperSVG(id).length).toBeLessThan(4096);
    });

    it(`${id} is a 393 × 852 pt scene with no script, text or external reference`, () => {
      const svg = wallpaperSVG(id);
      expect(svg).toMatch(/^<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg" viewBox="0 0 393 852">/);
      expect(svg).not.toMatch(/<script|<text|<image|https?:\/\/(?!www\.w3\.org)/);
      // Every href points inside the file.
      for (const m of svg.matchAll(/href="([^"]+)"/g)) expect(m[1]).toMatch(/^#/);
    });
  }

  it('dawn rows use the brief gradient #0D2418 → #29483A → #C79A5E', () => {
    const svg = wallpaperSVG('dawn-rows');
    const i = (c: string) => svg.indexOf(c);
    expect(i('#0D2418')).toBeGreaterThan(0);
    expect(i('#29483A')).toBeGreaterThan(i('#0D2418'));
    expect(i('#C79A5E')).toBeGreaterThan(i('#29483A'));
  });

  it('is deterministic', () => {
    expect(wallpaperSVG('dawn-rows')).toBe(wallpaperSVG('dawn-rows'));
  });

  it('the blurred twin is one small WebP (brief: 12 KB or less)', () => {
    const file = join(here, 'dawn-rows-blur.webp');
    const head = readFileSync(file).subarray(0, 12).toString('latin1');
    expect(head.slice(0, 4)).toBe('RIFF');
    expect(head.slice(8, 12)).toBe('WEBP');
    expect(statSync(file).size).toBeLessThanOrEqual(12 * 1024);
  });
});
