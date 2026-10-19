// @ts-check
import { defineConfig, fontProviders } from 'astro/config';
import sitemap from '@astrojs/sitemap';

/**
 * Lab and Open Graph template routes are tools, not pages: keep them out of the sitemap.
 * @param {string} page
 */
const isToolRoute = (page) => /\/(lab|og)(\/|$)/.test(new URL(page).pathname);

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
 * @param {string} pkg
 * @param {string} file
 */
const fontsource = (pkg, file) => `./node_modules/@fontsource/${pkg}/files/${file}`;

export default defineConfig({
  site: 'https://treefarm.joshnliz.com',
  output: 'static',
  trailingSlash: 'ignore',
  devToolbar: { enabled: false },
  build: {
    // The page's CSS is ~9 KB gzipped: inlining it saves a render-blocking round trip (LCP).
    inlineStylesheets: 'always',
    format: 'directory',
  },
  integrations: [sitemap({ filter: (page) => !isToolRoute(page) }), siriLinesCheck()],
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
      // The motion chunk (GSAP + plugins + core) is ~160 KB raw, ~60 KB gzipped (budget: 80 KB gz).
      chunkSizeWarningLimit: 180,
    },
  },
});
