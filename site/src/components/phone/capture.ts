/**
 * Real simulator captures: public/screens/<state-id>.{avif,webp,png} (1179 × 2556) replace
 * the HTML recreation of that state. Screen.astro calls findCapture() at build time.
 */
import { existsSync } from 'node:fs';
import { join } from 'node:path';

/** Formats in order of preference. */
export const CAPTURE_EXTS = ['avif', 'webp', 'png'] as const;

/** A real capture is 1179 × 2556 (iPhone 15/16 Pro at 3x: 393 × 852 pt). */
export const CAPTURE_SIZE = { width: 1179, height: 2556 } as const;

/** State ids are kebab-case words and digits (lock-1414-activity), so they are safe file names. */
export const isStateId = (id: string) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(id);

/**
 * The public URL of the capture for `stateId`, or null when there is none.
 * `dir` defaults to public/screens under the working directory (Astro builds from site/).
 */
export function findCapture(stateId: string, dir = join(process.cwd(), 'public', 'screens')): string | null {
  if (!isStateId(stateId)) return null;
  for (const ext of CAPTURE_EXTS) {
    if (existsSync(join(dir, `${stateId}.${ext}`))) return `/screens/${stateId}.${ext}`;
  }
  return null;
}
