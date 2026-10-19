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

  // ---- Which section is under the header ----
  const sections = Array.from(document.querySelectorAll<HTMLElement>('main section[data-ribbon-tag]'));
  const links = new Map(
    Array.from(list.querySelectorAll<HTMLAnchorElement>('a[data-chapter-link]')).map((a) => [a.dataset.chapterLink!, a]),
  );
  const tags = Array.from(nav.querySelectorAll<HTMLElement>('[data-shift-tag]'));
  let current: HTMLElement | null = null;

  const update = () => {
    const line = header.getBoundingClientRect().bottom + 1;
    let found: HTMLElement | null = null;
    for (const s of sections) {
      const r = s.getBoundingClientRect();
      if (r.top <= line && r.bottom > line) {
        found = s;
        break;
      }
    }
    const theme = found?.dataset.theme === 'light' ? 'light' : 'dark';
    if (header.dataset.theme !== theme) header.dataset.theme = theme;
    if (found === current) return;
    current = found;
    const idx = found ? sections.indexOf(found) : -1;
    sections.forEach((s, i) => {
      const a = links.get(s.id);
      if (!a) return;
      a.classList.toggle('reached', i <= idx);
      if (i === idx) a.setAttribute('aria-current', 'location');
      else a.removeAttribute('aria-current');
    });
    // Without motion, the tag names the chapter; with motion DayClock writes the live time.
    if (!root.classList.contains('motion')) {
      const tag = sections[Math.max(0, idx)]?.dataset.ribbonTag ?? '';
      for (const t of tags) t.textContent = tag;
      nav.style.setProperty('--p', String(Math.max(0, idx) / Math.max(1, sections.length - 1)));
    }
  };

  let raf = 0;
  const schedule = () => {
    if (!raf) raf = requestAnimationFrame(() => ((raf = 0), update()));
  };
  const io = new IntersectionObserver(schedule, { threshold: [0, 0.01, 0.5, 0.99, 1] });
  sections.forEach((s) => io.observe(s));
  addEventListener('scroll', schedule, { passive: true });
  addEventListener('resize', schedule, { passive: true });
  new MutationObserver(schedule).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['data-theme'] });
  update();
}
