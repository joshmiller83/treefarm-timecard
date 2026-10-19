/**
 * SCENE · PACE (3:40 PM, the Clock tab). Spec:
 *   jq '.sections[] | select(.id=="pace") | .animation' docs/landing/brief.json
 * Numbers, words and beats: src/sections/pace/pace.ts (unit-tested against the ledger).
 *
 *   [0, .10]   time-lapse 3:00 → 3:40 on the lock screen: the Live Activity timer spins to
 *              7:39:00, the trees roll 240 → 260 and the row buttons step to 39 · 40 · 41,
 *              each at the minute Alex marks the row
 *   [.10, .18] unlock: the lock layer slides up, the Clock tab settles from .94
 *   [.19, .29] the tab scrolls to the pace card and parks it under the toolbar
 *   .30 .38 .46  one page tile at a time lights (triggered): its rule draws, it rises in, its
 *              digits roll up from blank, and the matching pace row on the phone draws its
 *              gold rule
 *   [.55, .65] on to Hours & pay; the week's bars grow from the baseline, Friday last, in gold
 *   .77 .785   a tap on the eye-slash 'Show pay'; the masked pay answers with a short 'no' (it
 *              stays hidden on this page) as the small print says why
 *   [.88, .99] back to the top, and the lock screen returns: the phone ends at rest on it
 *
 * Scrubbed (ctx.tl) except the tiles lighting and the bars: short time-based pieces that are
 * level-triggered from the scrubbed playhead (on past their mark, off before it). They follow
 * every update, and snap to their state on build and on every ScrollTrigger refresh, which
 * sets the playhead without update events (a reload or restored scroll mid-section, a deep
 * link, a breakpoint rebuild). No pins: SectionShell's sticky frame holds the phone.
 */
import { registerScene } from '../scene.ts';
import { FIELD_TREES, fieldShapedAt, fmtCount, treesAt } from '../../data/ledger.ts';
import { setOdometer } from '../odometer.ts';
import { stripStep, stripWidth } from '../../components/system/lockscreen/activity.ts';
import { PACE_AT, PACE_FROM, ROLL_REST, beatsFor, lapseEvents, leadRows, litAt, rollStops, scrollStops } from '../../sections/pace/pace.ts';

const CLOCK = '[data-screen="clock-1540"]';
const LOCK = '[data-screen="lock-1540-activity"]';
/** One row step of the Live Activity strip, in percent of the strip (the track's own width). */
const STEP_PCT = (stripStep / stripWidth) * 100;

registerScene(
  'pace',
  (ctx) => {
    const { tl, day, util, gsap, q, q1, section, isDesk, SplitText } = ctx;
    const undo: Array<() => void> = [];
    const BEATS = beatsFor(isDesk);
    // Phone hooks are found by their layer's unique state id, wherever the stage has the
    // screens right now (ctx.q1 can miss them while the stage swaps two sections' screens).
    const $ = <T extends Element = HTMLElement>(sel: string) => document.querySelector<T>(sel) ?? q1<T>(sel);
    const $$ = <T extends Element = HTMLElement>(sel: string) => {
      const all = Array.from(document.querySelectorAll<T>(sel));
      return all.length ? all : q<T>(sel);
    };
    const span = (w: readonly number[]) => w[1]! - w[0]!;

    const clockLayer = $(CLOCK);
    const lockLayer = $(LOCK);

    // ---- The day: 3:00 → 3:40 over the time-lapse, then it holds at 3:40 ----
    day.to(tl, PACE_AT, BEATS.lapse[0], BEATS.lapse[1], PACE_FROM);

    // ---- Layers: the lock screen covers the Clock tab at the start ----
    if (lockLayer) gsap.set(lockLayer, { opacity: 1, yPercent: 0 });
    if (clockLayer) gsap.set(clockLayer, { opacity: 1, scale: 0.94, transformOrigin: '50% 50%' });

    // ---- [0, .1] The time-lapse on the Live Activity ----
    const events = lapseEvents();
    const track = $(`${LOCK} [data-strip-track]`);
    const first = track?.querySelector<HTMLElement>('[data-row]');
    if (track && first) {
      // The final card starts at row 39; give the strip the rows it shows at 3:00 (37, 38).
      for (const row of [...leadRows()].reverse()) {
        const b = first.cloneNode(true) as HTMLElement;
        b.dataset.row = String(row);
        b.textContent = `Row ${row}`;
        track.insertBefore(b, track.firstChild);
        undo.push(() => b.remove());
      }
      gsap.set(track, { xPercent: 0 });
      events.forEach((e, i) => {
        tl.fromTo(
          track,
          { xPercent: -i * STEP_PCT },
          { xPercent: -(i + 1) * STEP_PCT, duration: 0.012, ease: 'power2.inOut', immediateRender: false },
          e.p,
        );
      });
    }
    const laTrees = $(`${LOCK} [data-trees]`);
    if (laTrees && events.length) {
      // Start the count at 3:00 (util.odometer only does that the first time it sees the
      // element, and a breakpoint change rebuilds the scene); put 3:40 back on revert.
      const final = laTrees.dataset.odoText ?? fmtCount(treesAt(PACE_AT));
      setOdometer(laTrees, fmtCount(events[0]!.before));
      undo.push(() => setOdometer(laTrees, final));
      for (const e of events) util.odometer(tl, laTrees, e.before, e.after, e.p, 0.01);
    }
    const fill = $(`${LOCK} [data-fieldbar]`);
    if (fill && events.length) {
      const pct = (min: number) => fieldShapedAt(min) / FIELD_TREES;
      gsap.set(fill, { scaleX: pct(PACE_FROM), transformOrigin: '0% 50%' });
      for (const e of events) {
        tl.fromTo(fill, { scaleX: pct(e.at - 1e-6) }, { scaleX: pct(e.at), duration: 0.012, ease: 'power2.out', immediateRender: false }, e.p);
      }
    }

    // ---- [.1, .18] Unlock ----
    const [u0] = BEATS.unlock;
    const uDur = span(BEATS.unlock);
    if (lockLayer) tl.fromTo(lockLayer, { yPercent: 0 }, { yPercent: -100, duration: uDur, ease: 'power2.inOut', immediateRender: false }, u0);
    if (clockLayer) tl.fromTo(clockLayer, { scale: 0.94 }, { scale: 1, duration: uDur, ease: 'power2.out', immediateRender: false }, u0 + uDur * 0.15);
    util.sheen(tl, u0 + uDur * 0.3, 0.05);

    // ---- In-phone scroll: top → pace card → the end → top ----
    const scroll = $(`${CLOCK} [data-scroll-layer]`);
    const viewport = $(`${CLOCK} [data-app-scroll]`);
    const paceCard = $(`${CLOCK} [data-pace-card]`);
    if (scroll && viewport && paceCard) {
      const stops = () =>
        scrollStops({ layerH: scroll.offsetHeight, screenH: viewport.clientHeight, paceTop: paceCard.offsetTop, pt: viewport.clientWidth / 393 });
      gsap.set(scroll, { yPercent: 0 });
      tl.fromTo(scroll, { yPercent: 0 }, { yPercent: () => stops().pacePct, duration: span(BEATS.toPace), ease: 'power2.inOut', immediateRender: false }, BEATS.toPace[0]);
      tl.fromTo(
        scroll,
        { yPercent: () => stops().pacePct },
        { yPercent: () => stops().endPct, duration: span(BEATS.toHours), ease: 'power2.inOut', immediateRender: false },
        BEATS.toHours[0],
      );
      tl.fromTo(scroll, { yPercent: () => stops().endPct }, { yPercent: 0, duration: span(BEATS.back), ease: 'power2.inOut', immediateRender: false }, BEATS.back[0]);
    }

    // ---- The page tiles, each lit with its phone row's gold rule ----
    // Each tile lights as one short, time-based piece (on once the scrubbed playhead is past
    // its mark, reversed before it), so the rule, the rise and the rolling digits always
    // finish together however fast or slowly the page is scrolled.
    const tiles = q<HTMLElement>('[data-tile]');
    const lights: GSAPTimeline[] = [];
    for (const tile of tiles) {
      const face = tile.querySelector('.pace-tile-face');
      const line = tile.querySelector('[data-tile-line]');
      const rules = [tile.querySelector('[data-tile-rule]'), $(`${CLOCK} [data-pace-row="${tile.dataset.row}"] [data-pace-rule]`)].filter(
        (r): r is Element => !!r,
      );
      const roll = tile.querySelector<HTMLElement>('[data-roll]');
      const cols = roll ? Array.from(roll.querySelectorAll<HTMLElement>('.roll-col')) : [];
      const stops = rollStops(roll?.dataset.rollText ?? '');
      const seps = roll ? Array.from(roll.querySelectorAll<HTMLElement>('.roll-s')) : [];
      const t = gsap.timeline({ paused: true, defaults: { ease: 'power3.out' } });
      if (line) t.fromTo(line, { scaleX: 0 }, { scaleX: 1, duration: 0.5, ease: 'power2.inOut' }, 0);
      // The tile rises in as it lights, its number rolling up from blank (no ghost zeros that
      // would contradict the phone): a label never waits beside an empty number slot.
      if (face) t.fromTo(face, { opacity: 0, y: isDesk ? 16 : 8 }, { opacity: 1, y: 0, duration: 0.5 }, 0.06);
      // Every column spins from its blank rest to its digit in the second cycle: no counting.
      if (cols.length) t.fromTo(cols, { y: 0, yPercent: ROLL_REST }, { y: 0, yPercent: (k: number) => stops[k] ?? 0, duration: 0.8, stagger: 0.07 }, 0.06);
      // The colon comes in with the digits around it.
      if (seps.length) t.fromTo(seps, { opacity: 0 }, { opacity: 1, duration: 0.3, ease: 'power2.out' }, 0.2);
      if (rules.length) t.fromTo(rules, { scaleY: 0 }, { scaleY: 1, duration: 0.4, ease: 'power2.out' }, 0.16);
      lights.push(t);
    }

    // Below 900px the tiles share one card: it comes in with the first tile, so it never
    // scrolls up empty.
    const statsCard = isDesk ? null : q1<HTMLElement>('.pace-stats');
    if (statsCard) tl.fromTo(statsCard, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.035, ease: 'power1.out' }, BEATS.tiles[0] - 0.035);

    // ---- Hours & pay: the bars grow from the baseline (triggered), Friday last ----
    const bars = $$(`${CLOCK} [data-hours-card] [data-bar]`);
    const grow = gsap.timeline({ paused: true });
    if (bars.length) grow.fromTo(bars, { scaleY: 0, transformOrigin: '50% 100%' }, { scaleY: 1, duration: 0.55, ease: 'power3.out', stagger: 0.06 });

    // Triggered pieces are level-triggered from the scrubbed playhead: on past their mark
    // (play), off before it (reverse). snap = jump straight to that state (no animation).
    const marks = [...BEATS.tiles.slice(0, lights.length), BEATS.bars];
    const players = [...lights, grow];
    const sync = (snap = false) => {
      const on = litAt(tl.progress(), marks);
      players.forEach((pl, i) => {
        if (snap) {
          pl.pause().reversed(false).progress(on[i] ? 1 : 0);
        } else if (on[i]) {
          if (pl.reversed() || pl.progress() < 1) void pl.play();
        } else if (!pl.reversed() && pl.progress() > 0) {
          void pl.reverse();
        }
      });
    };
    tl.eventCallback('onUpdate', () => sync());
    // A refresh sets the playhead with its events suppressed (and a reload or deep link lands
    // mid-section that way), so snap after every refresh and once the scene is in place.
    const onRefresh = () => sync(true);
    ctx.ScrollTrigger.addEventListener('refresh', onRefresh);
    const raf = requestAnimationFrame(() => sync(true));
    undo.push(() => {
      cancelAnimationFrame(raf);
      tl.eventCallback('onUpdate', null);
      ctx.ScrollTrigger.removeEventListener('refresh', onRefresh);
    });

    // ---- The pay toggle: a tap, the masked pay answers 'no' (pay stays hidden here), the small print ----
    const toggle = $(`${CLOCK} [data-pay-toggle]`);
    // No haptic phone shake: the dots' own 'no' is the response.
    util.tap(tl, toggle, BEATS.tap, { dur: BEATS.tapDur, shake: false });
    const pay = $(`${CLOCK} [data-pay]`);
    if (pay) {
      // A short horizontal 'no' in phone points (like a refused passcode), not a pulse that
      // reads as a button that did nothing.
      const pt = () => (viewport?.clientWidth ?? 393) / 393;
      const nope = [-6, 6, -4, 0];
      const step = [0.008, 0.012, 0.01, 0.01]; // .04 in all
      tl.to(pay, { keyframes: nope.map((v, i) => ({ x: () => v * pt(), duration: step[i]!, ease: 'sine.inOut' })) }, BEATS.nope);
    }
    const small = q1('[data-small]');
    if (small) {
      gsap.set(small, { opacity: 0, y: 8 });
      tl.fromTo(small, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: span(BEATS.small), ease: 'power2.out', immediateRender: false }, BEATS.small[0]);
    }

    // ---- Desktop: the bullets come in as the copy reaches them ----
    if (isDesk) {
      q('[data-bullet]').forEach((li, i) => {
        const at = BEATS.bullets[i] ?? BEATS.bullets.at(-1)!;
        gsap.set(li, { opacity: 0, y: 12 });
        tl.fromTo(li, { opacity: 0, y: 12 }, { opacity: 1, y: 0, duration: 0.05, ease: 'power2.out', immediateRender: false }, at);
      });
    }

    // ---- [.88, 1] The lock screen returns ----
    const rDur = span(BEATS.relock);
    if (lockLayer) tl.fromTo(lockLayer, { yPercent: -100 }, { yPercent: 0, duration: rDur, ease: 'power2.inOut', immediateRender: false }, BEATS.relock[0]);
    if (clockLayer) tl.fromTo(clockLayer, { scale: 1 }, { scale: 0.96, duration: rDur, ease: 'power2.in', immediateRender: false }, BEATS.relock[0]);
    util.sheen(tl, BEATS.relock[0] + rDur * 0.4, 0.04);

    // ---- The headline: lines mask up once, at 'top 75%' (not scrubbed) ----
    const h = section.querySelector<HTMLElement>(`#${section.id}-h`);
    if (h && h.getBoundingClientRect().top > innerHeight * 0.75) {
      const split = SplitText.create(h, { type: 'lines', mask: 'lines' });
      gsap.set(split.lines, { yPercent: 100 });
      ctx.trigger({
        trigger: h,
        start: 'top 75%',
        once: true,
        onEnter: () => gsap.to(split.lines, { yPercent: 0, duration: 0.7, stagger: 0.08, ease: 'power3.out' }),
      });
      undo.push(() => split.revert());
    }

    return () => undo.forEach((f) => f());
  },
  { dayStart: PACE_FROM },
);
