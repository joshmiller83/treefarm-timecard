// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import sitemap from '@astrojs/sitemap';

/**
 * Lab and Open Graph template routes are tools, not pages: keep them out of the sitemap.
 * @param {string} page
 */
const isToolRoute = (page) => /\/(lab|og|404)(\/|$)/.test(new URL(page).pathname);

/**
 * Prints the Siri lines that are not yet confirmed against the app's dialog strings.
 * The brief asks the build to list them so nothing unconfirmed ships quietly.
 * @returns {import('astro').AstroIntegration}
 */
function siriLinesCheck() {
  return {
    name: 'treefarm:siri-lines',
    hooks: {
      'astro:build:done': async ({ logger }) => {
        try {
          const { unverifiedLines } = await import('./src/data/siri.ts');
          const lines = unverifiedLines();
          if (lines.length === 0) {
            logger.info('Every Siri line on the page is verified against the app.');
          } else {
            logger.warn(`${lines.length} Siri line(s) are not verified against the app's dialog strings yet:`);
            for (const l of lines) logger.warn(`  - [${l.key}] ${l.text}`);
          }
        } catch (err) {
          logger.warn(`Could not check the Siri lines: ${err instanceof Error ? err.message : String(err)}`);
        }
      },
    },
  };
}

/**
 * One render-blocking stylesheet for the page, and the in-app tab screens' CSS after it.
 *
 * Vite splits the page's CSS into a file per shared component group (the lab pages share the
 * components), eight files in all. After the build, the page's links are merged, in their
 * order, into one file (one request, and gzip sees all of it at once). The rules of the
 * Trees, Clock and Report tab chunks (the last three, all far below the fold) whose components
 * only ever draw inside a phone screen below the hero (found in the built HTML) move into a
 * second file that loads without blocking the first paint, last in the cascade as before;
 * their rules for anything on the page itself (the paper time card) stay in the first. Until
 * the second file has loaded, app screens stay blank (a rule appended to the first file, so a
 * dev server never hides them) and the motion core waits for it before it builds a scene that
 * measures one (the tf:tabs-css event). Without JS it is a plain stylesheet (noscript). Lab
 * pages keep Vite's files. scripts/budgets.ts measures both.
 * @returns {import('astro').AstroIntegration}
 */
function pageCss() {
  return {
    name: 'treefarm:page-css',
    hooks: {
      'astro:build:done': async ({ dir, logger }) => {
        const { readFile, writeFile } = await import('node:fs/promises');
        const { createHash } = await import('node:crypto');
        const { fileURLToPath } = await import('node:url');
        const { parse, ELEMENT_NODE } = await import('ultrahtml');
        const { transform } = await import('lightningcss');
        const root = fileURLToPath(dir);
        const page = `${root}index.html`;
        let html = await readFile(page, 'utf8');
        const links = [...html.matchAll(/<link rel="stylesheet" href="\/_astro\/([\w.-]+\.css)">/g)].map((m) => ({ tag: m[0], file: String(m[1]) }));
        if (links.length < 2) return;
        const tabChunk = (/** @type {string} */ f) => /^(TreesTab|ClockTab|ReportTab)\./.test(f);
        const read = (/** @type {string} */ f) => readFile(`${root}_astro/${f}`, 'utf8');
        const hash = (/** @type {string} */ s) => createHash('sha256').update(s).digest('base64url').slice(0, 8);

        // Scopes (astro-xxxxxxxx) whose every element sits in a phone screen outside the hero.
        /** @type {Map<string, boolean>} */
        const inPhone = new Map();
        /** @param {any} node @param {boolean} screen @param {boolean} hero */
        const walk = (node, screen, hero) => {
          if (node.type === ELEMENT_NODE) {
            const cls = String(node.attributes?.class ?? '').split(/\s+/);
            hero = hero || node.attributes?.id === 'hero';
            screen = screen || cls.includes('screen');
            for (const c of cls) if (c.startsWith('astro-')) inPhone.set(c, (inPhone.get(c) ?? true) && screen && !hero);
          }
          for (const child of node.children ?? []) walk(child, screen, hero);
        };
        walk(parse(html), false, false);
        const later = (/** @type {string} */ c) => inPhone.get(c) === true;
        /** @param {any} sel @returns {boolean} */
        const hasLater = (sel) =>
          sel.some((/** @type {any} */ c) => (c.type === 'class' && later(c.name)) || (Array.isArray(c.selectors) && c.selectors.some(hasLater)));
        const targets = { chrome: 111 << 16, edge: 111 << 16, firefox: 114 << 16, safari: (16 << 16) | (4 << 8) };
        /** Keep the style rules that `keep` says yes to (all other rules stay). */
        const filter = (/** @type {string} */ code, /** @type {(rule: any) => boolean} */ keep) =>
          transform({ filename: 'page.css', code: Buffer.from(code), minify: true, targets, visitor: { Rule: { style: (rule) => (keep(rule) ? undefined : []) } } }).code.toString();
        const isLater = (/** @type {any} */ rule) => rule.value.selectors.every(hasLater);

        const first = [];
        const second = [];
        for (const l of links) {
          const css = await read(l.file);
          if (!tabChunk(l.file)) {
            first.push(css);
            continue;
          }
          first.push(filter(css, (r) => !isLater(r)));
          second.push(filter(css, isLater).replace(/@(font-face|keyframes)[^{]*\{(?:[^{}]|\{[^{}]*\})*\}/g, ''));
        }
        const blank = 'html.js:not(.tabs-css) [data-app]{visibility:hidden}';
        let main = `${first.join('\n')}\n${blank}\n`;
        let tabs = second.join('\n');
        // Astro's scope classes (astro- and 8 characters, on most elements and in most selectors)
        // become _0, _1…: 2 KB gz less HTML and 1 KB less CSS. Nothing reads them by name.
        const ids = [...new Set((html + main + tabs).match(/\bastro-[a-z0-9]{8}\b/g) ?? [])];
        if (!/class="[^"]*(?<![\w-])_[0-9a-z]+(?![\w-])/.test(html)) {
          const short = new Map(ids.map((id, i) => [id, `_${i.toString(36)}`]));
          const swap = (/** @type {string} */ s) => s.replace(/\bastro-[a-z0-9]{8}\b/g, (m) => short.get(m) ?? m);
          html = swap(html);
          main = swap(main);
          tabs = swap(tabs);
        }
        const mainFile = `page.${hash(main)}.css`;
        await writeFile(`${root}_astro/${mainFile}`, main);
        // The merged file takes the place of the first link (the page's cascade order).
        links.forEach((l, i) => (html = html.replace(l.tag, i === 0 ? `<link rel="stylesheet" href="/_astro/${mainFile}">` : '')));
        if (tabs.trim()) {
          const tabsFile = `tabs.${hash(tabs)}.css`;
          await writeFile(`${root}_astro/${tabsFile}`, tabs);
          const href = `/_astro/${tabsFile}`;
          const onload = "this.media='all';this.onload=null;document.documentElement.classList.add('tabs-css');dispatchEvent(new Event('tf:tabs-css'))";
          html = html.replace(
            '</head>',
            `<link rel="preload" href="${href}" as="style"><link rel="stylesheet" href="${href}" media="print" onload="${onload}" data-later-css><noscript><link rel="stylesheet" href="${href}"></noscript></head>`,
          );
        }
        await writeFile(page, html);
        logger.info(`index.html: ${links.length} stylesheets merged into ${mainFile}; the tab screens' rules load after the first paint`);
      },
    },
  };
}

/**
 * @param {string} pkg
 * @param {string} file
 */
const fontsource = (pkg, file) => `./node_modules/@fontsource/${pkg}/files/${file}`;

export default defineConfig({
  site: 'https://treefarm.joshnliz.com',
  output: 'static',
  trailingSlash: 'ignore',
  devToolbar: { enabled: false },
  // Scoped styles by class (astro-xxxx) rather than data-astro-cid-xxxx attributes: the same
  // specificity, and shorter in both the HTML and the CSS (the page has ~6k elements).
  scopedStyleStrategy: 'class',
  build: {
    // 'auto' (the brief's "inlined where small"): small stylesheets inline, the page's main
    // CSS is a cached file. Inlining all of it put ~40 KB gz into every HTML response and
    // pushed the HTML past its 75 KB gz budget (and LCP up under load).
    inlineStylesheets: 'auto',
    format: 'directory',
  },
  integrations: [sitemap({ filter: (page) => !isToolRoute(page) }), siriLinesCheck(), pageCss()],
  fonts: [
    {
      provider: fontProviders.local(),
      name: 'Zilla Slab',
      cssVariable: '--font-zilla',
      fallbacks: ['Georgia', 'serif'],
      display: 'swap',
      options: {
        variants: [
          { src: [fontsource('zilla-slab', 'zilla-slab-latin-600-normal.woff2')], weight: 600, style: 'normal' },
          { src: [fontsource('zilla-slab', 'zilla-slab-latin-700-normal.woff2')], weight: 700, style: 'normal' },
        ],
      },
    },
    {
      provider: fontProviders.local(),
      name: 'Public Sans',
      cssVariable: '--font-public',
      fallbacks: ['Arial', 'sans-serif'],
      display: 'swap',
      options: {
        variants: [
          // 400 and 600 only (the brief's font budget, 120 KB): 500 renders as 400 and 700 as 600.
          { src: [fontsource('public-sans', 'public-sans-latin-400-normal.woff2')], weight: 400, style: 'normal' },
          { src: [fontsource('public-sans', 'public-sans-latin-600-normal.woff2')], weight: 600, style: 'normal' },
        ],
      },
    },
    {
      provider: fontProviders.local(),
      name: 'IBM Plex Mono',
      cssVariable: '--font-plex',
      fallbacks: ['Courier New', 'monospace'],
      display: 'swap',
      options: {
        variants: [
          { src: [fontsource('ibm-plex-mono', 'ibm-plex-mono-latin-500-normal.woff2')], weight: 500, style: 'normal' },
          { src: [fontsource('ibm-plex-mono', 'ibm-plex-mono-latin-600-normal.woff2')], weight: 600, style: 'normal' },
        ],
      },
    },
  ],
  vite: {
    build: {
      // The motion chunk (GSAP + plugins + core) is ~140 KB raw, ~53 KB gzipped.
      chunkSizeWarningLimit: 180,
      rollupOptions: {
        output: {
          manualChunks(id) {
            if (/src\/(data\/(ledger|siri)|scripts\/(odometer|wave|text)|components\/system\/lockscreen\/activity)\.ts$/.test(id)) return 'shared';
          },
        },
      },
    },
  },
});
