/**
 * Real simulator captures: public/screens/<state-id>.{avif,webp} (1179 × 2556, ≤ 200 KB)
 * replace the HTML recreation of that state. Screen.astro calls findCapture() at build time
 * with the directory from Astro's publicDir, so the build finds them from any working directory.
 *
 * Encode a simulator PNG before dropping it in (captures are pictures of flat UI, so a
 * WebP at quality 80 is sharp and small; AVIF is smaller still):
 *   cwebp -q 80 -m 6 -sharp_yuv capture.png -o public/screens/<state-id>.webp
 *   avifenc -q 60 -s 4 capture.png public/screens/<state-id>.avif
 * capture.test.ts fails the unit tests when a file in public/screens breaks these rules.
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

/** Formats in order of preference. PNG is not allowed: a 1179 × 2556 PNG is 1–3 MB. */
export const CAPTURE_EXTS = ['avif', 'webp'] as const;

/** A real capture is 1179 × 2556 (iPhone 15/16 Pro at 3x: 393 × 852 pt). */
export const CAPTURE_SIZE = { width: 1179, height: 2556 } as const;

/** The most one capture may weigh (the brief's image budget is tight). */
export const CAPTURE_MAX_BYTES = 200 * 1024;

/** State ids are kebab-case words and digits (lock-1414-activity), so they are safe file names. */
export const isStateId = (id: string) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id);

/** public/screens inside Astro's publicDir (a file: URL or a path). */
export function captureDir(publicDir: URL | string): string {
  return join(typeof publicDir === 'string' ? publicDir : fileURLToPath(publicDir), 'screens');
}

/** The public URL of the capture for `stateId` in `dir` (see captureDir), or null when there is none. */
export function findCapture(stateId: string, dir: string): string | null {
  if (!isStateId(stateId)) return null;
  for (const ext of CAPTURE_EXTS) {
    if (existsSync(join(dir, `${stateId}.${ext}`))) return `/screens/${stateId}.${ext}`;
  }
  return null;
}

export interface ImageSize {
  type: 'webp' | 'avif';
  width: number;
  height: number;
}

const ascii = (b: Uint8Array, at: number, n = 4) => String.fromCharCode(...b.subarray(at, at + n));

/** Pixel size of a WebP (VP8, VP8L or VP8X) or AVIF file from its header, or null. */
export function imageSize(b: Uint8Array): ImageSize | null {
  const v = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const u24le = (at: number) => v.getUint16(at, true) | (v.getUint8(at + 2) << 16);
  if (b.length >= 30 && ascii(b, 0) === 'RIFF' && ascii(b, 8) === 'WEBP') {
    const chunk = ascii(b, 12);
    if (chunk === 'VP8X') return { type: 'webp', width: u24le(24) + 1, height: u24le(27) + 1 };
    if (chunk === 'VP8L' && v.getUint8(20) === 0x2f) {
      const bits = v.getUint32(21, true);
      return { type: 'webp', width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
    }
    if (chunk === 'VP8 ' && v.getUint8(23) === 0x9d && v.getUint8(24) === 0x01 && v.getUint8(25) === 0x2a) {
      return { type: 'webp', width: v.getUint16(26, true) & 0x3fff, height: v.getUint16(28, true) & 0x3fff };
    }
    return null;
  }
  if (b.length >= 12 && ascii(b, 4) === 'ftyp' && ['avif', 'avis'].includes(ascii(b, 8))) {
    // Image spatial extents ('ispe'): the largest is the whole image (grid tiles are smaller).
    let width = 0;
    let height = 0;
    for (let i = 4; i + 16 <= b.length; i += 1) {
      if (b[i] === 0x69 && ascii(b, i) === 'ispe') {
        width = Math.max(width, v.getUint32(i + 8));
        height = Math.max(height, v.getUint32(i + 12));
      }
    }
    return width && height ? { type: 'avif', width, height } : null;
  }
  return null;
}

/** What is wrong with one file meant for public/screens (empty when it is fine). */
export function captureProblems(file: string, bytes: Uint8Array): string[] {
  const dot = file.lastIndexOf('.');
  const id = file.slice(0, dot);
  const ext = file.slice(dot + 1);
  const problems: string[] = [];
  if (!(CAPTURE_EXTS as readonly string[]).includes(ext)) {
    problems.push(`${file}: use .avif or .webp, not .${ext} (encode it: see src/components/phone/capture.ts)`);
    return problems;
  }
  if (!isStateId(id)) problems.push(`${file}: name it <state-id>.${ext} in kebab-case (see CONTRACT.md's registry)`);
  if (bytes.length > CAPTURE_MAX_BYTES) {
    problems.push(`${file}: ${Math.round(bytes.length / 1024)} KB is over ${CAPTURE_MAX_BYTES / 1024} KB; encode it smaller`);
  }
  const size = imageSize(bytes);
  if (!size || size.type !== ext) problems.push(`${file}: not a readable ${ext.toUpperCase()} file`);
  else if (size.width !== CAPTURE_SIZE.width || size.height !== CAPTURE_SIZE.height) {
    problems.push(`${file}: ${size.width} × ${size.height}, expected ${CAPTURE_SIZE.width} × ${CAPTURE_SIZE.height}`);
  }
  return problems;
}

/** Every problem with the files in `dir` (dotfiles such as .gitkeep are ignored). */
export function auditCaptures(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => !f.startsWith('.'))
    .sort()
    .flatMap((f) => captureProblems(f, new Uint8Array(readFileSync(join(dir, f)))));
}
