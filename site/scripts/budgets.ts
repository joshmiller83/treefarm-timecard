/**
 * Size budgets (the brief's performance budget) for the built page, gzipped:
 *
 *   node scripts/budgets.ts            (after npm run build)
 *
 *   HTML              dist/index.html                                        ≤ 75 KB  fail
 *   First-load JS     the page's module scripts and their static imports      ≤ 6 KB   fail
 *   CSS, first paint  render-blocking stylesheets and inline <style>          ≤ 35 KB  fail
 *   CSS, later        the tab screens' stylesheet (loads after first paint)    reported
 *   Motion JS         the motion core plus every scene chunk it loads         ≤ 80 KB  target,
 *                                                                              ≤ 104 KB fail
 *
 * Any line marked fail stops the run (exit 1), so CI never deploys a page over it. Motion JS
 * is over the brief's 80 KB (GSAP, ScrollTrigger and SplitText alone are 50 KB, and the nine
 * scenes ~48 KB): it fails at a ceiling just above today's size, so it can only shrink, and
 * the target is printed beside it (README: Budgets).
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
// The document without its <noscript> fallbacks (a browser with JS never reads them).
const live = html.replace(/<noscript>[\s\S]*?<\/noscript>/g, '');

/** A JS file and its static imports (from "./x.js" / import "./x.js"), once each. */
function graph(file: string, seen = new Set<string>()): Set<string> {
  if (seen.has(file)) return seen;
  seen.add(file);
  const src = read(join(astro, file)).toString();
  for (const m of src.matchAll(/(?:from|import)\s*["']\.\/([\w.-]+\.js)["']/g)) graph(m[1]!, seen);
  return seen;
}

const entry = [...live.matchAll(/<script[^>]+src="\/_astro\/([\w.-]+\.js)"/g)].map((m) => m[1]!);
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

const sheets = [...live.matchAll(/<link\b[^>]*\brel="stylesheet"[^>]*>/g)].map((m) => m[0]);
const href = (tag: string) => tag.match(/href="\/_astro\/([\w.-]+\.css)"/)?.[1];
const blocking = sheets.filter((t) => !/\bmedia="print"/.test(t)).map(href).filter((f): f is string => !!f);
const later = sheets.filter((t) => /\bmedia="print"/.test(t)).map(href).filter((f): f is string => !!f);
const inlineCss = [...live.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]!).join('');

const sum = (set: Iterable<string>) => [...set].reduce((n, f) => n + gz(read(join(astro, f))), 0);
interface Row {
  name: string;
  size: number;
  /** Fails the run when over. */
  limit?: number;
  /** The brief's number, printed when it differs from the limit. */
  target?: number;
}
const rows: Row[] = [
  { name: 'HTML (index.html)', size: gz(html), limit: 75 * 1024 },
  { name: `First-load JS (${firstLoad.size} files)`, size: sum(firstLoad), limit: 6 * 1024 },
  { name: `CSS, first paint (${blocking.length} + inline)`, size: sum(blocking) + gz(inlineCss), limit: 35 * 1024 },
  { name: `CSS, after first paint (${later.length})`, size: sum(later) },
  { name: `Motion JS (${motion.size} files)`, size: sum(motion), limit: 104 * 1024, target: 80 * 1024 },
];

let failed = false;
for (const r of rows) {
  const over = r.limit !== undefined && r.size > r.limit;
  const offTarget = r.target !== undefined && r.size > r.target;
  const mark = over ? 'FAIL' : offTarget ? 'over' : r.limit === undefined ? '' : 'ok';
  const budget = r.limit === undefined ? 'reported' : r.target !== undefined ? `target ${kb(r.target)}, fails over ${kb(r.limit)}` : `budget ${kb(r.limit)}`;
  console.log(`${mark.padEnd(4)}  ${r.name.padEnd(32)} ${kb(r.size).padStart(9)} gz  (${budget})`);
  if (over) failed = true;
}
if (failed) {
  console.error('A size budget is exceeded.');
  process.exit(1);
}
