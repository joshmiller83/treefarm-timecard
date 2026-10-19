/**
 * Size budgets (the brief's performance budget) for the built page, gzipped:
 *
 *   node scripts/budgets.ts            (after npm run build)
 *
 *   HTML             dist/index.html                                   ≤ 75 KB
 *   first-load JS    the page's module scripts and their static imports ≤ 6 KB
 *   motion JS        the motion core plus every scene chunk it loads   ≤ 80 KB  (reported)
 *   CSS              the page's stylesheets and inline <style>         ≤ 35 KB  (reported)
 *
 * HTML and first-load JS fail the run (exit 1) when over. Motion JS and CSS are printed with
 * their budget and flagged when over, without failing, until they are brought under it
 * (README: Budgets).
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

const dist = resolve(fileURLToPath(new URL('../dist', import.meta.url)));
const astro = join(dist, '_astro');
const gz = (buf: Buffer | string) => gzipSync(buf, { level: 9 }).length;
const kb = (n: number) => `${(n / 1024).toFixed(1)} KB`;
const read = (p: string) => readFileSync(p);

const html = read(join(dist, 'index.html')).toString();

/** A JS file and its static imports (from "./x.js" / import "./x.js"), once each. */
function graph(file: string, seen = new Set<string>()): Set<string> {
  if (seen.has(file)) return seen;
  seen.add(file);
  const src = read(join(astro, file)).toString();
  for (const m of src.matchAll(/(?:from|import)\s*["']\.\/([\w.-]+\.js)["']/g)) graph(m[1]!, seen);
  return seen;
}

const entry = [...html.matchAll(/<script[^>]+src="\/_astro\/([\w.-]+\.js)"/g)].map((m) => m[1]!);
const firstLoad = new Set<string>();
for (const f of entry) graph(f, firstLoad);

const files = readdirSync(astro);
const motionCore = files.find((f) => /^motion\.[\w-]+\.js$/.test(f));
const motion = new Set<string>();
if (motionCore) {
  graph(motionCore, motion);
  // Scene chunks are dynamic imports of the core: count them and their own imports.
  const core = read(join(astro, motionCore)).toString();
  for (const m of core.matchAll(/import\(\s*[`"']\.\/([\w.-]+\.js)[`"']\s*\)/g)) graph(m[1]!, motion);
}
for (const f of firstLoad) motion.delete(f);

const cssFiles = [...html.matchAll(/<link rel="stylesheet" href="\/_astro\/([\w.-]+\.css)"/g)].map((m) => m[1]!);
const inlineCss = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]!).join('');

const sum = (set: Iterable<string>) => [...set].reduce((n, f) => n + gz(read(join(astro, f))), 0);
const rows = [
  { name: 'HTML (index.html)', size: gz(html), budget: 75 * 1024, hard: true },
  { name: `First-load JS (${firstLoad.size} files)`, size: sum(firstLoad), budget: 6 * 1024, hard: true },
  { name: `Motion JS (${motion.size} files)`, size: sum(motion), budget: 80 * 1024, hard: false },
  { name: `CSS (${cssFiles.length} files + inline)`, size: sum(cssFiles) + gz(inlineCss), budget: 35 * 1024, hard: false },
];

let failed = false;
for (const r of rows) {
  const over = r.size > r.budget;
  const mark = over ? (r.hard ? 'FAIL' : 'over') : 'ok';
  console.log(`${mark.padEnd(4)}  ${r.name.padEnd(30)} ${kb(r.size).padStart(9)} gz  (budget ${kb(r.budget)})`);
  if (over && r.hard) failed = true;
}
if (failed) {
  console.error('A hard size budget is exceeded.');
  process.exit(1);
}
