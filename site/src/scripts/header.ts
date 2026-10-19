/**
 * First-load header behaviour (no GSAP): the mobile chapter disclosure, the light/dark
 * header switch, the current chapter, and the Pause motion toggle.
 * DayClock (motion only) also writes the ribbon and tag; this keeps them right without it.
 * It reads the chapters from the sections' own attributes (SectionShell writes
 * data-ribbon-tag), so the first-load bundle never pulls in the chapter list or the ledger.
 */

export const PAUSE_KEY = 'tf-pause';
export const PAUSE_EVENT = 'tf:pause';

export function isPaused(): boolean {
  return document.documentElement.classList.contains('paused');
}

export function initHeader(): void {
  const root = document.documentElement;
  const header = document.querySelector<HTMLElement>('[data-header]');
  const nav = header?.querySelector<HTMLElement>('nav.shift');
  const toggle = nav?.querySelector<HTMLButtonElement>('.shift-toggle');
  const list = nav?.querySelector<HTMLElement>('.shift-list');
  const pause = header?.querySelector<HTMLButtonElement>('[data-pause-toggle]');
  if (!header || !nav || !toggle || !list) return;

  // ---- Mobile disclosure ----
  const setOpen = (open: boolean, focusToggle = false) => {
    toggle.setAttribute('aria-expanded', String(open));
    nav.classList.toggle('is-open', open);
    if (!open && focusToggle) toggle.focus();
  };
  toggle.addEventListener('click', () => setOpen(toggle.getAttribute('aria-expanded') !== 'true'));
  list.addEventListener('click', (e) => {
    if ((e.target as Element).closest('a')) setOpen(false);
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && nav.classList.contains('is-open')) setOpen(false, true);
  });
  document.addEventListener('click', (e) => {
    if (nav.classList.contains('is-open') && !nav.contains(e.target as Node)) setOpen(false);
  });
  // Keyboard focus leaving the panel closes it, so it never sits over the page unattended.
  nav.addEventListener('focusout', (e) => {
    const next = e.relatedTarget as Node | null;
    if (nav.classList.contains('is-open') && next && !nav.contains(next)) setOpen(false);
  });

  // ---- Pause motion (WCAG 2.2.2) ----
  if (pause) {
    const sync = () => pause.setAttribute('aria-pressed', String(isPaused()));
    sync();
    pause.addEventListener('click', () => {
      const paused = !isPaused();
      root.classList.toggle('paused', paused);
      try {
        localStorage.setItem(PAUSE_KEY, paused ? '1' : '0');
      } catch {
        /* storage can be blocked; the toggle still works for this visit */
      }
      sync();
      window.dispatchEvent(new CustomEvent(PAUSE_EVENT, { detail: { paused } }));
    });
  }

  // ---- Chapter links and deep links on the static page ----
  // Without motion, far sections skip rendering (content-visibility: auto, 1100px stand-ins),
  // so a native jump lands on a guess of where the target will be. Render everything first
  // (html.cv-all, kept for the rest of the visit), then scroll once layout is real.
  const jump = (id: string, push: boolean): boolean => {
    if (root.classList.contains('motion')) return false;
    const target = document.getElementById(id);
    if (!target?.matches('section.sec')) return false;
    root.classList.add('cv-all');
    const land = () => target.scrollIntoView({ block: 'start', behavior: 'auto' });
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        if (push && location.hash !== `#${id}`) history.pushState(null, '', `#${id}`);
        land();
        // Keyboard and screen-reader users continue from the chapter, as with a native jump.
        if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
        target.focus({ preventScroll: true });
        // Fonts or late layout can still move things a little: land again after it settles.
        requestAnimationFrame(() => requestAnimationFrame(land));
      }),
    );
    return true;
  };
  document.addEventListener('click', (e) => {
    if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const a = (e.target as Element).closest<HTMLAnchorElement>('a[href^="#"]');
    const id = a?.getAttribute('href')!.slice(1);
    if (id && jump(id, true)) e.preventDefault();
  });
  addEventListener('hashchange', () => jump(location.hash.slice(1), false));
  addEventListener('popstate', () => jump(location.hash.slice(1), false));
  if (location.hash.length > 1) {
    const initial = location.hash.slice(1);
    jump(initial, false);
    addEventListener('load', () => jump(initial, false), { once: true });
  }

  // ---- Which section is under the header ----
  const sections = Array.from(document.querySelectorAll<HTMLElement>('main section[data-ribbon-tag]'));
  const links = new Map(
    Array.from(list.querySelectorAll<HTMLAnchorElement>('a[data-chapter-link]')).map((a) => [a.dataset.chapterLink!, a]),
  );
  const tags = Array.from(nav.querySelectorAll<HTMLElement>('[data-shift-tag]'));
  let current: HTMLElement | null = null;
  // Two 1px lines, each watched by an IntersectionObserver (no layout reads while the page
  // scrolls: DayClock writes text every frame, so a getBoundingClientRect here forced a full
  // layout of the page each time):
  //  - the band under the header's bottom edge: which section the header sits over (its theme);
  //  - the chapter line: which chapter is current. Without motion it lies a few px below the
  //    scroll padding, where a chapter link or a deep link lands its chapter (at the header's
  //    edge it named the chapter above, one behind); with motion it is the 55% line where the
  //    motion core hands the day to the next chapter, so the chip and aria-current agree.
  const inBand = new Set<Element>();
  const onLine = new Set<Element>();
  let line = '';

  const update = () => {
    const under = sections.find((s) => inBand.has(s)) ?? null;
    const theme = under?.dataset.theme === 'light' ? 'light' : 'dark';
    if (header.dataset.theme !== theme) header.dataset.theme = theme;
    const found = sections.find((s) => onLine.has(s)) ?? null;
    if (!found || found === current) return;
    current = found;
    const idx = sections.indexOf(found);
    sections.forEach((s, i) => {
      const a = links.get(s.id);
      if (!a) return;
      a.classList.toggle('reached', i <= idx);
      if (i === idx) a.setAttribute('aria-current', 'location');
      else a.removeAttribute('aria-current');
    });
    // Without motion, the tag names the chapter; with motion DayClock writes the live time.
    if (!root.classList.contains('motion')) {
      const tag = found.dataset.ribbonTag ?? '';
      for (const t of tags) if (t.textContent !== tag) t.textContent = tag;
      nav.style.setProperty('--p', String(idx / Math.max(1, sections.length - 1)));
    }
  };

  let raf = 0;
  const schedule = () => {
    if (!raf) raf = requestAnimationFrame(() => ((raf = 0), update()));
  };
  let band: IntersectionObserver | null = null;
  let chapterLine: IntersectionObserver | null = null;
  /** An observer of the 1px line `y` px from the top of the viewport. */
  const watchLine = (y: number, into: Set<Element>) => {
    into.clear();
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (e.isIntersecting) into.add(e.target);
          else into.delete(e.target);
        }
        schedule();
      },
      { rootMargin: `-${y}px 0px -${Math.max(0, innerHeight - y - 1)}px 0px` },
    );
    sections.forEach((s) => io.observe(s));
    return io;
  };
  const watchBand = () => {
    // Style reads only, never a layout one (this runs while the page first loads): the
    // header's own height in the flow (its band hangs below it, over the page) from the
    // tokens, and the scroll padding a jump lands at.
    const cs = getComputedStyle(root);
    const top = Math.round((parseFloat(cs.getPropertyValue('--header-h')) || 56) + (parseFloat(cs.getPropertyValue('--ribbon-h')) || 3)) + 1;
    const motion = root.classList.contains('motion');
    const at = motion ? Math.round(innerHeight * 0.55) : Math.round((parseFloat(cs.scrollPaddingTop) || top) + 8);
    const key = `${top}|${at}|${innerHeight}`;
    if (key === line) return;
    line = key;
    band?.disconnect();
    chapterLine?.disconnect();
    band = watchLine(top, inBand);
    chapterLine = watchLine(Math.min(at, innerHeight - 2), onLine);
  };
  watchBand();
  addEventListener('resize', () => (watchBand(), schedule()), { passive: true });
  new MutationObserver(schedule).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['data-theme'] });
  // Motion can come off after load (the 4 s gate, a failed motion bundle): move the chapter line.
  new MutationObserver(() => watchBand()).observe(root, { attributes: true, attributeFilter: ['class'] });
  update();
}
