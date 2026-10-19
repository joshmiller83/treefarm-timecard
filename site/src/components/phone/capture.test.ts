import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { afterAll, describe, expect, it } from 'vitest';
import {
  auditCaptures,
  CAPTURE_MAX_BYTES,
  CAPTURE_SIZE,
  captureDir,
  captureProblems,
  findCapture,
  imageSize,
  isStateId,
} from './capture.ts';

const dir = mkdtempSync(join(tmpdir(), 'screens-'));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

/** 13 × 29 images straight from cwebp and avifenc. */
const FIXTURES = {
  lossy: 'UklGRjwAAABXRUJQVlA4IDAAAACwAgCdASoNAB0APm0qkUWkIqGYBABABsSgCdAC0kAA/vGVcjDIf9bfRX72xHz8MAA=',
  lossless: 'UklGRh4AAABXRUJQVlA4TBEAAAAvDAAHAAfQrXZUp/+BiOh/AAA=',
  alpha:
    'UklGRmAAAABXRUJQVlA4WAoAAAAQAAAADAAAHAAAQUxQSAoAAAABB9C/iAhERP8DVlA4IDAAAACwAgCdASoNAB0APm0qkUWkIqGYBABABsSgCdAC0kAA/vGVcjDIf9bfRX72xHz8MAA=',
  avif: 'AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUEAAADybWV0YQAAAAAAAAAoaGRscgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAGxpYmF2aWYAAAAADnBpdG0AAAAAAAEAAAAeaWxvYwAAAABEAAABAAEAAAABAAABGgAAAB4AAAAoaWluZgAAAAAAAQAAABppbmZlAgAAAAABAABhdjAxQ29sb3IAAAAAamlwcnAAAABLaXBjbwAAABRpc3BlAAAAAAAAAA0AAAAdAAAAEHBpeGkAAAAAAwgICAAAAAxhdjFDgSAAAAAAABNjb2xybmNseAABAA0ABoAAAAAXaXBtYQAAAAAAAAABAAEEAQKDBAAAACZtZGF0EgAKCDgNM4wgIaDSMhAWQAYYYYQAAN++KOgaDm9A',
  png: 'iVBORw0KGgoAAAANSUhEUgAAAA0AAAAdCAYAAABxPebnAAAACXBIWXMAAAABAAAAAQBPJcTWAAAAHUlEQVR4nGOQjbb6TypmGNU0qmlU06imUU1DXhMA1O99yLY4TRoAAAAASUVORK5CYII=',
};
const bytes = (b64: string) => new Uint8Array(Buffer.from(b64, 'base64'));

/** A WebP header (VP8X) claiming width × height, padded to `size` bytes. */
function fakeWebp(width: number, height: number, size = 64) {
  const b = new Uint8Array(size);
  b.set(Buffer.from('RIFF'), 0);
  b.set(Buffer.from('WEBPVP8X'), 8);
  const put24 = (at: number, v: number) => b.set([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff], at);
  put24(24, width - 1);
  put24(27, height - 1);
  return b;
}

describe('findCapture', () => {
  it('returns null when no capture exists (the HTML recreation renders)', () => {
    expect(findCapture('lock-1414-activity', dir)).toBeNull();
  });

  it('finds a WebP capture by state id', () => {
    writeFileSync(join(dir, 'trees-1415-block2.webp'), '');
    expect(findCapture('trees-1415-block2', dir)).toBe('/screens/trees-1415-block2.webp');
  });

  it('prefers AVIF, then WebP, and never renders a PNG', () => {
    writeFileSync(join(dir, 'report-week.png'), '');
    expect(findCapture('report-week', dir)).toBeNull();
    writeFileSync(join(dir, 'report-week.webp'), '');
    expect(findCapture('report-week', dir)).toBe('/screens/report-week.webp');
    writeFileSync(join(dir, 'report-week.avif'), '');
    expect(findCapture('report-week', dir)).toBe('/screens/report-week.avif');
  });

  it('ignores ids that are not plain kebab-case (no path tricks)', () => {
    writeFileSync(join(dir, 'x.webp'), '');
    expect(isStateId('lock-1414-tapped')).toBe(true);
    expect(isStateId('../x')).toBe(false);
    expect(isStateId('Lock 1414')).toBe(false);
    expect(findCapture('../screens/x', dir)).toBeNull();
  });

  it('expects 1179 × 2556 captures (393 × 852 pt at 3x)', () => {
    expect(CAPTURE_SIZE.width / 3).toBe(393);
    expect(CAPTURE_SIZE.height / 3).toBe(852);
  });
});

describe('captureDir', () => {
  it('resolves public/screens from Astro’s publicDir, not the working directory', () => {
    const pub = pathToFileURL(join(dir, 'public') + '/');
    expect(captureDir(pub)).toBe(join(dir, 'public', 'screens'));
    expect(captureDir(join(dir, 'public'))).toBe(join(dir, 'public', 'screens'));
  });
});

describe('imageSize', () => {
  it('reads lossy, lossless and extended (alpha) WebP headers', () => {
    expect(imageSize(bytes(FIXTURES.lossy))).toEqual({ type: 'webp', width: 13, height: 29 });
    expect(imageSize(bytes(FIXTURES.lossless))).toEqual({ type: 'webp', width: 13, height: 29 });
    expect(imageSize(bytes(FIXTURES.alpha))).toEqual({ type: 'webp', width: 13, height: 29 });
    expect(imageSize(fakeWebp(1179, 2556))).toEqual({ type: 'webp', width: 1179, height: 2556 });
  });
  it('reads an AVIF’s image extents', () => {
    expect(imageSize(bytes(FIXTURES.avif))).toEqual({ type: 'avif', width: 13, height: 29 });
  });
  it('returns null for anything else', () => {
    expect(imageSize(bytes(FIXTURES.png))).toBeNull();
    expect(imageSize(new Uint8Array(8))).toBeNull();
  });
});

describe('captureProblems', () => {
  it('passes a 1179 × 2556 WebP under the size limit', () => {
    expect(captureProblems('lock-1414-activity.webp', fakeWebp(1179, 2556))).toEqual([]);
  });
  it('rejects PNG, the wrong size, a heavy file, a bad name and a mislabeled format', () => {
    expect(captureProblems('report-week.png', bytes(FIXTURES.png))[0]).toMatch(/use \.avif or \.webp/);
    expect(captureProblems('report-week.webp', bytes(FIXTURES.lossy))[0]).toMatch(/13 × 29, expected 1179 × 2556/);
    expect(captureProblems('report-week.webp', fakeWebp(1179, 2556, CAPTURE_MAX_BYTES + 1))[0]).toMatch(/over 200 KB/);
    expect(captureProblems('Report Week.webp', fakeWebp(1179, 2556))[0]).toMatch(/kebab-case/);
    expect(captureProblems('report-week.avif', fakeWebp(1179, 2556))[0]).toMatch(/not a readable AVIF/);
  });
});

describe('public/screens (the real captures)', () => {
  it('holds only AVIF or WebP captures, 1179 × 2556, at most 200 KB, named by state id', () => {
    const screens = fileURLToPath(new URL('../../../public/screens/', import.meta.url));
    expect(auditCaptures(screens)).toEqual([]);
  });
  it('the audit catches a bad file (and skips dotfiles such as .gitkeep)', () => {
    const d = mkdtempSync(join(tmpdir(), 'audit-'));
    try {
      writeFileSync(join(d, '.gitkeep'), '');
      expect(auditCaptures(d)).toEqual([]);
      writeFileSync(join(d, 'lock-1414-activity.png'), bytes(FIXTURES.png));
      expect(auditCaptures(d)).toHaveLength(1);
    } finally {
      rmSync(d, { recursive: true, force: true });
    }
  });
});
