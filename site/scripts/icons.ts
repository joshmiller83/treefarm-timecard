/**
 * Regenerates the favicons from the app's own icon drawing.
 *   npm run icons
 * - public/favicon.svg        from src/data/icon.ts (a port of tools/make_icon.swift)
 * - public/apple-touch-icon.png (180 px) and public/favicon.ico (32 px), drawn by
 *   tools/make_icon.swift into a temp folder and resized with sips (macOS only).
 */
import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { appIconSVG } from '../src/data/icon.ts';

const site = resolve(fileURLToPath(new URL('..', import.meta.url)));
const repo = resolve(site, '..');
const pub = join(site, 'public');

writeFileSync(join(pub, 'favicon.svg'), `${appIconSVG()}\n`);
console.log('wrote public/favicon.svg');

const tmp = mkdtempSync(join(tmpdir(), 'tf-icon-'));
try {
  execFileSync('swift', [join(repo, 'tools/make_icon.swift'), tmp], { stdio: 'inherit' });
  const src = join(tmp, 'AppIcon-light.png');
  execFileSync('sips', ['-z', '180', '180', src, '--out', join(pub, 'apple-touch-icon.png')], { stdio: 'ignore' });
  const png32 = join(tmp, 'favicon-32.png');
  execFileSync('sips', ['-z', '32', '32', src, '--out', png32], { stdio: 'ignore' });
  execFileSync('sips', ['-s', 'format', 'ico', png32, '--out', join(pub, 'favicon.ico')], { stdio: 'ignore' });
  console.log('wrote public/apple-touch-icon.png and public/favicon.ico');
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
