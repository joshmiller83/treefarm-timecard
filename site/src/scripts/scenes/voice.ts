/**
 * VOICE scene · "Say it. Keep cutting." Spec:
 *   jq '.sections[] | select(.id=="voice") | .animation' docs/landing/brief.json
 *
 * Timelines
 *   ctx.tl (the track, 'top top' → 'bottom bottom')   the pocket slides up [0, .06], down [.94, 1]
 *   one per exchange (desktop: each <article>, 'top 65%' → 'bottom 35%'; mobile: each card,
 *   'top 80%' → 'top 35%'; the lunch article is one timeline on desktop, two cards on mobile)
 *
 * Rules that keep scrubbing (and jumping) exact
 *   - Each element property has exactly one writer: an exchange animates only its own screen
 *     layer and its own words. Layers stack bottom to top and are opaque, so the next
 *     exchange's layer simply covers the last one (its snippet and glow fade out with it).
 *   - The DayClock minute is not tweened: every timeline's onUpdate recomputes it from all of
 *     their progress values with voiceMinute() (model.ts, unit-tested).
 *   - From-states are set once at build (gsap.set, reverted with the matchMedia context);
 *     every tween is a fromTo with immediateRender off, so invalidation never re-records them.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS, treesAt } from '../../data/ledger.ts';
import { place, voiceMinute, type PartId, type Source } from '../../sections/voice/model.ts';

type Win = readonly [number, number];
type Els = Element[];

registerScene(
  'voice',
  (ctx) => {
    const { tl, gsap, isDesk, util, section, day, screens, SplitText } = ctx;
    if (!screens) return;
    const cleanups: Array<() => void> = [];

    const all = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string): T[] =>
      root ? Array.from(root.querySelectorAll<T>(sel)) : [];
    const one = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string): T | null =>
      root ? root.querySelector<T>(sel) : null;

    // ---- The clock: one function of every timeline's progress ----
    const track = day.track(tl);
    const tls: Partial<Record<Source, GSAPTimeline>> = { main: tl };
    const progress: Partial<Record<Source, number>> = {};
    const sync = () => {
      for (const k of Object.keys(tls) as Source[]) progress[k] = tls[k]!.progress();
      track.min = voiceMinute(progress, isDesk);
    };
    tl.eventCallback('onUpdate', sync);

    const mini = (src: Source, trigger: Element | null, start: string, end: string) => {
      const m = gsap.timeline({
        defaults: { ease: 'none' },
        onUpdate: sync,
        scrollTrigger: trigger ? { trigger, start, end, scrub: 0.6 } : undefined,
      });
      m.to({}, { duration: 1 }, 0); // normalized: progress = position
      tls[src] = m;
      return m;
    };
    const article = (id: string) => one(section, `[data-x="${id}"]`);
    const partEl = (id: PartId) => one(section, `[data-part="${id}"]`);
    if (isDesk) {
      for (const id of ['misheard', 'next', 'lunch', 'status'] as const) mini(id, article(id), 'top 65%', 'bottom 35%');
    } else {
      for (const id of ['misheard', 'next', 'lunchA', 'lunchB', 'status'] as const) mini(id, partEl(id), 'top 80%', 'top 35%');
    }

    /** A part's local window [a, b] on its timeline. */
    const at = (part: PartId, u: number) => place(part, u, isDesk).p;
    const tlOf = (part: PartId) => tls[place(part, 0, isDesk).src]!;
    const T = (part: PartId) => {
      const m = tlOf(part);
      const pos = (u: number) => at(part, u);
      return {
        m,
        pos,
        /** fromTo over a local window, never rendered at build. */
        ft(el: Element | Els | null, from: gsap.TweenVars, to: gsap.TweenVars, w: Win, ease = 'none') {
          if (!el || (Array.isArray(el) && !el.length)) return;
          m.fromTo(el, from, { ...to, duration: Math.max(pos(w[1]) - pos(w[0]), 1e-4), ease, immediateRender: false }, pos(w[0]));
        },
        /** A discrete flip (attributes): begin before u, end from u on. */
        flip(el: Element | null, from: gsap.TweenVars, to: gsap.TweenVars, u: number) {
          if (!el) return;
          m.fromTo(el, from, { ...to, duration: 1e-4, immediateRender: false }, pos(u));
        },
      };
    };

    // ---- Screen layers ----
    const layerEls = (id: string) => {
      const el = one(screens, `[data-screen="${id}"]`);
      const lock = one(el, '[data-lock]');
      const la = one(el, '[data-la]');
      return {
        el,
        chrome: all(lock, ':scope > [data-date], :scope > [data-clock], :scope > [data-padlock]'),
        sbTime: one(lock, '[data-statusbar] [data-clock]'),
        snippet: one(el, '[data-snippet]'),
        sWords: all(el, '[data-snippet] [data-word]'),
        chips: all(el, '[data-choice]'),
        glow: one(el, '[data-glow]'),
        ring: one(el, '[data-glow-ring]'),
        la,
        laBreak: one(la, '[data-la-break]'),
        faceClock: one(la, '[data-pill-face="clock"]'),
        faceBreak: one(la, '[data-pill-face="break"]'),
        pillBreakText: one(la, '[data-pill-text="break"]'),
        worked: one(la, '[data-worked-line]'),
        trees: one(la, '[data-trees]'),
        rows: all(la, '[data-row]'),
        breakBtn: one(la, '[data-break-btn]'),
        backBtn: one(la, '[data-back-btn]'),
      };
    };
    type L = ReturnType<typeof layerEls>;
    const L1 = layerEls('lock-0718-misheard');
    const L2 = layerEls('lock-0719-next');
    const L3 = layerEls('lock-1201-lunch');
    const L4 = layerEls('lock-1231-back');
    const L5 = layerEls('lock-1401-status');

    // Layers: the first shows from the start; each later one fades in over the last.
    gsap.set(L1.el, { opacity: 1 });
    gsap.set([L2.el, L3.el, L4.el, L5.el], { opacity: 0 });

    // Siri's from-state on every layer with a snippet: the big clock shows, the card is away.
    const siriLayers = [L1, L2, L4, L5];
    for (const L of siriLayers) {
      gsap.set(L.chrome, { opacity: 1 });
      gsap.set(L.sbTime, { opacity: 0 });
      gsap.set(L.snippet, { opacity: 0, yPercent: -14, scale: 0.97, transformOrigin: '50% 0%' });
      gsap.set(L.sWords, { opacity: 0 });
    }
    for (const L of [L1, L2, L3, L4, L5]) {
      gsap.set(L.glow, { opacity: 0 });
      gsap.set(L.ring, { rotation: 0 });
    }

    // ---- Page words ----
    const words = (root: Element | null, sel: string) => all(root, `${sel} .w`);
    const glyphBars = (root: Element | null) => all(root, '.x-wave [data-bar]');

    /** Listening, thinking, then Siri's card drops in and its words stream. */
    const listen = (t: ReturnType<typeof T>, L: L, w: Win) => t.ft(L.glow, { opacity: 0 }, { opacity: 1 }, w, 'power1.out');
    const think = (t: ReturnType<typeof T>, L: L, w: Win) => t.ft(L.ring, { rotation: 0 }, { rotation: 60 }, w);
    const answer = (t: ReturnType<typeof T>, L: L, drop: Win, type: Win) => {
      t.ft(L.snippet, { opacity: 0, yPercent: -14, scale: 0.97 }, { opacity: 1, yPercent: 0, scale: 1 }, drop, 'power2.out');
      t.ft(L.chrome, { opacity: 1 }, { opacity: 0 }, [drop[0], drop[0] + (drop[1] - drop[0]) * 0.6]);
      t.ft(L.sbTime, { opacity: 0 }, { opacity: 1 }, drop);
      if (L.sWords.length) {
        const each = (t.pos(type[1]) - t.pos(type[0])) / L.sWords.length;
        t.m.fromTo(L.sWords, { opacity: 0 }, { opacity: 1, duration: each, stagger: each, immediateRender: false }, t.pos(type[0]));
      }
      // The ring keeps turning slowly while Siri speaks.
      t.ft(L.ring, { rotation: 60 }, { rotation: 110 }, [drop[0], type[1]]);
    };
    /**
     * Your line: karaoke, words .25 → 1. The dim state is a class (.x-near) that is on only
     * while the part is on screen, so text at rest far from the reader is never left dim (axe
     * checks the whole page). Once a word's tween has run, its inline opacity rules; when the
     * timeline rewinds to its start, the inline styles are cleared again.
     */
    const rewound = new Map<GSAPTimeline, Element[]>();
    const karaoke = (t: ReturnType<typeof T>, els: Els, w: Win) => {
      if (!els.length) return;
      const each = (t.pos(w[1]) - t.pos(w[0])) / els.length;
      t.m.fromTo(els, { opacity: 0.25 }, { opacity: 1, duration: each, stagger: each, immediateRender: false }, t.pos(w[0]));
      rewound.set(t.m, [...(rewound.get(t.m) ?? []), ...els]);
    };
    const near = (el: Element | null) =>
      el && ctx.trigger({ trigger: el, start: 'top bottom', end: 'bottom top', toggleClass: { targets: el, className: 'x-near' } });
    /** Siri's reply on the page: word by word, and the gold bars speak. */
    const reveal = (t: ReturnType<typeof T>, root: Element | null, w: Win) => {
      const turn = one(root, '.x-siri');
      if (turn) {
        gsap.set(turn, { opacity: 0 });
        t.ft(turn, { opacity: 0 }, { opacity: 1 }, [w[0], w[0] + (w[1] - w[0]) * 0.15]);
      }
      const els = words(root, '.x-reply');
      if (els.length) {
        gsap.set(els, { opacity: 0 });
        const each = (t.pos(w[1]) - t.pos(w[0])) / els.length;
        t.m.fromTo(els, { opacity: 0 }, { opacity: 1, duration: each, stagger: each, immediateRender: false }, t.pos(w[0]));
      }
      const bars = glyphBars(root);
      if (bars.length) {
        gsap.set(bars, { scaleY: 0.4 });
        t.m.fromTo(
          bars,
          { scaleY: 0.4 },
          {
            keyframes: { scaleY: [0.4, 1, 0.55, 0.95, 0.5, 1] },
            duration: t.pos(w[1]) - t.pos(w[0]),
            stagger: { each: (t.pos(w[1]) - t.pos(w[0])) * 0.04, from: 'center' },
            immediateRender: false,
          },
          t.pos(w[0]),
        );
      }
    };
    const fadeUp = (t: ReturnType<typeof T>, el: Element | null, w: Win) => {
      if (!el) return;
      gsap.set(el, { opacity: 0, y: 8 });
      t.ft(el, { opacity: 0, y: 8 }, { opacity: 1, y: 0 }, w, 'power2.out');
    };

    // ---- 7:18 · the misheard check ----
    {
      const t = T('misheard');
      const p = partEl('misheard');
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [0.02, 0.26]);
      listen(t, L1, [0, 0.28]);
      think(t, L1, [0.28, 0.36]);
      // Siri heard 'forty': a rust wave draws under 'fourteen', left to right.
      const squiggle = one(p, '[data-squiggle]');
      if (squiggle) {
        gsap.set(squiggle, { clipPath: 'inset(0% 100% 0% 0%)' });
        t.ft(squiggle, { clipPath: 'inset(0% 100% 0% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)' }, [0.42, 0.5]);
      }
      answer(t, L1, [0.36, 0.44], [0.38, 0.5]);
      reveal(t, p, [0.36, 0.54]);
      // Then the card offers Yes and No, and you say no. (A little earlier than the brief's
      // .6/.7/.8: the next exchange's layer starts covering this one at about .79.)
      gsap.set(L1.chips, { opacity: 0, y: 6 });
      t.ft(L1.chips, { opacity: 0, y: 6 }, { opacity: 1, y: 0, stagger: 0.004 }, [0.5, 0.55], 'power2.out');
      const answerTurn = one(p, '[data-turn="answer"]');
      if (answerTurn) {
        gsap.set(answerTurn, { opacity: 0 });
        t.ft(answerTurn, { opacity: 0 }, { opacity: 1 }, [0.55, 0.57]);
      }
      karaoke(t, words(p, '[data-turn="answer"] .x-said'), [0.56, 0.62]);
      const no = one(L1.el, '[data-choice="No"]');
      const ring = one(no, '[data-choice-ring]');
      gsap.set(ring, { opacity: 0 });
      util.tap(t.m, no, t.pos(0.62), { dur: t.pos(0.66) - t.pos(0.62) });
      t.ft(ring, { opacity: 0 }, { opacity: 1 }, [0.63, 0.66]);
      // Nothing changes: the Live Activity is never touched here.
      fadeUp(t, one(p, '[data-note]'), [0.68, 0.74]);
    }

    // ---- 7:19 · next row ----
    {
      const t = T('next');
      const p = partEl('next');
      t.ft(L2.el, { opacity: 0 }, { opacity: 1 }, [0.06, 0.1]);
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [0.08, 0.28]);
      listen(t, L2, [0.1, 0.28]);
      think(t, L2, [0.3, 0.4]);
      answer(t, L2, [0.4, 0.48], [0.42, 0.6]);
      reveal(t, p, [0.4, 0.66]);
      util.odometer(t.m, L2.trees, treesAt(MOMENTS.misheard), treesAt(MOMENTS.firstRow), t.pos(0.44), t.pos(0.52) - t.pos(0.44));
    }

    // ---- 12:01 · take lunch ----
    // (Timed early in its window: on mobile the card covers the Live Activity after ~.6.)
    {
      const t = T('lunchA');
      const p = partEl('lunchA');
      t.ft(L3.el, { opacity: 0 }, { opacity: 1 }, [0.04, 0.1]);
      // The morning passes with the clock: trees roll up with it.
      util.odometer(t.m, L3.trees, treesAt(MOMENTS.firstRow), treesAt(MOMENTS.lunch), t.pos(0.06), t.pos(0.24) - t.pos(0.06));
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [0.22, 0.44]);
      listen(t, L3, [0.22, 0.42]);
      think(t, L3, [0.42, 0.48]);
      // From-state: still on the clock.
      gsap.set(L3.la, { attr: { 'data-state': 'working' } });
      gsap.set(L3.laBreak, { opacity: 0 });
      gsap.set(L3.faceClock, { opacity: 1 });
      gsap.set(L3.faceBreak, { opacity: 0 });
      gsap.set(L3.worked, { opacity: 0 });
      gsap.set(L3.rows, { scaleX: 1, transformOrigin: '100% 50%' });
      gsap.set(L3.breakBtn, { opacity: 1 });
      gsap.set(L3.backBtn, { clipPath: 'inset(0% 100% 0% 0%)' });
      // Lunch starts on the word: gold tint, 'On lunch', the timer rolls to 0:00:00.
      t.flip(L3.la, { attr: { 'data-state': 'working' } }, { attr: { 'data-state': 'lunch' } }, 0.48);
      t.ft(L3.laBreak, { opacity: 0 }, { opacity: 1 }, [0.48, 0.56]);
      t.ft(L3.faceClock, { opacity: 1 }, { opacity: 0 }, [0.48, 0.52]);
      t.ft(L3.faceBreak, { opacity: 0 }, { opacity: 1 }, [0.48, 0.54]);
      t.ft(L3.worked, { opacity: 0 }, { opacity: 1 }, [0.52, 0.6]);
      if (L3.rows.length) {
        const span = t.pos(0.6) - t.pos(0.5);
        const each = span * 0.12;
        t.m.fromTo(
          [...L3.rows].reverse(),
          { scaleX: 1 },
          { scaleX: 0, duration: span - each * (L3.rows.length - 1), stagger: each, ease: 'power2.in', immediateRender: false },
          t.pos(0.5),
        );
      }
      t.ft(L3.breakBtn, { opacity: 1 }, { opacity: 0 }, [0.5, 0.55]);
      t.ft(L3.backBtn, { clipPath: 'inset(0% 100% 0% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)' }, [0.56, 0.68], 'power2.out');
      // No reply: the gold lock screen is the answer. Siri lets go.
      t.ft(L3.glow, { opacity: 1 }, { opacity: 0 }, [0.62, 0.76]);
    }

    // ---- 12:31 · back to work ----
    {
      const t = T('lunchB');
      const p = partEl('lunchB');
      // From-state: the lunch look (this layer's own static state is back at work).
      const lunchPill = L4.pillBreakText?.textContent ?? null;
      if (L4.pillBreakText) L4.pillBreakText.textContent = 'On lunch';
      gsap.set(L4.la, { attr: { 'data-state': 'lunch' } });
      gsap.set(L4.laBreak, { opacity: 1 });
      gsap.set(L4.faceClock, { opacity: 0 });
      gsap.set(L4.faceBreak, { opacity: 1 });
      gsap.set(L4.worked, { opacity: 1 });
      gsap.set(L4.rows, { scaleX: 0, transformOrigin: '0% 50%' });
      gsap.set(L4.breakBtn, { opacity: 0 });
      gsap.set(L4.backBtn, { clipPath: 'inset(0% 0% 0% 0%)', opacity: 1 });
      t.ft(L4.el, { opacity: 0 }, { opacity: 1 }, [0, 0.04]);
      // Desktop: thirty minutes of lunch fill the dotted line between the halves.
      const fill = one(article('lunch'), '[data-lunch-fill]');
      gsap.set(fill, { scaleY: 0 });
      t.ft(fill, { scaleY: 0 }, { scaleY: 1 }, [0, 0.18]);
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [0.18, 0.34]);
      listen(t, L4, [0.18, 0.32]);
      think(t, L4, [0.32, 0.36]);
      util.tap(t.m, L4.backBtn, t.pos(0.35), { dur: t.pos(0.39) - t.pos(0.35) });
      t.flip(L4.la, { attr: { 'data-state': 'lunch' } }, { attr: { 'data-state': 'working' } }, 0.38);
      t.ft(L4.laBreak, { opacity: 1 }, { opacity: 0 }, [0.38, 0.46]);
      t.ft(L4.faceBreak, { opacity: 1 }, { opacity: 0 }, [0.38, 0.42]);
      t.ft(L4.faceClock, { opacity: 0 }, { opacity: 1 }, [0.38, 0.44]);
      t.ft(L4.worked, { opacity: 1 }, { opacity: 0 }, [0.38, 0.43]);
      t.ft(L4.backBtn, { opacity: 1 }, { opacity: 0 }, [0.4, 0.45]);
      if (L4.rows.length) {
        const span = t.pos(0.52) - t.pos(0.42);
        const each = span * 0.12;
        t.m.fromTo(
          L4.rows,
          { scaleX: 0 },
          { scaleX: 1, duration: span - each * (L4.rows.length - 1), stagger: each, ease: 'power2.out', immediateRender: false },
          t.pos(0.42),
        );
      }
      t.ft(L4.breakBtn, { opacity: 0 }, { opacity: 1 }, [0.46, 0.52]);
      answer(t, L4, [0.42, 0.5], [0.44, 0.6]);
      reveal(t, p, [0.42, 0.7]);
      // Restore the static text if the scene is ever reverted.
      cleanups.push(() => {
        if (L4.pillBreakText && lunchPill !== null) L4.pillBreakText.textContent = lunchPill;
      });
    }

    // ---- 2:01 · how many trees ----
    {
      const t = T('status');
      const p = partEl('status');
      t.ft(L5.el, { opacity: 0 }, { opacity: 1 }, [0.04, 0.08]);
      util.odometer(t.m, L5.trees, treesAt(MOMENTS.back), treesAt(MOMENTS.status), t.pos(0.06), t.pos(0.18) - t.pos(0.06));
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [0.14, 0.3]);
      listen(t, L5, [0.12, 0.3]);
      think(t, L5, [0.3, 0.4]);
      answer(t, L5, [0.4, 0.48], [0.42, 0.6]);
      reveal(t, p, [0.4, 0.68]);
    }

    for (const [m, els] of rewound) m.eventCallback('onReverseComplete', () => gsap.set(els, { clearProps: 'opacity' }));
    for (const id of ['misheard', 'next', 'lunchA', 'lunchB', 'status'] as const) near(partEl(id));

    // ---- The pocket: up over the phone at the start, away at the end ----
    const pocket = isDesk ? one(section, '.x-stage-pocket [data-pocket]') : one(section, '.x-device [data-pocket]');
    if (pocket) {
      gsap.set(pocket, { yPercent: 100 });
      tl.fromTo(pocket, { yPercent: 100 }, { yPercent: 0, duration: 0.06, ease: 'power2.out', immediateRender: false }, 0);
      tl.fromTo(pocket, { yPercent: 0 }, { yPercent: 110, duration: 0.06, ease: 'power2.in', immediateRender: false }, 0.94);
    }

    // ---- The headline: lines rise out of a mask, once ----
    const h2 = one(section, '#voice-h');
    if (h2) {
      const split = SplitText.create(h2, { type: 'lines', mask: 'lines', aria: 'auto' });
      const rest = all(section, '.beat-head .eyebrow, .beat-head .beat-intro');
      gsap.set(split.lines, { yPercent: 100 });
      gsap.set(rest, { opacity: 0, y: 12 });
      const intro = gsap.timeline({ paused: true });
      intro.to(split.lines, { yPercent: 0, stagger: 0.08, duration: 0.7, ease: 'power3.out' }, 0);
      intro.to(rest, { opacity: 1, y: 0, duration: 0.6, stagger: 0.08, ease: 'power2.out' }, 0.15);
      ctx.trigger({ trigger: h2, start: 'top 75%', once: true, onEnter: () => intro.play() });
    }

    sync();
    return () => cleanups.forEach((f) => f());
  },
  { dayStart: MOMENTS.clockIn },
);
