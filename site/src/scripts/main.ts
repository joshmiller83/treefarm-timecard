/**
 * First-load page script (kept tiny: the 6 KB first-load budget). The header behaviour
 * loads with the Header component. Here we only decide whether to fetch the motion core:
 * only under html.motion, and only after first paint, when the browser is idle.
 */
const root = document.documentElement;

function fail(err: unknown) {
  console.warn('[motion] falling back to the static page', err);
  root.classList.remove('motion', 'intro-wait', 'stage-on');
  root.classList.add('motion-failed');
}

if (root.classList.contains('motion')) {
  const load = () =>
    import('./motion.ts')
      .then((m) => m.boot())
      .catch(fail);
  if ('requestIdleCallback' in window) requestIdleCallback(load, { timeout: 1200 });
  else setTimeout(load, 200);
}
