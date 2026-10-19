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
 * order, into one file (one request, and gzip sees all of it at once). The Trees, Clock and
 * Report tabs' CSS (TreesTab, ClockTab and ReportTab chunks: their screens are all far below
 * the fold) moves into a second file that loads without blocking the first paint; it is last
 * in the cascade, as before. Until it has loaded, app screens stay blank (visibility: hidden,
 * appended to the first file, so a dev server never hides them) and the motion core waits for
 * it before it builds a scene that measures one (the tf:tabs-css event). Without JS it is a
 * plain stylesheet (noscript). Lab pages keep Vite's files. scripts/budgets.ts measures both.
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
        const root = fileURLToPath(dir);
        const page = `${root}index.html`;
        let html = await readFile(page, 'utf8');
        const links = [...html.matchAll(/<link rel="stylesheet" href="\/_astro\/([\w.-]+\.css)">/g)].map((m) => ({ tag: m[0], file: String(m[1]) }));
        if (links.length < 2) return;
        const later = (/** @type {string} */ f) => /^(TreesTab|ClockTab|ReportTab)\./.test(f);
        const read = (/** @type {string} */ f) => readFile(`${root}_astro/${f}`, 'utf8');
        const hash = (/** @type {string} */ s) => createHash('sha256').update(s).digest('base64url').slice(0, 8);
        const first = links.filter((l) => !later(l.file));
        const rest = links.filter((l) => later(l.file));
        if (!first.length || later(links[0]?.file ?? '')) return;
        const blank = 'html.js:not(.tabs-css) [data-app]{visibility:hidden}';
        const main = (await Promise.all(first.map((l) => read(l.file)))).join('\n') + `\n${blank}\n`;
        const mainFile = `page.${hash(main)}.css`;
        await writeFile(`${root}_astro/${mainFile}`, main);
        // The merged file takes the place of the first link (the page's cascade order).
        links.forEach((l, i) => (html = html.replace(l.tag, i === 0 ? `<link rel="stylesheet" href="/_astro/${mainFile}">` : '')));
        if (rest.length) {
          const tabs = (await Promise.all(rest.map((l) => read(l.file)))).join('\n');
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
        logger.info(`index.html: ${first.length} stylesheets merged into ${mainFile}; ${rest.length} tab screens' stylesheets load after the first paint`);
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
