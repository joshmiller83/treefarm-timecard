/**
 * THE STAGE (desktop with motion only): one fixed phone carries the whole day.
 * claim(section) moves that section's [data-screens] into the stage phone's .screen with a
 * .35 s crossfade and a sheen; the previous section's screens go back home. The section's
 * own figure is visually hidden (html.stage-on) and stays readable by screen readers.
 * The stage phone's rect is written to --stage-x/-y/-w/-h on :root for section extras.
 */
import type { gsap as GSAPObject } from 'gsap';

export interface Stage {
  el: HTMLElement;
  phone: HTMLElement;
  slot: HTMLElement;
  claim(section: HTMLElement): void;
  release(section: HTMLElement): void;
  /** The section whose screens are in the stage. */
  owner(): HTMLElement | null;
  destroy(): void;
}

export function createStage(gsap: typeof GSAPObject, doc: Document = document): Stage | null {
  const el = doc.querySelector<HTMLElement>('[data-stage]');
  const phone = el?.querySelector<HTMLElement>('[data-phone]');
  const slot = phone?.querySelector<HTMLElement>('.screen');
  if (!el || !phone || !slot) return null;

  const root = doc.documentElement;
  const homes = new Map<HTMLElement, { parent: Node; next: Node | null }>();
  let current: HTMLElement | null = null;
  let owner: HTMLElement | null = null;

  const writeRect = () => {
    const r = phone.getBoundingClientRect();
    root.style.setProperty('--stage-x', `${r.left.toFixed(1)}px`);
    root.style.setProperty('--stage-y', `${r.top.toFixed(1)}px`);
    root.style.setProperty('--stage-w', `${r.width.toFixed(1)}px`);
    root.style.setProperty('--stage-h', `${r.height.toFixed(1)}px`);
  };

  const goHome = (screens: HTMLElement) => {
    const home = homes.get(screens);
    if (!home || screens.parentNode === home.parent) return;
    gsap.set(screens, { clearProps: 'opacity' });
    home.parent.insertBefore(screens, home.next && home.next.parentNode === home.parent ? home.next : null);
  };

  const sheen = () => {
    const s = phone.querySelector('[data-sheen]');
    if (s) gsap.fromTo(s, { opacity: 0, xPercent: -70 }, { keyframes: { opacity: [0, 1, 0] }, xPercent: 70, duration: 0.55, ease: 'none' });
  };

  root.classList.add('stage-on');
  writeRect();
  const ro = new ResizeObserver(writeRect);
  ro.observe(phone);
  addEventListener('resize', writeRect, { passive: true });

  const stage: Stage = {
    el,
    phone,
    slot,
    claim(section) {
      const screens = section.querySelector<HTMLElement>('[data-screens]');
      if (!screens) return;
      owner = section;
      if (screens === current) return;
      if (!homes.has(screens)) homes.set(screens, { parent: screens.parentNode!, next: screens.nextSibling });
      const prev = current;
      current = screens;
      slot.appendChild(screens);
      gsap.fromTo(screens, { opacity: 0 }, { opacity: 1, duration: 0.35, ease: 'power1.out', overwrite: 'auto' });
      sheen();
      gsap.delayedCall(0.36, () => {
        for (const s of homes.keys()) if (s !== current) goHome(s);
        if (prev && prev !== current) goHome(prev);
      });
    },
    release(section) {
      const screens = section.querySelector<HTMLElement>('[data-screens]');
      if (screens && screens === current) {
        current = null;
        owner = null;
        goHome(screens);
      }
    },
    owner: () => owner,
    destroy() {
      ro.disconnect();
      removeEventListener('resize', writeRect);
      for (const s of homes.keys()) goHome(s);
      current = null;
      owner = null;
      root.classList.remove('stage-on');
    },
  };
  return stage;
}
