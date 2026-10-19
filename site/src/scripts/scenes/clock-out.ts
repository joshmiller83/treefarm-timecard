/**
 * CLOCK OUT · 4:31 PM (scene). Spec:
 *   jq '.sections[] | select(.id=="clock-out") | .animation' docs/landing/brief.json
 * Windows live in src/sections/clock-out/model.ts (DESK, MOB), unit-tested against the brief.
 *
 * Desktop (the stage phone):
 *   lapse     day 3:40 → 4:31: the timer spins, the trees roll 260 → 290, the strip advances
 *   ask       karaoke on “Clock out with Time Card.”, Siri's glow, the question types in
 *   yes       tap Yes; “Yes.” appears
 *   answer    the answer types in; a gold rule sweeps under the stopped timer
 *   dismiss   the Live Activity leaves like iOS; the ribbon completes
 *   lights    a light layer fades over the stage; at .4 the section turns light
 *   copyIn    the report copy takes over columns 1–5 (held in the sticky frame)
 *   unlock    to the Report tab; tap This week
 *   lift      the paper lifts out of the preview (a FLIP) while the phone steps right
 *   print     rows print top to bottom, Friday last with a gold flash; the totals rule draws
 *   annotate  “No pay on the report. Ever.”; tap Export PDF, then CSV; the chips pop
 *   rest      the phone settles back to rest
 * Mobile: the same exchange on the section's sticky phone; the light part (copy, the Report
 * tab, the paper) is in flow after the track and rises in one piece, one day block at a time.
 *
 * Only transform, opacity and clip-path animate (plus the theme flip, whose 0.4 s color
 * transition lives in CSS). The phone is at rest at 0 and 1.
 *
 * From-states for staggered tweens are set at build with gsap.set and played with tl.to: a
 * staggered fromTo inside a scrubbed timeline only renders its first target's from-state early.
 */
import { registerScene } from '../scene.ts';
import { odometerHTML } from '../odometer.ts';
import { AT, DESK, FROM, MOB, lapse, lapseAt } from '../../sections/clock-out/model.ts';

/** The stage phone's frame is 420 u wide; the screen is set in 13.5 u on every side. */
const INSET = 13.5 / 420;
/** The page card's layout width (the Report tab preview is drawn at its proportions). */
const CARD_W = 720;

type El = Element | null | undefined;

registerScene(
  'clock-out',
  (ctx) => {
    const { tl, day, util, gsap, section, phone, isDesk, ScrollTrigger } = ctx;
    const B = isDesk ? DESK : MOB;
    const L = lapse();
    const undo: Array<() => void> = [];

    // This section's own screens. When a chapter link jumps here, the stage can claim the
    // section before the scene builds, and ctx.screens may then be the previous chapter's
    // screens still fading out of the stage; the quiet layer exists only in ours.
    const own = (el: El) => (el?.querySelector(':scope > [data-screen="lock-1631-quiet"]') ? (el as HTMLElement) : null);
    const screens = own(ctx.screens) ?? document.querySelector<HTMLElement>('[data-screens] > [data-screen="lock-1631-quiet"]')?.parentElement ?? null;

    const one = <T extends Element = HTMLElement>(root: El, sel: string) => (root?.querySelector<T>(sel) ?? null) as T | null;
    const all = <T extends Element = HTMLElement>(root: El, sel: string) => (root ? Array.from(root.querySelectorAll<T>(sel)) : []);
    const layer = (id: string) => one(screens, `:scope > [data-screen="${id}"]`);
    const act = layer('lock-1631-activity');
    const ask = layer('lock-1631-ask');
    const ans = layer('lock-1631-answer');
    const quiet = layer('lock-1631-quiet');
    const report = layer('report-week');
    const span = (w: readonly [number, number]) => w[1] - w[0];

    /** A tween only when its targets exist (GSAP warns on empty targets). */
    const has = (t: El | El[]) => (Array.isArray(t) ? t.filter(Boolean).length > 0 : !!t);
    const set = (t: El | El[], at: number, vars: GSAPTweenVars) => has(t) && tl.set(t as gsap.TweenTarget, vars, at);
    /** Staggered reveal: from-state now, played forwards by the timeline. */
    const reveal = (targets: Element[], from: GSAPTweenVars, to: GSAPTweenVars, at: number, dur: number) => {
      if (!targets.length) return;
      gsap.set(targets, from);
      const each = dur / targets.length;
      tl.to(targets, { ...to, duration: Math.max(each, 0.001), stagger: each, ease: to.ease ?? 'none' }, at);
    };
    const typeIn = (el: El, at: number, dur: number) => {
      if (!el) return;
      const chars = util.split(el, 'chars');
      if (!chars.length) return;
      gsap.set(chars, { opacity: 0 });
      const each = dur / chars.length;
      tl.to(chars, { opacity: 1, duration: Math.min(each, 0.002), stagger: each, ease: 'none' }, at);
    };
    // The page's lines are pre-split into word spans (.co-w) on the server.
    const lightWords = (el: El, at: number, dur: number, from: number) => reveal(all(el, '.co-w'), { opacity: from }, { opacity: 1 }, at, dur);

    // ---- The section starts at dusk and turns light at the lights-up ----
    const theme = section.dataset.theme;
    section.dataset.theme = 'dark';
    undo.push(() => {
      if (theme) section.dataset.theme = theme;
    });

    util.show(screens, 'lock-1631-activity');

    // ---- The day: 3:40 → 4:31, then the ribbon's last stretch with the dismiss ----
    day.to(tl, AT, B.lapse[0], B.lapse[1], FROM);
    day.complete(tl, B.dismiss[0], B.dismiss[1]);

    // ---- Time-lapse on the Live Activity (its timer follows the DayClock on its own) ----
    const rim = one(phone, '[data-rim]');
    if (rim) tl.to(rim, { opacity: 0.6, duration: span(B.lapse) }, B.lapse[0]);

    const trees = one(act, '[data-trees]');
    const bar = one(act, '[data-fieldbar]');
    // The row buttons roll their numbers like the trees (rows 39–41 → 42–44 over three marks).
    const rowNums = all(act, '[data-strip] [data-row]').map((btn, i) => {
      const before = btn.innerHTML;
      undo.push(() => (btn.innerHTML = before));
      const label = `Row ${L.rows[0][0] + i}`;
      btn.innerHTML = `<span class="odo co-rowodo" data-odo data-odo-text="${label}">${odometerHTML(label)}</span>`;
      return btn.querySelector<HTMLElement>('.odo');
    });
    if (bar) gsap.set(bar, { scaleX: L.fieldPct[0] });
    let prevTrees = L.trees[0];
    L.steps.forEach((s, k) => {
      const t = lapseAt(B.lapse, s.t) - 0.004;
      const d = 0.008;
      util.odometer(tl, trees, prevTrees, s.trees, t, d);
      prevTrees = s.trees;
      rowNums.forEach((el, i) => {
        const from = L.rows[0][0] + i + k;
        util.odometer(tl, el, from, from + 1, t, d, (v) => `Row ${v}`);
      });
      if (bar) tl.to(bar, { scaleX: s.fieldPct, duration: d, ease: 'power2.out' }, t);
    });

    // ---- Ask: karaoke on the user line, Siri's glow, the question types in ----
    lightWords(section.querySelector('[data-co-said]'), B.karaoke[0], span(B.karaoke), 0.25);

    set(act, B.glow[0], { opacity: 0 });
    set(ask, B.glow[0], { opacity: 1 });
    const glow = one(ask, '[data-glow]');
    const ring = one(ask, '[data-glow-ring]');
    if (glow) tl.fromTo(glow, { opacity: 0 }, { opacity: 1, duration: span(B.glow), ease: 'power1.out' }, B.glow[0]);
    if (ring) tl.fromTo(ring, { rotation: 0 }, { rotation: 140, duration: B.answer[0] - B.glow[0] }, B.glow[0]);

    const askCard = one(ask, '[data-snippet]');
    const askChrome = all(ask, '[data-lock] > :is([data-date], [data-clock], [data-padlock])');
    const askSpan = span(B.ask);
    const dropDur = askSpan * 0.18;
    const typeAt = B.ask[0] + dropDur * 0.6;
    const typeDur = askSpan * 0.55;
    if (askCard) tl.fromTo(askCard, { opacity: 0, y: -14 }, { opacity: 1, y: 0, duration: dropDur, ease: 'power2.out' }, B.ask[0]);
    if (askChrome.length) {
      gsap.set(askChrome, { opacity: 1 });
      tl.to(askChrome, { opacity: 0, duration: dropDur }, B.ask[0]);
    }
    typeIn(one(askCard, '[data-snippet-text]'), typeAt, typeDur);
    reveal(all(askCard, '[data-choice]'), { opacity: 0, y: 6 }, { opacity: 1, y: 0, ease: 'power2.out' }, B.ask[1] - askSpan * 0.22, askSpan * 0.2);
    // The page reveals Siri's question word by word as the phone types it.
    lightWords(section.querySelector('[data-co-reply="ask"]'), typeAt, typeDur, 0.2);

    // ---- Yes: tap the chip, the gold ring, the page's “Yes.” ----
    const yesChip = one(askCard, '[data-choice="Yes"]');
    util.tap(tl, yesChip, B.yes[0]);
    const yesRing = one(yesChip, '[data-choice-ring]');
    if (yesRing) tl.fromTo(yesRing, { opacity: 0 }, { opacity: 1, duration: 0.008 }, B.yes[0] + 0.012);
    lightWords(section.querySelector('[data-co-yes]'), B.yes[0] + 0.014, 0.012, 0.25);

    // ---- Answer: it replaces the question in the same slot and types in ----
    const ansSpan = span(B.answer);
    if (ans) tl.fromTo(ans, { opacity: 0 }, { opacity: 1, duration: ansSpan * 0.25, immediateRender: false }, B.answer[0]);
    if (ask) tl.to(ask, { opacity: 0, duration: ansSpan * 0.25 }, B.answer[0]);
    typeIn(one(ans, '[data-snippet-text]'), B.answer[0] + ansSpan * 0.2, ansSpan * 0.6);
    lightWords(section.querySelector('[data-co-reply="answer"]'), B.answer[0] + ansSpan * 0.2, ansSpan * 0.6, 0.2);

    // The timer has stopped (the answer layer's timer is fixed, so the idle tick is off from
    // here): a 1px gold rule sweeps under it.
    const stopped = one(ans, '[data-timer]');
    if (stopped) {
      const rule = document.createElement('i');
      rule.className = 'co-underline';
      rule.setAttribute('aria-hidden', 'true');
      const pos = stopped.style.position;
      stopped.style.position = 'relative';
      stopped.appendChild(rule);
      undo.push(() => {
        rule.remove();
        stopped.style.position = pos;
      });
      tl.fromTo(rule, { scaleX: 0 }, { scaleX: 1, duration: ansSpan * 0.4, ease: 'power2.inOut' }, B.answer[1] - ansSpan * 0.45);
    }

    // ---- Dismiss: the buttons fade in turn, then the card drops away like iOS ----
    const card = one(ans, '[data-la]');
    const btns = all(ans, '[data-strip] [data-row], [data-break-btn]');
    const disSpan = span(B.dismiss);
    if (btns.length) tl.to(btns, { opacity: 0, duration: disSpan * 0.25, stagger: disSpan * 0.08, ease: 'power1.in' }, B.dismiss[0]);
    if (card) tl.to(card, { scale: 0.98, y: 16, opacity: 0, duration: disSpan * 0.45, ease: 'power2.in' }, B.dismiss[0] + disSpan * 0.45);
    set(ans, B.dismiss[1], { opacity: 0 });
    set(quiet, B.dismiss[1], { opacity: 1 });

    // ---- Lights up ----
    const light = document.querySelector<HTMLElement>('[data-tint-light]');
    const lightSpan = span(B.lights);
    if (light) tl.fromTo(light, { opacity: 0 }, { opacity: 1, duration: lightSpan, ease: 'power1.inOut', immediateRender: false }, B.lights[0]);
    if (rim) tl.to(rim, { opacity: 0, duration: lightSpan * 0.75 }, B.lights[0] + lightSpan * 0.1);
    tl.set(section, { attr: { 'data-theme': 'light' } }, B.theme);
    // Once the light layer is up, the section paints the same light itself (so the page reads
    // as light to anything that looks at the section, like a contrast checker).
    section.dataset.coLit = 'no';
    undo.push(() => delete section.dataset.coLit);
    tl.set(section, { attr: { 'data-co-lit': 'yes' } }, B.lights[1]);

    if (isDesk) desk();
    else mobile();

    return () => {
      for (const fn of undo.reverse()) fn();
    };

    // =========================================================================
    function desk() {
      const D = DESK;
      const copy = section.querySelector<HTMLElement>('[data-co-copy]');
      const copySlot = section.querySelector<HTMLElement>('[data-co-copyslot]');
      const block = section.querySelector<HTMLElement>('[data-co-paperblock]');
      const slot = section.querySelector<HTMLElement>('[data-co-slot]');
      const fitBox = section.querySelector<HTMLElement>('[data-co-fitbox]');
      const fit = section.querySelector<HTMLElement>('[data-co-fit]');
      const paper = section.querySelector<HTMLElement>('[data-paper]');
      const frame = ctx.frame;

      // Stage the light part in the sticky frame: the copy in columns 1–5, the paper in 1–7.
      const move = (el: HTMLElement | null, to: HTMLElement | null) => {
        if (!el?.parentNode || !to) return;
        const parent = el.parentNode;
        const next = el.nextSibling;
        to.appendChild(el);
        undo.push(() => parent.insertBefore(el, next));
      };
      move(copy, copySlot);
      move(block, slot);
      section.classList.add('co-staged');
      undo.push(() => section.classList.remove('co-staged'));

      // The 720px card scaled to fit columns 1–7 and the frame's height.
      const fitPaper = () => {
        if (!fit || !fitBox || !slot || !block) return;
        gsap.set(fit, { scale: 1 });
        const paperH = fit.offsetHeight;
        const chrome = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--chrome-h')) || 59;
        const room = (frame?.clientHeight ?? innerHeight) - chrome;
        const others = block.offsetHeight - fitBox.offsetHeight;
        const s = Math.min(1, slot.clientWidth / CARD_W, Math.max(0.4, (room - others - 72) / paperH));
        gsap.set(fit, { scale: s, transformOrigin: '0 0' });
        fitBox.style.height = `${(paperH * s).toFixed(1)}px`;
        fitBox.style.width = `${(CARD_W * s).toFixed(1)}px`;
        fitBox.dataset.scale = s.toFixed(4);
      };
      fitPaper();
      ScrollTrigger.addEventListener('refreshInit', fitPaper);
      undo.push(() => {
        ScrollTrigger.removeEventListener('refreshInit', fitPaper);
        if (fit) gsap.set(fit, { clearProps: 'transform' });
        if (fitBox) {
          fitBox.style.height = '';
          fitBox.style.width = '';
          delete fitBox.dataset.scale;
        }
      });

      // ---- The report copy takes over columns 1–5, holds, and makes way for the paper ----
      if (copy) {
        tl.fromTo(copy, { opacity: 0, y: 32 }, { opacity: 1, y: 0, duration: span(D.copyIn), ease: 'power2.out' }, D.copyIn[0]);
        tl.to(copy, { opacity: 0, y: -24, duration: span(D.copyOut), ease: 'power1.in' }, D.copyOut[0]);
      }

      // ---- Unlock to the Report tab, tap This week ----
      const uSpan = span(D.unlock);
      set(report, D.unlock[0], { opacity: 1 });
      if (report) tl.fromTo(report, { scale: 0.94 }, { scale: 1, duration: uSpan * 0.5, ease: 'power2.out', immediateRender: false }, D.unlock[0] + uSpan * 0.05);
      if (quiet) tl.to(quiet, { yPercent: -100, duration: uSpan * 0.45, ease: 'power2.in' }, D.unlock[0]);
      util.sheen(tl, D.unlock[0] + uSpan * 0.1);
      util.tap(tl, one(report, '[data-range-chip="this-week"]'), D.unlock[1] - 0.045);

      // ---- The phone steps right ----
      const liftSpan = span(D.lift);
      if (phone) tl.to(phone, { xPercent: 8, scale: 0.9, duration: liftSpan, ease: 'power2.inOut' }, D.lift[0]);

      // ---- The paper lifts out of the preview (FLIP, measured lazily and scroll-independent) ----
      const thumb = one(report, '[data-paper-thumb]');
      const screenEl = thumb?.closest<HTMLElement>('.screen') ?? null;
      let frac = { x: 0.04, y: 0.5, w: 0.85 };
      const measureThumb = () => {
        if (!thumb || !screenEl) return;
        const sr = screenEl.getBoundingClientRect();
        const r = thumb.getBoundingClientRect();
        // Only trust a measurement taken while the screen is upright and unscaled.
        if (sr.width > 0 && Math.abs(sr.width - screenEl.offsetWidth) < 0.5) frac = { x: (r.left - sr.left) / sr.width, y: (r.top - sr.top) / sr.width, w: r.width / sr.width };
      };
      measureThumb();
      let from = { x: 0, y: 0, scale: 0.5 };
      const flip = () => {
        measureThumb();
        const stageSlot = ctx.stage?.el.querySelector<HTMLElement>('.stage-slot') ?? null;
        if (!stageSlot || !fitBox || !frame) return from;
        // The stage phone at rest: its slot is never transformed.
        const p = stageSlot.getBoundingClientRect();
        const k = p.width * INSET;
        const sw = p.width - 2 * k;
        const s = Number(fitBox.dataset.scale ?? '1');
        const fr = frame.getBoundingClientRect();
        const box = fitBox.getBoundingClientRect();
        // While the section plays, the frame is sticky at the viewport's top-left.
        const left = box.left - fr.left;
        const top = box.top - fr.top;
        from = {
          x: (p.left + k + frac.x * sw - left) / s,
          y: (p.top + k + frac.y * sw - top) / s,
          scale: (frac.w * sw) / (CARD_W * s),
        };
        return from;
      };
      if (paper) {
        const shadow = one(paper, '[data-paper-shadow]');
        tl.fromTo(
          paper,
          { x: () => flip().x, y: () => from.y, scale: () => from.scale, rotation: -3 },
          { x: 0, y: 0, scale: 1, rotation: -1, duration: liftSpan, ease: 'power3.inOut' },
          D.lift[0],
        );
        tl.fromTo(paper, { opacity: 0 }, { opacity: 1, duration: liftSpan * 0.12, ease: 'none' }, D.lift[0]);
        // The preview dims as its sheet lifts off, and comes back once the sheet is clear.
        if (thumb) {
          tl.to(thumb, { opacity: 0.3, duration: liftSpan * 0.15, ease: 'power1.out' }, D.lift[0]);
          tl.to(thumb, { opacity: 1, duration: liftSpan * 0.4, ease: 'power1.inOut' }, D.lift[0] + liftSpan * 0.55);
        }
        if (shadow) tl.fromTo(shadow, { opacity: 0 }, { opacity: 1, duration: liftSpan * 0.8 }, D.lift[0] + liftSpan * 0.2);

        // ---- Print: rows top to bottom, Friday last with a gold flash ----
        const rows = all(paper, 'tr[data-day]');
        const each = span(D.print) / Math.max(rows.length, 1);
        rows.forEach((tr, i) => {
          tl.fromTo(tr, { clipPath: 'inset(0% 0% 100% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)', duration: each * 0.8, ease: 'power1.inOut' }, D.print[0] + i * each);
        });
        const flashes = all(paper, '[data-cell="fri-trees"] [data-flash], [data-cell="fri-hours"] [data-flash]');
        if (flashes.length) {
          const fAt = D.print[1] - each * 0.3;
          gsap.set(flashes, { opacity: 0 });
          tl.to(flashes, { opacity: 1, duration: 0.006 }, fAt);
          tl.to(flashes, { opacity: 0, duration: 0.03, ease: 'power1.in' }, fAt + 0.012);
        }
        const rule = one(paper, '[data-totals-rule]');
        const totals = one(paper, '[data-totals]');
        const tSpan = span(D.totals);
        if (rule) tl.fromTo(rule, { scaleX: 0 }, { scaleX: 1, duration: tSpan * 0.6, ease: 'power2.inOut' }, D.totals[0]);
        if (totals) tl.fromTo(totals, { opacity: 0 }, { opacity: 1, duration: tSpan * 0.5 }, D.totals[0] + tSpan * 0.4);
      }

      // ---- The annotation: the leader draws down to the band, then the label slides in ----
      const aSpan = span(D.annotate);
      const lead = section.querySelector('[data-co-note-line]');
      const label = section.querySelector('[data-co-note-label]');
      if (lead) tl.fromTo(lead, { scaleY: 0 }, { scaleY: 1, duration: aSpan * 0.4, ease: 'power2.inOut' }, D.annotate[0]);
      if (label) tl.fromTo(label, { opacity: 0, x: 8 }, { opacity: 1, x: 0, duration: aSpan * 0.6, ease: 'power2.out' }, D.annotate[0] + aSpan * 0.4);

      // ---- Export PDF, then CSV: taps in the phone, chips pop under the paper ----
      const eSpan = span(D.exports);
      const pop = (chip: El, at: number) => {
        if (chip) tl.fromTo(chip, { opacity: 0, scale: 0.9 }, { opacity: 1, scale: 1, duration: eSpan * 0.3, ease: 'back.out(1.6)' }, at);
      };
      util.tap(tl, one(report, '[data-export="pdf"]'), D.exports[0]);
      pop(section.querySelector('[data-co-chip="pdf"]'), D.exports[0] + eSpan * 0.22);
      util.tap(tl, one(report, '[data-export="csv"]'), D.exports[0] + eSpan * 0.5);
      pop(section.querySelector('[data-co-chip="csv"]'), D.exports[0] + eSpan * 0.72);

      // ---- Rest: the phone settles for the next chapter ----
      if (phone) tl.to(phone, { xPercent: 0, scale: 1, duration: span(D.rest), ease: 'power2.inOut' }, D.rest[0]);
    }

    // =========================================================================
    function mobile() {
      // The light part is in flow after the track: each piece rises in as it enters.
      const after = section.querySelector('[data-co-after]');
      const rise = (els: Element[]) => {
        for (const el of els) {
          gsap.fromTo(
            el,
            { opacity: 0, y: 8 },
            { opacity: 1, y: 0, duration: 0.5, ease: 'power2.out', scrollTrigger: { trigger: el, start: 'top 85%', toggleActions: 'play none none none' } },
          );
        }
      };
      rise(all(after, '.co-copy > *'));
      rise(all(after, '[data-co-report], [data-co-note], [data-paper-band], tr[data-day], .tc-total, .co-exports'));
    }
  },
  { dayStart: FROM },
);

