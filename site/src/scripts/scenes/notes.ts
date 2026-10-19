/**
 * NOTES · 2:30 PM, on a break. A scrubbed scene (no pins): positions come from
 * src/sections/notes/plan.ts (unit-tested), strings from the ledger and siri.ts.
 *
 *   0       2:16 → 2:30 on the lock screen the lock-screen chapter left (Row 36 marked · Undo)
 *   break   "Take a break with Time Card." → "What's the break for?" → "Sharpening shears."
 *           → "Break for sharpening shears started at 2:30." and the card turns gold:
 *           the pill swaps, the strip collapses from the right, Back to work wipes in,
 *           the timer rolls from 6:43:00 worked to the break's 0:00:00
 *   tree    "Note a tree in Time Card." → four answer chips → "Noted on block 2, row 36,
 *           tree 7." → unlock to the Trees tab
 *   crew    the rust flag drops onto row 36 tree 7 with one ripple, the map scrolls, a tap,
 *           the note sheet rises; then it lowers and the lock screen slides back down
 *   shift   "Add a note in Time Card." → the dictation types in the phone and on the page →
 *           "Added to today's notes." → the paper time-card strip prints
 *   back    2:44: a tap on Back to work; green again, rows 37, 38, 39 and Break, 6:43:00
 *
 * Static first: the server markup is every layer's own state and the final layer is the
 * note sheet. This file only sets from-states (at build) and tweens towards the markup.
 * Screen layers that a real capture replaced lose their hooks; every lookup tolerates that.
 */
import { registerScene, type SceneContext } from '../scene.ts';
import { MOMENTS, liveActivityAt } from '../../data/ledger.ts';
import { setWave } from '../wave.ts';
import { activityView } from '../../components/system/lockscreen/activity.ts';
import { plan, type BeatKey, type Span } from '../../sections/notes/plan.ts';
import { TRANSCRIPT_PARTS } from '../../sections/notes/copy.ts';

type El = HTMLElement;

/** The gold face before a reason is given ('On break': the card's own button gives none). */
const SHORT_BREAK = activityView({ at: MOMENTS.island }).pillBreak;
/** The gold face once the reason is spoken: 'On break · Sharpening shears'. */
const BREAK_PILL = liveActivityAt(MOMENTS.break).pill;

registerScene(
  'notes',
  (ctx: SceneContext) => {
    const { tl, day, util, gsap, section, isDesk } = ctx;
    // ctx.screens can be another section's container when the stage holds several during a
    // hand-over (a jump straight to #notes): find ours by its own layer ids.
    const ours = (el: Element | null | undefined) => (el?.querySelector(':scope > [data-screen="lock-1430-break"]') ? (el as El) : null);
    const screens = ours(ctx.screens) ?? ours(document.querySelector('[data-screen="lock-1430-break"]')?.parentElement) ?? ctx.screens;
    const P = plan(isDesk ? 'desk' : 'mob');
    const dur = (s: Span) => Math.max(s[1] - s[0], 0.001);

    // ---- Lookups (scoped to a layer; null-safe) ----
    const layer = (id: string) => screens?.querySelector<El>(`:scope > [data-screen="${id}"]`) ?? null;
    const one = (root: Element | null, sel: string) => root?.querySelector<El>(sel) ?? null;
    const many = (root: Element | null, sel: string) => (root ? Array.from(root.querySelectorAll<El>(sel)) : []);
    const page = (sel: string) => section.querySelector<El>(sel);
    const set = (el: Element | Element[] | null, vars: gsap.TweenVars) => {
      if (el && (!Array.isArray(el) || el.length)) gsap.set(el, vars);
    };
    const to = (el: Element | Element[] | null, vars: gsap.TweenVars, at: number) => {
      if (el && (!Array.isArray(el) || el.length)) tl.to(el, vars, at);
    };
    /** Hand over between layers that show the same pixels: the new one on top, the old one off. */
    const swap = (from: El | null, into: El | null, at: number) => {
      if (into) tl.set(into, { opacity: 1 }, at);
      if (from) tl.set(from, { opacity: 0 }, at + 0.001);
    };
    /**
     * Change an element's text at `at`, reversibly (a scrubbed timeline runs both ways).
     * The Live Activity's pill stacks both faces in one grid cell, so the hidden gold face's
     * text sets the pill's width: it reads the short 'On break' until the reason is spoken.
     */
    const textAt = (el: El | null, before: string, after: string, at: number) => {
      if (!el) return;
      tl.to({}, { duration: 0.0005, onStart: () => void (el.textContent = after), onReverseComplete: () => void (el.textContent = before) }, at);
    };
    /** Markup text a from-state overwrites, restored when the scene is reverted. */
    const written = new Map<El, string>();
    const remember = (el: El | null) => {
      if (el && !written.has(el)) written.set(el, el.textContent ?? '');
    };
    const keepState = (la: El | null) => {
      if (la && !la.dataset.nbState) la.dataset.nbState = la.getAttribute('data-state') ?? '';
    };

    const L = {
      flag: layer('trees-1433-flag'),
      note: layer('trees-1433-note'),
      brk: layer('lock-1430-break'),
      tree: layer('lock-1433-treenote'),
      shift: layer('lock-1436-dictation'),
      back: layer('lock-1444-back'),
    };

    // ---- Layers: start on the break lock screen ----
    util.show(screens, 'lock-1430-break');

    // ---- The day: 2:16 → 2:30 → 2:33 → 2:36 → 2:44 ----
    for (const d of P.day) day.to(tl, d.min, d.start, d.end);

    // ---- Shared pieces of a lock layer with Siri ----
    const chrome = (lay: El | null) =>
      many(lay, ':scope [data-lock] > [data-date], :scope [data-lock] > [data-clock], :scope [data-lock] > [data-padlock]');
    const card = (lay: El | null, key: string) => one(lay, `[data-nb-card="${key}"] [data-snippet], [data-nb-card="${key}"] [data-wave]`);
    const glow = (lay: El | null) => one(lay, '[data-glow]');
    const ring = (lay: El | null) => one(lay, '[data-glow-ring]');

    /** Siri glow on over `on`, off over `off`; its ring turns slowly in between (scrubbed). */
    const glowSpan = (lay: El | null, on: Span, off: Span) => {
      const g = glow(lay);
      const r = ring(lay);
      if (!g) return;
      set(g, { opacity: 0 });
      to(g, { opacity: 1, duration: dur(on), ease: 'power1.out' }, on[0]);
      to(g, { opacity: 0, duration: dur(off), ease: 'power1.in' }, off[0]);
      if (r) {
        set(r, { rotation: 0 });
        to(r, { rotation: 150, duration: off[1] - on[0], ease: 'none' }, on[0]);
      }
    };

    /** A Siri card drops into the slot (and the lock screen's clock gives way, if it is showing). */
    const cardIn = (el: El | null, s: Span, lay: El | null, hideChrome: boolean) => {
      if (!el) return;
      to(el, { opacity: 1, y: 0, duration: dur(s), ease: 'power3.out' }, s[0]);
      if (hideChrome) to(chrome(lay), { opacity: 0, duration: dur(s), ease: 'power1.out' }, s[0]);
    };
    /** One card replaces another in the same slot (never stacked). */
    const cardSwap = (out: El | null, inn: El | null, s: Span) => {
      to(out, { opacity: 0, scale: 0.97, duration: dur(s) * 0.7, ease: 'power1.in' }, s[0]);
      if (inn) {
        set(inn, { scale: 0.97 });
        to(inn, { opacity: 1, y: 0, scale: 1, duration: dur(s), ease: 'power2.out' }, s[0] + dur(s) * 0.3);
      }
    };
    const cardOut = (el: El | null, s: Span, lay: El | null) => {
      // The card is nearly gone before the clock comes back, so the two never read over each other.
      to(el, { opacity: 0, y: -10, duration: dur(s) * 0.6, ease: 'power1.in' }, s[0]);
      to(chrome(lay), { opacity: 1, duration: dur(s) * 0.55, ease: 'power1.out' }, s[0] + dur(s) * 0.45);
    };
    const prepSiri = (lay: El | null) => {
      set(chrome(lay), { opacity: 1 });
      set(many(lay, '[data-nb-card] [data-snippet], [data-nb-card] [data-wave]'), { opacity: 0, y: -14, transformOrigin: '50% 0%' });
    };
    /** The dictation wave, scrubbed by seeded noise (same progress, same bars). */
    const wave = (el: El | null, s: Span) => {
      if (!el) return;
      setWave(el, 0);
      const o = { p: 0 };
      tl.to(o, { p: 1, duration: dur(s), ease: 'none', onUpdate: () => setWave(el, o.p) }, s[0]);
    };
    const typePhone = (el: El | null, s: Span) => {
      const text = one(el, '[data-snippet-text], [data-transcript]');
      if (text) util.typeIn(tl, text, s[0], dur(s));
    };

    // ---- Page copy ----
    // Page effects play on desktop, where the copy sits beside the phone. Mobile cards rise
    // over the phone while it plays, so their text simply reads (static, like the markup).
    const fx = isDesk;
    /** A Siri line on the page: its rule shows, then its words (never the hidden 'Siri:' label). */
    const reveal = (key: string, s: Span) => {
      const line = page(`[data-nb-line="${key}"]`);
      const text = page(`[data-nb-reply="${key}"]`);
      if (!line || !text || !fx) return;
      const words = util.split(text, 'words');
      set(line, { opacity: 0 });
      to(line, { opacity: 1, duration: 0.004, ease: 'none' }, s[0]);
      // Each word appears whole at its moment (never resting half faded in the reading area).
      tl.fromTo(words, { opacity: 0 }, { opacity: 1, duration: 0.0005, stagger: dur(s) / Math.max(words.length, 1), ease: 'none' }, s[0]);
    };
    const karaoke = (el: El | null, s: Span) => {
      if (el && fx) util.karaoke(tl, el, s[0], dur(s));
    };

    // Copy beats fade in as they rise (desktop, by progress) and out as they reach the header
    // (desktop, by position), or out over the phone (mobile, by progress).
    const beats: Record<'head' | BeatKey, El | null> = {
      head: section.querySelector<El>('.beat-head'),
      break: page('[data-nb="break"]'),
      tree: page('[data-nb="tree"]'),
      crew: page('[data-nb="crew"]'),
      shift: page('[data-nb="shift"]'),
      back: page('[data-nb="back"]'),
    };
    // Opacity only: the shell centres each beat with the CSS `translate` property, and a GSAP
    // transform on the same element would take that over (and freeze it in px).
    for (const [key, el] of Object.entries(beats) as Array<['head' | BeatKey, El | null]>) {
      if (!el) continue;
      const f = P.copy[key];
      if (f.in) {
        set(el, { opacity: 0 });
        to(el, { opacity: 1, duration: dur(f.in), ease: 'power1.out' }, f.in[0]);
      }
      if (f.out) to(el, { opacity: 0, duration: dur(f.out), ease: 'power1.in' }, f.out[0]);
    }
    if (isDesk) {
      // The header and ribbon are see-through, so on desktop every beat is gone by the time its
      // top reaches them, whatever its height and the viewport's: a position-based fade on its
      // body (the beat itself carries the progress fade-in), measured again on every refresh.
      const grid = section.querySelector<El>('.frame-grid');
      const edge = () => (grid ? parseFloat(getComputedStyle(grid).paddingTop) || 59 : 59) + 8;
      const reach = () => Math.round(Math.min(96, Math.max(56, innerHeight * 0.1)));
      for (const [key, el] of Object.entries(beats) as Array<['head' | BeatKey, El | null]>) {
        const body = key === 'head' ? el : one(el, ':scope > .nb-body');
        if (!el || !body) continue;
        const fade = gsap.fromTo(body, { opacity: 1 }, { opacity: 0, ease: 'none', paused: true });
        ctx.trigger({ trigger: el, start: () => `top ${edge() + reach()}px`, end: () => `top ${edge()}px`, scrub: true, animation: fade });
      }
    }

    // The headline: lines rise out of a mask once, not scrubbed.
    const h2 = section.querySelector<El>(`#${section.id}-h`);
    if (h2) {
      const split = ctx.SplitText.create(h2, { type: 'lines', mask: 'lines', aria: 'auto' });
      const rise = gsap.from(split.lines, { yPercent: 100, duration: 0.7, stagger: 0.08, ease: 'power3.out', paused: true });
      ctx.trigger({ trigger: h2, start: 'top 75%', once: true, onEnter: () => rise.play() });
    }

    // =======================================================================
    // BREAK · lock-1430-break: from "Row 36 marked · Undo" at 2:16 to gold at 2:30
    // =======================================================================
    {
      const lay = L.brk;
      const la = one(lay, '[data-la]');
      prepSiri(lay);
      glowSpan(lay, P.break.glow, P.break.glowOff);
      karaoke(page('[data-nb-said="break"]'), P.break.said);

      const ask = card(lay, 'ask');
      const wv = card(lay, 'wave');
      const reply = card(lay, 'reply');
      cardIn(ask, P.break.ask, lay, true);
      typePhone(ask, P.break.askType);
      reveal('ask', P.break.askLine);
      cardSwap(ask, wv, [P.break.wave[0], P.break.wave[0] + 0.008]);
      wave(wv, P.break.wave);
      typePhone(wv, P.break.answer);
      // Your answer waits for Siri's question (its space stays reserved: no layout shift).
      const you = fx ? page('.nb-you') : null;
      set(you, { opacity: 0 });
      to(you, { opacity: 1, duration: 0.004, ease: 'none' }, P.break.wave[0]);
      karaoke(page('[data-nb-answer="break"]'), P.break.answer);
      cardSwap(wv, reply, P.break.reply);
      typePhone(reply, P.break.replyType);
      reveal('break', P.break.replyType);
      cardOut(reply, P.break.cardOut, lay);

      if (la) {
        // From-state: working, with the 2:14 tap's "Row 36 marked · Undo" still showing.
        const rows = many(la, '[data-row]');
        const undoRow = one(la, '[data-undo-row]');
        remember(undoRow);
        if (undoRow) undoRow.textContent = String(liveActivityAt(MOMENTS.island).undoRow ?? '');
        const face = one(la, '[data-pill-text="break"]');
        remember(face);
        if (face) face.textContent = SHORT_BREAK;
        keepState(la);
        gsap.set(la, { attr: { 'data-state': 'tapped' } });
        set(one(la, '[data-la-break]'), { opacity: 0 });
        set(one(la, '[data-pill-face="clock"]'), { opacity: 1 });
        set(one(la, '[data-pill-face="break"]'), { opacity: 0 });
        set(one(la, '[data-undo]'), { opacity: 1 });
        set(one(la, '[data-worked-line]'), { opacity: 0 });
        set(rows, { scaleX: 1, opacity: 1, transformOrigin: '100% 50%' });
        set(one(la, '[data-break-btn]'), { opacity: 1 });
        set(one(la, '[data-back-btn]'), { clipPath: 'inset(0% 100% 0% 0%)' });

        const s = P.break.la;
        const d = dur(s);
        // The pill and Undo cross over first; at P.break.start (the day reaches 2:30 there) the
        // card turns gold and the timer switches to the break's 0:00:00 under the new pill.
        tl.set(la, { attr: { 'data-state': 'break' } }, P.break.start);
        textAt(face, SHORT_BREAK, BREAK_PILL, s[0]);
        to(one(la, '[data-la-break]'), { opacity: 1, duration: d * 0.5, ease: 'power1.inOut' }, s[0]);
        // The old face goes, then the new one comes with the new state (never two labels at once).
        const sw = P.break.start - s[0];
        to(one(la, '[data-pill-face="clock"]'), { opacity: 0, duration: sw, ease: 'none' }, s[0]);
        to(one(la, '[data-pill-face="break"]'), { opacity: 1, duration: d * 0.12, ease: 'none' }, P.break.start);
        to(one(la, '[data-undo]'), { opacity: 0, duration: sw, ease: 'none' }, s[0]);
        to(one(la, '[data-worked-line]'), { opacity: 1, duration: d * 0.25, ease: 'none' }, P.break.start);
        // Each row button folds into its right edge; its label fades first, so it never squashes.
        if (rows.length) {
          const back = rows.slice().reverse();
          tl.to(back, { scaleX: 0, duration: d * 0.35, stagger: d * 0.08, ease: 'power2.in' }, s[0] + d * 0.05);
          tl.to(back, { opacity: 0, duration: d * 0.15, stagger: d * 0.08, ease: 'none' }, s[0] + d * 0.05);
        }
        to(one(la, '[data-break-btn]'), { opacity: 0, duration: d * 0.2, ease: 'none' }, s[0] + d * 0.1);
        to(one(la, '[data-back-btn]'), { clipPath: 'inset(0% 0% 0% 0%)', duration: d * 0.45, ease: 'power2.inOut' }, s[0] + d * 0.45);
      }
    }
    // Identical pixels (same lock screen, same gold card, the clock back): hand over silently.
    swap(L.brk, L.tree, P.break.swap);

    // =======================================================================
    // TREE NOTE · lock-1433-treenote, then unlock
    // =======================================================================
    {
      const lay = L.tree;
      prepSiri(lay);
      glowSpan(lay, P.tree.glow, P.tree.glowOff);
      karaoke(page('[data-nb-said="tree"]'), P.tree.said);
      const wv = card(lay, 'wave');
      const reply = card(lay, 'reply');
      cardIn(wv, [P.tree.wave[0], P.tree.wave[0] + 0.01], lay, true);
      wave(wv, P.tree.wave);
      // Your answers type into the transcript as their chips appear: the row, the tree, the note.
      const said = one(wv, '[data-transcript]');
      if (said) {
        const chars = util.split(said, 'chars');
        const spans: Span[] = [
          [P.tree.chips[0], P.tree.chips[0] + P.tree.chipDur],
          [P.tree.chips[1], P.tree.chips[1] + P.tree.chipDur],
          P.tree.note,
        ];
        let i = 0;
        TRANSCRIPT_PARTS.forEach((part, k) => {
          const n = part.replace(/\s/g, '').length;
          const these = chars.slice(i, i + n);
          i += n;
          const span = spans[k]!;
          const each = dur(span) / Math.max(these.length, 1);
          if (these.length) tl.fromTo(these, { opacity: 0 }, { opacity: 1, duration: Math.min(each, 0.002), stagger: each, ease: 'none' }, span[0]);
        });
        // Anything past the known parts (a capture's own words) types with the note.
        if (i < chars.length) tl.fromTo(chars.slice(i), { opacity: 0 }, { opacity: 1, duration: 0.002, stagger: dur(P.tree.note) / (chars.length - i), ease: 'none' }, P.tree.note[0]);
      }
      cardSwap(wv, reply, P.tree.reply);
      typePhone(reply, P.tree.replyType);
      reveal('tree', P.tree.replyType);

      // The answers, one per step; the flag lands with a little overshoot.
      if (fx) P.tree.chips.forEach((t, i) => {
        const chip = page(`[data-nb-chip="${i}"]`);
        if (!chip) return;
        set(chip, { opacity: 0, y: 12 });
        to(chip, { opacity: 1, y: 0, duration: P.tree.chipDur, ease: i === 3 ? 'back.out(1.6)' : 'power2.out' }, t);
      });

      // Unlock: the lock screen slides up and away, the app settles in from .94.
      const app = L.flag;
      if (app) {
        set(app, { opacity: 0, scale: 0.94 });
        tl.set(app, { opacity: 1 }, P.tree.unlock[0]);
        to(app, { scale: 1, duration: dur(P.tree.unlock), ease: 'power3.out' }, P.tree.unlock[0]);
      }
      to(lay, { yPercent: -100, duration: dur(P.tree.unlock), ease: 'power3.inOut' }, P.tree.unlock[0]);
      util.sheen(tl, P.tree.unlock[0]);
    }

    // =======================================================================
    // CREW · the flag drops, the map scrolls, the sheet rises (trees-1433-flag → -note)
    // =======================================================================
    {
      const a = L.flag;
      const b = L.note;
      const marker = one(a, `[data-note-marker="2-36-7"]`);
      const ripple = one(marker, '[data-note-ripple]');
      if (marker) {
        set(marker, { opacity: 0, yPercent: -90 });
        to(marker, { opacity: 1, duration: dur(P.crew.drop) * 0.4, ease: 'none' }, P.crew.drop[0]);
        to(marker, { yPercent: 0, duration: dur(P.crew.drop), ease: 'back.out(1.8)' }, P.crew.drop[0]);
      }
      // On the page, the new note joins the old one as its flag lands.
      const row = fx ? page('[data-nb-flag="0"]') : null;
      set(row, { opacity: 0, x: -12 });
      to(row, { opacity: 1, x: 0, duration: dur(P.crew.drop), ease: 'power2.out' }, P.crew.drop[0] + dur(P.crew.drop) * 0.4);
      if (ripple) {
        set(ripple, { opacity: 0, scale: 0.5 });
        to(ripple, { keyframes: { opacity: [0, 0.75, 0] }, scale: 1.7, duration: dur(P.crew.ripple), ease: 'power2.out' }, P.crew.ripple[0]);
      }
      // Scroll the map so it lines up row for row with the sheet layer's map.
      const firstRow = (lay: El | null) => {
        const r = one(lay, '[data-map-row]');
        return r ? Number(r.dataset.mapRow) : NaN;
      };
      const shift = firstRow(b) - firstRow(a);
      if (Number.isFinite(shift) && shift !== 0) {
        to(many(a, '[data-block-row]'), { yPercent: -100 * shift, duration: dur(P.crew.scroll), ease: 'power2.inOut' }, P.crew.scroll[0]);
      }
      if (marker) util.tap(tl, marker, P.crew.tap, { shake: false });
      // The same map with the tree selected, the sheet waiting below the screen.
      const sheet = one(b, '[data-sheet]');
      set(sheet, { yPercent: 100 });
      if (b) swap(a, b, P.crew.swap);
      to(sheet, { yPercent: 0, duration: dur(P.crew.sheetUp), ease: 'expo.out' }, P.crew.sheetUp[0]);
      to(sheet, { yPercent: 100, duration: dur(P.crew.sheetDown), ease: 'power2.in' }, P.crew.sheetDown[0]);

      // The lock screen comes back down over the app, like pulling down from the top.
      const lock = L.shift;
      if (lock) {
        set(lock, { opacity: 0, yPercent: -100 });
        tl.set(lock, { opacity: 1 }, P.crew.lockIn[0]);
        to(lock, { yPercent: 0, duration: dur(P.crew.lockIn), ease: 'power3.inOut' }, P.crew.lockIn[0]);
        util.sheen(tl, P.crew.lockIn[0]);
      }
    }

    // =======================================================================
    // SHIFT NOTE · lock-1436-dictation
    // =======================================================================
    {
      const lay = L.shift;
      prepSiri(lay);
      glowSpan(lay, P.shift.glow, P.shift.glowOff);
      karaoke(page('[data-nb-said="shift"]'), P.shift.said);
      const wv = card(lay, 'wave');
      const reply = card(lay, 'reply');
      cardIn(wv, [P.shift.wave[0], P.shift.wave[0] + 0.01], lay, true);
      wave(wv, P.shift.wave);
      typePhone(wv, P.shift.type);
      cardSwap(wv, reply, P.shift.reply);
      typePhone(reply, P.shift.replyType);
      cardOut(reply, P.shift.cardOut, lay);

      // On the page: your words type into your bubble, then Siri's bubble answers.
      const you = fx ? page('[data-nb-bubble="you"]') : null;
      const siri = fx ? page('[data-nb-bubble="siri"]') : null;
      set(you, { opacity: 0, y: 10 });
      to(you, { opacity: 1, y: 0, duration: 0.01, ease: 'power2.out' }, P.shift.type[0] - 0.01);
      const typed = fx ? page('[data-nb-type="shift"]') : null;
      if (typed) util.typeIn(tl, typed, P.shift.type[0], dur(P.shift.type));
      set(siri, { opacity: 0, y: 10 });
      to(siri, { opacity: 1, y: 0, duration: 0.01, ease: 'power2.out' }, P.shift.replyType[0] - 0.006);
      const said = fx ? page('[data-nb-reply="shift"]') : null;
      if (said) {
        const words = util.split(said, 'words');
        tl.fromTo(words, { opacity: 0 }, { opacity: 1, duration: 0.0005, stagger: dur(P.shift.replyType) / words.length, ease: 'none' }, P.shift.replyType[0]);
      }
      // The note prints onto the time card strip.
      const strip = fx ? page('[data-nb-strip]') : null;
      set(strip, { clipPath: 'inset(0% 0% 100% 0%)', y: -6 });
      to(strip, { clipPath: 'inset(0% 0% 0% 0%)', y: 0, duration: dur(P.shift.strip), ease: 'power2.out' }, P.shift.strip[0]);
    }
    swap(L.shift, L.back, P.shift.swap);

    // =======================================================================
    // BACK · lock-1444-back: tap Back to work at 2:44, green again
    // =======================================================================
    {
      const la = one(L.back, '[data-la]');
      if (la) {
        const rows = many(la, '[data-row]');
        const back = one(la, '[data-back-btn]');
        const pillBreak = one(la, '[data-pill-text="break"]');
        // From-state: the break as it stood (the reason came by voice).
        remember(pillBreak);
        if (pillBreak) pillBreak.textContent = BREAK_PILL;
        keepState(la);
        gsap.set(la, { attr: { 'data-state': 'break' } });
        set(one(la, '[data-la-break]'), { opacity: 1 });
        set(one(la, '[data-pill-face="clock"]'), { opacity: 0 });
        set(one(la, '[data-pill-face="break"]'), { opacity: 1 });
        set(one(la, '[data-worked-line]'), { opacity: 1 });
        set(rows, { scaleX: 0, opacity: 0, transformOrigin: '0% 50%' });
        set(one(la, '[data-break-btn]'), { opacity: 0 });
        set(back, { clipPath: 'inset(0% 0% 0% 0%)', opacity: 1 });

        if (back) util.tap(tl, back, P.back.tap);
        const s = P.back.la;
        const d = dur(s);
        // The card stays in its break state until the gold face has gone; then, at P.back.end
        // (the day reaches 2:44 there), it turns green (white timer, the field back in the place
        // line) and the timer resumes at 6:43:00, with the short face text behind it.
        tl.set(la, { attr: { 'data-state': 'working' } }, P.back.end);
        to(one(la, '[data-la-break]'), { opacity: 0, duration: d * 0.5, ease: 'power1.inOut' }, s[0]);
        to(one(la, '[data-pill-face="break"]'), { opacity: 0, duration: P.back.end - s[0], ease: 'none' }, s[0]);
        to(one(la, '[data-pill-face="clock"]'), { opacity: 1, duration: d * 0.12, ease: 'none' }, P.back.end);
        textAt(pillBreak, BREAK_PILL, SHORT_BREAK, P.back.end - 0.0005);
        to(one(la, '[data-worked-line]'), { opacity: 0, duration: d * 0.2, ease: 'none' }, s[0]);
        // Back to work wipes off towards the rows' side and fades as it goes: no blank gold sliver.
        to(back, { clipPath: 'inset(0% 0% 0% 100%)', duration: d * 0.4, ease: 'power2.inOut' }, s[0] + d * 0.05);
        to(back, { opacity: 0, duration: d * 0.25, ease: 'power1.in' }, s[0] + d * 0.05);
        if (rows.length) {
          tl.to(rows, { scaleX: 1, duration: d * 0.35, stagger: d * 0.08, ease: 'back.out(1.4)' }, s[0] + d * 0.3);
          tl.to(rows, { opacity: 1, duration: d * 0.2, stagger: d * 0.08, ease: 'power1.out' }, s[0] + d * 0.38);
        }
        to(one(la, '[data-break-btn]'), { opacity: 1, duration: d * 0.25, ease: 'none' }, s[0] + d * 0.6);
      }
    }

    return () => {
      // Text and states written for from-states go back to the markup's (the static state).
      for (const [el, text] of written) el.textContent = text;
      for (const lay of [L.brk, L.back]) {
        const la = one(lay, '[data-la]');
        if (la?.dataset.nbState) la.setAttribute('data-state', la.dataset.nbState);
      }
    };
  },
  { dayStart: MOMENTS.island },
);
