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
 *     layer and its own words. Layers stack bottom to top and are opaque.
 *   - Siri lets go inside the outgoing exchange's own timeline, before the next layer starts
 *     to come in: the card lifts away, the glow fades and the big clock returns. The handover
 *     is then clock face to clock face, so it reads as one screen. On desktop the timelines
 *     overlap, so the handoff is measured from the articles at build; mobile cards never
 *     overlap, so Siri lets go near each card's end.
 *   - The DayClock minute is not tweened: every timeline's onUpdate recomputes it from all of
 *     their progress values with voiceMinute() (clock.ts, unit-tested). The Live Activity's
 *     lunch flips sit on the same BEATS, so the card and the clock change together.
 *   - On mobile each card slides over the Live Activity at about .45, so everything the card
 *     shows changes before then (BEATS.mob and the mobile windows below).
 *   - From-states are set once at build (gsap.set, reverted with the matchMedia context);
 *     every tween is a fromTo with immediateRender off, so invalidation never re-records them.
 */
import { registerScene } from '../scene.ts';
import { FIELD_TREES, MOMENTS, fieldShapedAt, fmtCount, rowsAt, treesAt } from '../../data/ledger.ts';
import { setOdometer } from '../odometer.ts';
import { BEATS, place, voiceMinute, type PartId, type Source } from '../../sections/voice/clock.ts';

type Win = readonly [number, number];
type Els = Element[];

registerScene(
  'voice',
  (ctx) => {
    const { tl, gsap, isDesk, util, section, day, screens, SplitText } = ctx;
    if (!screens) return;
    const cleanups: Array<() => void> = [];
    /** Desktop value or mobile value. */
    const dm = <T>(desk: T, mob: T): T => (isDesk ? desk : mob);
    const B = isDesk ? BEATS.desk : BEATS.mob;

    const all = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string): T[] =>
      root ? Array.from(root.querySelectorAll<T>(sel)) : [];
    const one = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string): T | null =>
      root ? root.querySelector<T>(sel) : null;

    // ---- The clock: one function of every timeline's progress ----
    const track = day.track(tl);
    const tls: Partial<Record<Source, GSAPTimeline>> = { main: tl };
    const progress: Partial<Record<Source, number>> = {};
    /** Writes the ledger's numbers for the clock's minute (set once the layers are found). */
    let ledgerAt: (min: number) => void = () => {};
    const sync = () => {
      for (const k of Object.keys(tls) as Source[]) progress[k] = tls[k]!.progress();
      track.min = voiceMinute(progress, isDesk);
      ledgerAt(track.min);
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

    /**
     * Desktop: the progress of `cur`'s timeline at which `next`'s starts ('top 65%' →
     * 'bottom 35%' on both, so the next article starts while this one is still running).
     * Mobile cards end before the next one starts.
     */
    const handoff = (cur: string, next: string) => {
      if (!isDesk) return 0.96;
      const a = article(cur)?.getBoundingClientRect();
      const b = article(next)?.getBoundingClientRect();
      if (!a || !b || !a.height) return 0.72;
      return Math.min(0.96, Math.max(0.3, (b.top - a.top) / (a.height + 0.3 * window.innerHeight)));
    };

    /** A part's local progress u on its timeline. */
    const at = (part: PartId, u: number) => place(part, u, isDesk).p;
    const tlOf = (part: PartId) => tls[place(part, 0, isDesk).src]!;
    const T = (part: PartId) => {
      const m = tlOf(part);
      const pos = (u: number) => at(part, u);
      /** fromTo over a window of the timeline's own progress, never rendered at build. */
      const ftp = (el: Element | Els | null, from: gsap.TweenVars, to: gsap.TweenVars, w: Win, ease = 'none') => {
        if (!el || (Array.isArray(el) && !el.length)) return;
        m.fromTo(el, from, { ...to, duration: Math.max(w[1] - w[0], 1e-4), ease, immediateRender: false }, w[0]);
      };
      return {
        m,
        pos,
        ftp,
        /** fromTo over a window of the part's local progress. */
        ft(el: Element | Els | null, from: gsap.TweenVars, to: gsap.TweenVars, w: Win, ease = 'none') {
          ftp(el, from, to, [pos(w[0]), pos(w[1])], ease);
        },
        /** A discrete flip (attributes): begin before u, end from u on. */
        flip(el: Element | null, from: gsap.TweenVars, to: gsap.TweenVars, u: number) {
          if (!el) return;
          m.fromTo(el, from, { ...to, duration: 1e-4, immediateRender: false }, pos(u));
        },
      };
    };
    type TT = ReturnType<typeof T>;

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
        strip: one(la, '[data-strip-track]'),
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

    // ---- Numbers from the ledger at the clock's minute ----
    // While the day time-lapses on a layer (the morning on the 12:01 card, the early
    // afternoon on the 2:01 one), its trees, row buttons and field bar are read from the
    // ledger at the DayClock's minute on every update: whole rows of ten, never a count in
    // between, and the buttons step to the rows Alex is on at that minute.
    const live = [
      { L: L3, from: MOMENTS.firstRow, to: MOMENTS.lunch },
      { L: L5, from: MOMENTS.back, to: MOMENTS.status },
    ].map((x) => {
      const bar = one<HTMLElement>(x.L.la, '[data-fieldbar]');
      return {
        ...x,
        bar,
        rows: x.L.rows.map((el) => ({ el, row: Number(el.dataset.row), text: el.textContent ?? '' })),
        trees: x.L.trees?.dataset.odoText ?? null,
        barTransform: bar?.style.transform ?? '',
      };
    });
    ledgerAt = (min: number) => {
      for (const x of live) {
        const m = Math.min(x.to, Math.max(x.from, min));
        if (x.L.trees) setOdometer(x.L.trees, fmtCount(treesAt(m)));
        const shift = rowsAt(m)[0] - rowsAt(x.to)[0];
        for (const r of x.rows) {
          const row = String(r.row + shift);
          if (r.el.dataset.row !== row) {
            r.el.dataset.row = row;
            r.el.textContent = `Row ${row}`;
          }
        }
        if (x.bar) x.bar.style.transform = `scaleX(${(fieldShapedAt(m) / FIELD_TREES).toFixed(4)})`;
      }
    };
    cleanups.push(() => {
      for (const x of live) {
        if (x.L.trees && x.trees) setOdometer(x.L.trees, x.trees);
        for (const r of x.rows) {
          r.el.dataset.row = String(r.row);
          r.el.textContent = r.text;
        }
        if (x.bar) x.bar.style.transform = x.barTransform;
      }
    });

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

    /** The next layer comes in over the last (a window of its timeline's own progress). */
    const enter = (t: TT, L: L, w: Win) => t.ftp(L.el, { opacity: 0 }, { opacity: 1 }, w);
    /** Listening, thinking, then Siri's card drops in and its words stream. */
    const listen = (t: TT, L: L, w: Win) => t.ft(L.glow, { opacity: 0 }, { opacity: 1 }, w, 'power1.out');
    const think = (t: TT, L: L, w: Win) => t.ft(L.ring, { rotation: 0 }, { rotation: 60 }, w);
    const answer = (t: TT, L: L, drop: Win, type: Win) => {
      t.ft(L.snippet, { opacity: 0, yPercent: -14, scale: 0.97 }, { opacity: 1, yPercent: 0, scale: 1 }, drop, 'power2.out');
      t.ft(L.chrome, { opacity: 1 }, { opacity: 0 }, [drop[0], drop[0] + (drop[1] - drop[0]) * 0.45]);
      t.ft(L.sbTime, { opacity: 0 }, { opacity: 1 }, drop);
      if (L.sWords.length) {
        const each = (t.pos(type[1]) - t.pos(type[0])) / L.sWords.length;
        t.m.fromTo(L.sWords, { opacity: 0 }, { opacity: 1, duration: each, stagger: each, immediateRender: false }, t.pos(type[0]));
      }
      // The ring keeps turning slowly while Siri speaks.
      t.ft(L.ring, { rotation: 60 }, { rotation: 110 }, [drop[0], type[1]]);
      return t.pos(type[1]);
    };
    /**
     * Siri lets go: the card lifts away, the glow fades, the big clock comes back and the status
     * bar time leaves. `end` is where the next layer starts to come in (timeline progress);
     * `after` is where this layer's last Siri tween ends.
     */
    const letGo = (t: TT, L: L, end: number, after: number) => {
      const a = Math.max(end - dm(0.06, 0.1), after + 0.004);
      const w: Win = [a, Math.max(end, a + 0.02)];
      // The card leaves first; the clock comes back as it goes, so they barely overlap.
      const out: Win = [w[0], w[0] + (w[1] - w[0]) * 0.65];
      const late: Win = [w[0] + (w[1] - w[0]) * 0.45, w[1]];
      t.ftp(L.snippet, { opacity: 1, yPercent: 0, scale: 1 }, { opacity: 0, yPercent: -14, scale: 0.97 }, out, 'power1.in');
      t.ftp(L.glow, { opacity: 1 }, { opacity: 0 }, w);
      t.ftp(L.chrome, { opacity: 0 }, { opacity: 1 }, late);
      t.ftp(L.sbTime, { opacity: 1 }, { opacity: 0 }, late);
    };
    /**
     * Your line: karaoke, words .4 → 1 (.4 keeps a waiting line at 3:1, large text). The dim state is a class (.x-near) that is on only
     * while the part is on screen, so text at rest far from the reader is never left dim (axe
     * checks the whole page). Once a word's tween has run, its inline opacity rules; when the
     * timeline rewinds to its start, the inline styles are cleared again.
     */
    const rewound = new Map<GSAPTimeline, Element[]>();
    const karaoke = (t: TT, els: Els, w: Win) => {
      if (!els.length) return;
      const each = (t.pos(w[1]) - t.pos(w[0])) / els.length;
      t.m.fromTo(els, { opacity: 0.4 }, { opacity: 1, duration: each, stagger: each, immediateRender: false }, t.pos(w[0]));
      rewound.set(t.m, [...(rewound.get(t.m) ?? []), ...els]);
    };
    const near = (el: Element | null) =>
      el && ctx.trigger({ trigger: el, start: 'top bottom', end: 'bottom top', toggleClass: { targets: el, className: 'x-near' } });
    /** Siri's reply on the page: word by word, and the gold bars speak. */
    const reveal = (t: TT, root: Element | null, w: Win) => {
      const turn = one(root, '.x-siri');
      if (turn) {
        gsap.set(turn, { opacity: 0 });
        t.ft(turn, { opacity: 0 }, { opacity: 1 }, [w[0], w[0] + (w[1] - w[0]) * 0.15]);
      }
      const els = words(root, '.x-reply');
      if (els.length) {
        gsap.set(els, { opacity: 0 });
        const each = (t.pos(w[1]) - t.pos(w[0])) / els.length;
        // Each word appears whole at its moment (as Siri's text does), never resting half
        // faded and unreadable in the reading area.
        t.m.fromTo(els, { opacity: 0 }, { opacity: 1, duration: Math.min(each, 0.0005), stagger: each, immediateRender: false }, t.pos(w[0]));
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
    const fadeUp = (t: TT, el: Element | null, w: Win) => {
      if (!el) return;
      gsap.set(el, { opacity: 0, y: 8 });
      t.ft(el, { opacity: 0, y: 8 }, { opacity: 1, y: 0 }, w, 'power2.out');
    };
    /** The caption explains what just happened, so it comes in after the reply. */
    const caption = (t: TT, p: Element | null, w: Win) => fadeUp(t, one(p, '.x-caption'), w);

    // Where each exchange hands over to the next (outgoing timeline's progress).
    const H = {
      misheard: handoff('misheard', 'next'),
      next: handoff('next', 'lunch'),
      lunch: handoff('lunch', 'status'),
    };

    // ---- 7:18 · the misheard check ----
    {
      const t = T('misheard');
      const p = partEl('misheard');
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [0.02, 0.26]);
      listen(t, L1, [0, 0.28]);
      think(t, L1, [0.28, 0.36]);
      // Siri heard 'forty': rust waves draw under 'fourteen' and under the 40 it heard.
      const [heard, as] = all(p, '[data-squiggle]');
      const hidden = 'inset(-80% 100% -80% 0%)';
      const shown = 'inset(-80% 0% -80% 0%)';
      for (const [sq, w] of [[heard, [0.42, 0.5]], [as, [0.46, 0.54]]] as const) {
        if (!sq) continue;
        gsap.set(sq, { clipPath: hidden });
        t.ft(sq, { clipPath: hidden }, { clipPath: shown }, w);
      }
      answer(t, L1, [0.36, 0.44], [0.38, 0.5]);
      reveal(t, p, [0.36, 0.54]);
      // Then the card offers Yes and No, and you say no.
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
      // Nothing changes: the Live Activity is never touched here. Siri lets go after the No.
      caption(t, p, [0.64, 0.7]);
      fadeUp(t, one(p, '[data-note]'), [0.7, 0.76]);
      letGo(t, L1, H.misheard, t.pos(0.66));
    }

    // ---- 7:19 · next row ----
    {
      const t = T('next');
      const p = partEl('next');
      enter(t, L2, [0, 0.04]);
      karaoke(t, words(p, '[data-turn="said"] .x-said'), dm([0.08, 0.28], [0.06, 0.22]));
      listen(t, L2, dm([0.1, 0.28], [0.06, 0.22]));
      think(t, L2, dm([0.3, 0.4], [0.22, 0.28]));
      const typed = answer(t, L2, dm([0.4, 0.48], [0.28, 0.34]), dm([0.42, 0.6], [0.3, 0.44]));
      const said: Win = dm([0.4, 0.6], [0.28, 0.48]);
      reveal(t, p, said);
      caption(t, p, [said[1], said[1] + 0.06]);
      // Row 14 is marked: ten trees, and the strip moves on one row. The layer starts where the
      // 7:18 one is ([Row 14][Row 15][Row 16]): its first row button joins the strip's front.
      const mark: Win = dm([0.44, 0.52], [0.32, 0.4]);
      util.odometer(t.m, L2.trees, treesAt(MOMENTS.misheard), treesAt(MOMENTS.firstRow), t.pos(mark[0]), t.pos(mark[1]) - t.pos(mark[0]));
      const first = L2.rows[0];
      const lead = L1.rows[0]?.cloneNode(true) as HTMLElement | undefined;
      if (L2.strip && first && lead && Number(lead.dataset.row) === Number(first.dataset.row) - 1) {
        L2.strip.prepend(lead);
        cleanups.push(() => lead.remove());
        const step = first.offsetLeft - lead.offsetLeft;
        const pct = L2.strip.offsetWidth ? (step / L2.strip.offsetWidth) * 100 : 0;
        if (pct > 0) {
          gsap.set(L2.strip, { xPercent: 0 });
          t.ft(L2.strip, { xPercent: 0 }, { xPercent: -pct }, mark, 'power2.inOut');
        } else lead.remove();
      }
      letGo(t, L2, H.next, typed);
    }

    // ---- 12:01 · take lunch ----
    {
      const t = T('lunchA');
      const p = partEl('lunchA');
      const f = B.lunchAt;
      // Desktop offsets after the flip; mobile plays them faster, before the page card slides
      // over the Live Activity (about .41 on a 320 × 640 phone).
      const k = dm(1, 0.55);
      const after = (a: number, b: number): Win => [f + a * k, f + b * k];
      enter(t, L3, [0, 0.04]);
      // The morning passes with the clock: trees and rows follow it (ledgerAt, from sync).
      karaoke(t, words(p, '[data-turn="said"] .x-said'), dm([0.24, 0.44], [0.12, 0.27]));
      listen(t, L3, dm([0.24, 0.42], [0.12, 0.26]));
      think(t, L3, [f - 0.05, f]);
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
      t.flip(L3.la, { attr: { 'data-state': 'working' } }, { attr: { 'data-state': 'lunch' } }, f);
      t.ft(L3.laBreak, { opacity: 0 }, { opacity: 1 }, after(0, 0.08));
      t.ft(L3.faceClock, { opacity: 1 }, { opacity: 0 }, after(0, 0.04));
      t.ft(L3.faceBreak, { opacity: 0 }, { opacity: 1 }, after(0, 0.06));
      t.ft(L3.worked, { opacity: 0 }, { opacity: 1 }, after(0.04, 0.12));
      if (L3.rows.length) {
        const [a, b] = after(0.02, 0.12);
        const span = t.pos(b) - t.pos(a);
        const each = span * 0.12;
        t.m.fromTo(
          [...L3.rows].reverse(),
          { scaleX: 1 },
          { scaleX: 0, duration: span - each * (L3.rows.length - 1), stagger: each, ease: 'power2.in', immediateRender: false },
          t.pos(a),
        );
      }
      t.ft(L3.breakBtn, { opacity: 1 }, { opacity: 0 }, after(0.02, 0.07));
      t.ft(L3.backBtn, { clipPath: 'inset(0% 100% 0% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)' }, after(0.08, 0.2), 'power2.out');
      // No reply: the gold lock screen is the answer. Siri lets go.
      t.ft(L3.glow, { opacity: 1 }, { opacity: 0 }, after(0.14, 0.28));
      // The caption lands with the gold card.
      caption(t, p, after(0.02, 0.1));
      // Desktop: the 'On lunch · 30 min' marker between the halves appears as lunch starts.
      const between = one(article('lunch'), '[data-between]');
      if (between && isDesk) {
        gsap.set(between, { opacity: 0 });
        t.ft(between, { opacity: 0 }, { opacity: 1 }, after(0.02, 0.14));
      }
    }

    // ---- 12:31 · back to work ----
    {
      const t = T('lunchB');
      const p = partEl('lunchB');
      const b = B.backAt;
      // From-state: the lunch look (this layer's own static state is back at work), with the
      // gold face's words taken from the 12:01 layer, which the Live Activity model rendered.
      const backPill = L4.pillBreakText?.textContent ?? null;
      if (L4.pillBreakText) L4.pillBreakText.textContent = L3.pillBreakText?.textContent ?? backPill;
      cleanups.push(() => {
        if (L4.pillBreakText && backPill !== null) L4.pillBreakText.textContent = backPill;
      });
      gsap.set(L4.la, { attr: { 'data-state': 'lunch' } });
      gsap.set(L4.laBreak, { opacity: 1 });
      gsap.set(L4.faceClock, { opacity: 0 });
      gsap.set(L4.faceBreak, { opacity: 1 });
      gsap.set(L4.worked, { opacity: 1 });
      gsap.set(L4.rows, { scaleX: 0, transformOrigin: '0% 50%' });
      gsap.set(L4.breakBtn, { opacity: 0 });
      gsap.set(L4.backBtn, { clipPath: 'inset(0% 0% 0% 0%)', opacity: 1 });
      t.ft(L4.el, { opacity: 0 }, { opacity: 1 }, dm([0, 0.04], [0, 0.03]));
      // Desktop: thirty minutes of lunch fill the dotted line between the halves.
      if (isDesk) {
        const fill = one(article('lunch'), '[data-lunch-fill]');
        gsap.set(fill, { scaleY: 0 });
        t.ft(fill, { scaleY: 0 }, { scaleY: 1 }, B.spin);
      }
      karaoke(t, words(p, '[data-turn="said"] .x-said'), [B.spin[1], b - 0.04]);
      listen(t, L4, [B.spin[1], b - 0.05]);
      think(t, L4, [b - 0.05, b - 0.01]);
      util.tap(t.m, L4.backBtn, t.pos(b - 0.03), { dur: t.pos(b) - t.pos(b - 0.03) });
      t.flip(L4.la, { attr: { 'data-state': 'lunch' } }, { attr: { 'data-state': 'working' } }, b);
      t.ft(L4.laBreak, { opacity: 1 }, { opacity: 0 }, [b, b + 0.06]);
      t.ft(L4.faceBreak, { opacity: 1 }, { opacity: 0 }, [b, b + 0.04]);
      t.ft(L4.faceClock, { opacity: 0 }, { opacity: 1 }, [b, b + 0.05]);
      t.ft(L4.worked, { opacity: 1 }, { opacity: 0 }, [b, b + 0.04]);
      t.ft(L4.backBtn, { opacity: 1 }, { opacity: 0 }, [b, b + 0.025]);
      if (L4.rows.length) {
        const [a, z] = [b + 0.02, b + dm(0.1, 0.11)];
        const span = t.pos(z) - t.pos(a);
        const each = span * 0.12;
        t.m.fromTo(
          L4.rows,
          { scaleX: 0 },
          { scaleX: 1, duration: span - each * (L4.rows.length - 1), stagger: each, ease: 'power2.out', immediateRender: false },
          t.pos(a),
        );
      }
      t.ft(L4.breakBtn, { opacity: 0 }, { opacity: 1 }, [b + dm(0.05, 0.05), b + dm(0.1, 0.11)]);
      const typed = answer(t, L4, [b + 0.01, b + dm(0.06, 0.07)], [b + 0.03, b + dm(0.12, 0.17)]);
      reveal(t, p, [b + 0.01, b + dm(0.16, 0.21)]);
      // Desktop: the lunch article's timeline hands over to the 2:01 one (H.lunch is that
      // timeline's progress, not this half's).
      letGo(t, L4, H.lunch, typed);
    }

    // ---- 2:01 · how many trees ----
    {
      const t = T('status');
      const p = partEl('status');
      enter(t, L5, [0, 0.04]);
      // The early afternoon passes with the clock: trees and rows follow it (ledgerAt).
      karaoke(t, words(p, '[data-turn="said"] .x-said'), dm([0.14, 0.3], [0.12, 0.28]));
      listen(t, L5, dm([0.12, 0.3], [0.1, 0.28]));
      think(t, L5, dm([0.3, 0.4], [0.28, 0.36]));
      answer(t, L5, dm([0.4, 0.48], [0.36, 0.44]), dm([0.42, 0.6], [0.38, 0.56]));
      const said: Win = dm([0.4, 0.66], [0.36, 0.6]);
      reveal(t, p, said);
      caption(t, p, [said[1], said[1] + 0.06]);
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
    // A ScrollTrigger refresh (a resize, or a scene built elsewhere changing the page's height)
    // moves the playheads with their update events suppressed: recompute the minute after it,
    // or the clock would rest on a stale time after a jump.
    const ST = ctx.ScrollTrigger;
    ST.addEventListener('refresh', sync);
    cleanups.push(() => ST.removeEventListener('refresh', sync));
    return () => cleanups.forEach((f) => f());
  },
  { dayStart: MOMENTS.clockIn, invalidate: false },
);
