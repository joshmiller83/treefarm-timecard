/**
 * Scene helpers. Every helper writes into a scrubbed timeline in PROGRESS UNITS (0–1),
 * renders correctly when scrubbed backwards, and animates only transform, opacity,
 * clip-path or stroke-dashoffset.
 *
 *   tap(tl, el, at)                       touch ring + press + 2px haptic shake (~.04)
 *   odometer(tl, el, from, to, at, dur)   roll odometer digits (see odometer.ts)
 *   karaoke(tl, el, at, dur)              words .25 → 1, scrubbed
 *   typeIn(tl, el, at, dur)               characters appear in order
 *   drawLine(tl, path, at, dur)           stroke-dashoffset full → 0
 *   crossfade(tl, a, b, at, dur)          screen change: a → .96/0, b from 1.04/0
 *   sheen(tl, at)                         specular sweep across the phone
 *   callout(tl, { line, label }, at)      leader line draws, then the label slides in 8px
 *   show(screens, stateId)                only this layer visible (call at build)
 *   ambient(tween)                        a loop that runs only while scrolling + 5 s, never while paused
 */
import type { gsap as GSAPObject } from 'gsap';
import type { SplitText as Split } from 'gsap/SplitText';
import { fmtCount } from '../data/ledger.ts';
import { setOdometer } from './odometer.ts';

type El = Element | null | undefined;

export interface Util {
  tap(tl: GSAPTimeline, el: El, at: number, opts?: { dur?: number; shake?: boolean; ring?: boolean }): void;
  odometer(tl: GSAPTimeline, el: El, from: number, to: number, at: number, dur?: number, format?: (v: number) => string): void;
  karaoke(tl: GSAPTimeline, el: El, at: number, dur: number): void;
  typeIn(tl: GSAPTimeline, el: El, at: number, dur: number): void;
  drawLine(tl: GSAPTimeline, path: El, at: number, dur: number): void;
  crossfade(tl: GSAPTimeline, a: El, b: El, at: number, dur?: number): void;
  sheen(tl: GSAPTimeline, at: number, dur?: number): void;
  callout(tl: GSAPTimeline, parts: { line?: El; label?: El; from?: 'left' | 'right' }, at: number, dur?: number): void;
  show(screens: El, stateId: string): void;
  ambient<T extends GSAPTween | GSAPTimeline>(anim: T): T;
  split(el: Element, type: 'words' | 'chars' | 'lines'): Element[];
}

export interface UtilDeps {
  gsap: typeof GSAPObject;
  SplitText: typeof Split;
  /** Returns the phone that taps shake and sheens sweep (stage phone on desktop). */
  phone: () => HTMLElement | null;
  /** Ambient loop registry shared by all scenes. */
  ambients: Set<GSAPTween | GSAPTimeline>;
}

const pathLength = (el: Element): number => {
  const attr = el.getAttribute('pathLength');
  if (attr) return Number(attr);
  const g = el as SVGGeometryElement;
  return typeof g.getTotalLength === 'function' ? g.getTotalLength() : 1;
};

export function createUtil({ gsap, SplitText, phone, ambients }: UtilDeps): Util {
  const splits = new WeakMap<Element, Record<string, Element[]>>();
  const odoStarted = new WeakSet<Element>();

  const split: Util['split'] = (el, type) => {
    let cache = splits.get(el);
    if (!cache) splits.set(el, (cache = {}));
    if (!cache[type]) {
      const s = SplitText.create(el, { type: type === 'chars' ? 'words,chars' : type, aria: 'none' });
      cache[type] = (type === 'chars' ? s.chars : type === 'words' ? s.words : s.lines) as Element[];
    }
    return cache[type]!;
  };

  const ringFor = (el: Element): HTMLElement => {
    let ring = el.querySelector<HTMLElement>(':scope > .tap-ring');
    if (!ring) {
      ring = document.createElement('span');
      ring.className = 'tap-ring';
      ring.setAttribute('aria-hidden', 'true');
      if (getComputedStyle(el).position === 'static') (el as HTMLElement).style.position = 'relative';
      el.appendChild(ring);
    }
    return ring;
  };

  const util: Util = {
    tap(tl, el, at, { dur = 0.04, shake = true, ring = true } = {}) {
      if (!el) return;
      if (ring) {
        const r = ringFor(el);
        tl.fromTo(r, { opacity: 0, scale: 0.6 }, { opacity: 0.35, duration: dur * 0.05, immediateRender: false }, at);
        tl.to(r, { opacity: 0, scale: 1.4, duration: dur * 0.95, ease: 'power2.out' }, at + dur * 0.05);
      }
      tl.to(el, { scale: 0.94, duration: dur * 0.35, ease: 'power2.out' }, at);
      tl.to(el, { scale: 1, duration: dur * 0.65, ease: 'back.out(1.8)' }, at + dur * 0.35);
      const p = phone();
      if (shake && p) tl.to(p, { keyframes: { x: [0, 2, -2, 2, -2, 0] }, duration: dur, ease: 'none' }, at);
    },

    odometer(tl, el, from, to, at, dur = 0.06, format = (v) => fmtCount(v)) {
      if (!el) return;
      const host = el as HTMLElement;
      const proxy = { v: from };
      const render = () => setOdometer(host, format(Math.round(proxy.v)));
      if (!odoStarted.has(el)) {
        odoStarted.add(el);
        setOdometer(host, format(Math.round(from)));
      }
      tl.fromTo(proxy, { v: from }, { v: to, duration: dur, ease: 'none', immediateRender: false, onUpdate: render }, at);
    },

    karaoke(tl, el, at, dur) {
      if (!el) return;
      const words = split(el, 'words');
      const each = dur / Math.max(words.length, 1);
      tl.fromTo(words, { opacity: 0.25 }, { opacity: 1, duration: each, stagger: each, ease: 'none' }, at);
    },

    typeIn(tl, el, at, dur) {
      if (!el) return;
      const chars = split(el, 'chars');
      const each = dur / Math.max(chars.length, 1);
      tl.fromTo(chars, { opacity: 0 }, { opacity: 1, duration: Math.min(each, 0.002), stagger: each, ease: 'none' }, at);
    },

    drawLine(tl, path, at, dur) {
      if (!path) return;
      const len = pathLength(path);
      gsap.set(path, { strokeDasharray: len });
      tl.fromTo(path, { strokeDashoffset: len }, { strokeDashoffset: 0, duration: dur, ease: 'none' }, at);
    },

    crossfade(tl, a, b, at, dur = 0.06) {
      if (a) tl.to(a, { opacity: 0, scale: 0.96, duration: dur, ease: 'power2.inOut' }, at);
      if (b) tl.fromTo(b, { opacity: 0, scale: 1.04 }, { opacity: 1, scale: 1, duration: dur, ease: 'power2.out', immediateRender: false }, at);
    },

    sheen(tl, at, dur = 0.05) {
      const s = phone()?.querySelector('[data-sheen]');
      if (!s) return;
      tl.fromTo(s, { opacity: 0, xPercent: -70 }, { opacity: 1, xPercent: 0, duration: dur / 2, ease: 'none', immediateRender: false }, at);
      tl.to(s, { opacity: 0, xPercent: 70, duration: dur / 2, ease: 'none' }, at + dur / 2);
    },

    callout(tl, { line, label, from = 'left' }, at, dur = 0.05) {
      if (line) util.drawLine(tl, line, at, dur * 0.4);
      if (label)
        tl.fromTo(label, { opacity: 0, x: from === 'left' ? -8 : 8 }, { opacity: 1, x: 0, duration: dur * 0.6, ease: 'power2.out' }, at + dur * 0.4);
    },

    show(screens, stateId) {
      if (!screens) return;
      for (const layer of Array.from(screens.querySelectorAll<HTMLElement>(':scope > .layer'))) {
        gsap.set(layer, { opacity: layer.dataset.state === stateId ? 1 : 0 });
      }
    },

    ambient(anim) {
      ambients.add(anim);
      if (document.documentElement.classList.contains('paused')) anim.pause();
      return anim;
    },

    split,
  };
  return util;
}
