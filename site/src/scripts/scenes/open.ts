/**
 * SCENE: BUILT IN THE OPEN. The shift is over, so nothing here is scrubbed: the scrubbed
 * timeline only holds the DayClock at 4:31 PM with the ribbon complete ('End of shift').
 * Spec: jq '.sections[] | select(.id=="open") | .animation' docs/landing/brief.json
 *
 * Each part plays once, when it comes into view (not when the section's top does, so on a
 * phone nothing plays below the fold):
 *   icon      the green square settles, the gold ring draws (1.0 s, power2.inOut), the ticks
 *             pop clockwise (stagger .04), the fir hand rises 12px and turns -8° → 0
 *             (back.out(1.4), .6 s) so the clock reads as a tree, then one sheen sweeps it
 *   headline  SplitText lines mask-reveal (yPercent 100 → 0, stagger .08, .7 s, power3.out)
 *   copy      paragraphs, chips, buttons fade up 16px (stagger .05)
 *   rail      the line fills to "now" and the stops pop in order
 *   terminal  types the command once (1.2 s, steps) with the cursor following, then rests
 *             as a static block (no blinking loop)
 *   ribbon    the 'End of shift' tag fades out 1.5 s after the section arrives (desktop)
 *   phone     the stage phone fades out (.4 s) as the section rises into view (desktop); the
 *             core then hides the stage itself, since this chapter is stage: 'off'
 *
 * Static first: an element that is already in view when the scene builds (a reader who
 * jumped here) keeps its final state; only parts still below the fold get from-states.
 * Every from-state and timeline is made while building, so gsap.matchMedia reverts them.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';
import { handDrop, tickOrder, typeTimes } from '../../sections/open/open.ts';

/** Where each part starts playing, as a fraction of the viewport height from the top. */
const AT = { icon: 0.85, head: 0.88, copy: 0.92, rail: 0.85, term: 0.82, ribbon: 0.7, phone: 0.85 } as const;

registerScene(
  'open',
  (ctx) => {
    const { tl, day, gsap, ScrollTrigger, SplitText, section, isDesk, q, q1 } = ctx;

    // The shift is over: hold 4:31 PM with the ribbon complete.
    day.to(tl, MOMENTS.clockOut, 0, 0.01, MOMENTS.clockOut);
    day.complete(tl, 0, 0.01);

    const later: Array<GSAPTween | GSAPTimeline> = [];
    const cleanups: Array<() => void> = [];
    const below = (el: Element | null, at: number): el is Element => !!el && el.getBoundingClientRect().top > innerHeight * at;
    const once = (trigger: Element, at: number, play: () => void) =>
      ScrollTrigger.create({ trigger, start: `top ${Math.round(at * 100)}%`, end: 'max', once: true, onEnter: play });

    // ---- The icon assembles ----
    const icon = q1('[data-open-icon]');
    if (below(icon, AT.icon)) {
      const svg = icon.querySelector('svg')!;
      const size = svg.getBoundingClientRect().width || 192;
      const bg = svg.querySelector('[data-icon-bg]');
      const ring = svg.querySelector('[data-icon-ring]');
      const hand = svg.querySelector('[data-icon-hand]');
      const ticks = Array.from(svg.querySelectorAll<SVGElement>('[data-icon-tick]'));
      const order = tickOrder(ticks.map((t) => Number(t.dataset.hour)));
      ticks.sort((a, b) => order.indexOf(Number(a.dataset.hour)) - order.indexOf(Number(b.dataset.hour)));
      const shadow = icon.querySelector('[data-icon-shadow]');
      const sheen = icon.querySelector('[data-icon-sheen]');
      const text = q('[data-lockup-text]').filter((t) => getComputedStyle(t).display !== 'none');

      const a = gsap.timeline({ paused: true });
      a.fromTo(bg, { opacity: 0, scale: 0.9, svgOrigin: '512 520' }, { opacity: 1, scale: 1, duration: 0.55, ease: 'power3.out' }, 0)
        .fromTo(shadow, { opacity: 0 }, { opacity: 1, duration: 0.8, ease: 'power1.out' }, 0.05)
        // The ring has pathLength 1, so its offset runs 1 → 0: tween the attribute (CSS px would round).
        .fromTo(ring, { attr: { 'stroke-dashoffset': 1 } }, { attr: { 'stroke-dashoffset': 0 }, duration: 1, ease: 'power2.inOut' }, 0.15)
        .fromTo(ticks, { scale: 0, transformOrigin: '50% 50%' }, { scale: 1, duration: 0.32, ease: 'back.out(2.2)', stagger: 0.04 }, 0.3)
        .fromTo(hand, { opacity: 0 }, { opacity: 1, duration: 0.18, ease: 'none' }, 0.72)
        .fromTo(
          hand,
          { y: handDrop(size), rotation: -8, svgOrigin: '512 520' },
          { y: 0, rotation: 0, duration: 0.6, ease: 'back.out(1.4)' },
          0.72,
        )
        .fromTo(text, { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: 0.5, stagger: 0.07, ease: 'power2.out' }, 0.85)
        .fromTo(sheen, { opacity: 0, xPercent: -100 }, { keyframes: { opacity: [0, 1, 1, 0] }, xPercent: 100, duration: 0.85, ease: 'power1.inOut' }, 1.3)
        .set(sheen, { xPercent: 0 });
      once(icon, AT.icon, () => a.play());
    }

    // ---- The headline: lines rise out of their masks ----
    const head = q1<HTMLElement>(`#${section.id}-h`);
    if (below(head, AT.head) && document.fonts.status === 'loaded') {
      const split = SplitText.create(head, { type: 'lines', mask: 'lines', linesClass: 'open-line', aria: 'auto' });
      const h = gsap.timeline({ paused: true, onComplete: () => split.revert() });
      // 115, not 100: each mask leaves .14em below its line for descenders (see Open.astro).
      h.fromTo(split.lines, { yPercent: 115 }, { yPercent: 0, duration: 0.7, stagger: 0.08, ease: 'power3.out' });
      once(head, AT.head, () => h.play());
      cleanups.push(() => split.revert());
    }

    // ---- Copy, chips and buttons fade up 16px as they arrive ----
    const reveal = q('[data-reveal]').filter((el) => below(el, AT.copy));
    if (reveal.length) {
      gsap.set(reveal, { opacity: 0, y: 16 });
      ScrollTrigger.batch(reveal, {
        start: `top ${AT.copy * 100}%`,
        end: 'max',
        once: true,
        onEnter: (batch) => {
          later.push(gsap.to(batch, { opacity: 1, y: 0, duration: 0.6, stagger: 0.05, ease: 'power2.out', overwrite: 'auto' }));
        },
      });
    }

    // ---- Where it stands: the line fills to "now", the stops pop in order ----
    const rail = q1<HTMLElement>('[data-open-rail]');
    if (below(rail, AT.rail)) {
      const fill = parseFloat(rail.style.getPropertyValue('--fill')) || 0;
      const dots = Array.from(rail.querySelectorAll<HTMLElement>('[data-dot]'));
      const now = dots.findIndex((d) => d.closest<HTMLElement>('[data-step]')?.dataset.step === 'now');
      const lineDur = 0.6;
      const r = gsap.timeline({ paused: true, delay: 0.15 });
      r.fromTo(rail, { '--fill': 0 }, { '--fill': fill, duration: lineDur, ease: 'power2.inOut' }, 0.1);
      dots.forEach((dot, i) => {
        const at = Math.max(0, i <= now && now > 0 ? 0.1 + (lineDur * i) / now - 0.08 : 0.1 + lineDur + 0.1 * (i - now));
        r.fromTo(dot, { scale: 0 }, { scale: 1, duration: i === now ? 0.5 : 0.35, ease: i === now ? 'back.out(2.6)' : 'back.out(2)' }, at);
        // "You are here": one ring rolls out from the gold stop (motion-only, so the scene makes it).
        if (i === now) {
          const ripple = document.createElement('span');
          ripple.className = 'open-ripple';
          ripple.dataset.transient = '';
          dot.appendChild(ripple);
          cleanups.push(() => ripple.remove());
          r.fromTo(ripple, { opacity: 0.8, scale: 1 }, { opacity: 0, scale: 2.8, duration: 0.9, ease: 'power2.out', immediateRender: false }, at + 0.25);
        }
      });
      once(rail, AT.rail, () => r.play());
    }

    // ---- The terminal types the command once ----
    const term = q1<HTMLElement>('[data-open-term]');
    const cursor = term?.querySelector<HTMLElement>('[data-term-cursor]');
    const chars = term ? Array.from(term.querySelectorAll<HTMLElement>('[data-term-char]')) : [];
    if (below(term, AT.term) && cursor && chars.length) {
      const DURATION = 1.2;
      const last = chars[chars.length - 1]!;
      // The cursor rests after the last character; these offsets move it after character i
      // (or before the first, i = -1), measured when typing starts.
      const offset = (i: number) => {
        const end = last.getBoundingClientRect();
        const c = chars[Math.max(i, 0)]!.getBoundingClientRect();
        return { x: (i < 0 ? c.left : c.right) - end.right, y: c.top - end.top };
      };
      gsap.set(chars, { opacity: 0 });
      gsap.set(cursor, offset(-1));
      // Function values are measured when each keystroke first plays, so the layout is final.
      const to = (i: number) => ({ x: () => offset(i).x, y: () => offset(i).y, immediateRender: false });
      const times = typeTimes(chars.length, DURATION);
      const t = gsap.timeline({ paused: true, delay: 0.35 });
      t.set(cursor, to(-1), 0.001);
      chars.forEach((ch, i) => {
        const at = times[i]! + 0.02;
        t.set(ch, { opacity: 1, immediateRender: false }, at);
        t.set(cursor, to(i), at);
      });
      t.set(cursor, { x: 0, y: 0, immediateRender: false }, DURATION + 0.03);
      once(term, AT.term, () => t.play());
    }

    // ---- The stage phone is released (desktop): it fades as the light section rises into view,
    // before this section's copy can scroll under it. The core hides the stage itself once the
    // section is active; this fades the phone inside it a little earlier, and back on the way up.
    const phone = isDesk ? ctx.phone : null;
    if (phone) {
      const away = gsap.fromTo(phone, { opacity: 1 }, { opacity: 0, duration: 0.4, ease: 'power1.out', paused: true, immediateRender: false });
      ScrollTrigger.create({
        trigger: section,
        start: `top ${AT.phone * 100}%`,
        end: 'max',
        onEnter: () => away.timeScale(1).play(),
        onLeaveBack: () => away.timeScale(1.4).reverse(),
      });
      cleanups.push(() => gsap.set(phone, { clearProps: 'opacity' }));
    }

    // ---- The ribbon's 'End of shift' tag fades out after 1.5 s (desktop: on mobile it is the chapter button) ----
    const tag = isDesk ? document.querySelector<HTMLElement>('[data-header] .tag-ride') : null;
    if (tag) {
      const out = gsap.to(tag, { opacity: 0, duration: 0.5, ease: 'power1.out', paused: true });
      ScrollTrigger.create({
        trigger: section,
        start: `top ${AT.ribbon * 100}%`,
        end: 'max',
        onEnter: () => out.timeScale(1).delay(1.5).restart(true),
        onLeaveBack: () => out.timeScale(2).reverse(),
      });
      cleanups.push(() => gsap.set(tag, { clearProps: 'opacity' }));
    }

    return () => {
      later.forEach((a) => a.kill());
      cleanups.forEach((fn) => fn());
    };
  },
  { dayStart: MOMENTS.clockOut },
);
