/**
 * SCENE: LOCK SCREEN · 2:14 PM (brief: .sections[lock-screen].animation; progress units 0–1).
 *
 *   [0, .08]    2:01 → 2:14: the timer runs 6:14 → 6:27, trees 212 → 220, the buttons step
 *               from Row 35 to Row 36 as row 35 is finished (2:12), the sheen sweeps
 *   [.08, .2]   the phone zooms (1.7 desktop, 1.4 mobile) about the Live Activity's centre;
 *               the lock screen dims to .45 under the card
 *   [.2, .45]   desktop: callouts 1–4 and 6 draw in .05 slots, the ghost Clock out with the
 *               sixth, its strike last. Mobile: pins 1–4 and 6 pop and pulse while card 1's
 *               notes light up
 *   [.5, .62]   the tap on Row 36: the strip moves one step, trees 220 → 230, the field bar
 *               creeps on, 'Row 36 marked · Undo' rises in; then callout 5 (pin 5) points at it
 *   [.62, .7]   the callouts fade [.62, .64], then the zoom back; the dim lifts
 *   [.7, .85]   unlock to the home screen, 2:14 → 2:16. On phones (and small stage phones)
 *               the phone zooms on the island. The island goes rest → compact (held to .78)
 *               → expanded (held to .858)
 *   [.85, .95]  the island collapses, the close-up lets go, the lock screen returns; on
 *               desktop beat 3, ControlsCard and the footnote fade up and the Action button
 *               glows twice
 *   [.95, 1]    rest on the lock screen in the tapped state
 *
 * Cues, geometry and copy come from src/sections/lock-screen/model.ts; numbers from the ledger.
 * Every hook is optional: a real capture swapped in for a layer turns its part into a still.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';
import {
  BEFORE,
  calloutWindows,
  CALLOUTS,
  CUE,
  deskLayout,
  ISLAND_AT,
  ISLAND_ORIGIN,
  islandZoom,
  mobZoom,
  ORIGIN,
  T,
  TAPPED,
  WORKING,
  type DeskLayout,
  type LabelSizes,
} from '../../sections/lock-screen/model.ts';

const ISLAND = { rest: [126, 37, 18.5], compact: [250, 37, 18.5], expanded: [371, 160, 44] } as const;
type Target = Element | null | undefined;
type Vars = Record<string, unknown>;

registerScene(
  'lock-screen',
  (ctx) => {
    const { tl, day, util, gsap, q, section, isDesk, stage, ScrollTrigger, SplitText } = ctx;
    const phone = ctx.phone;
    const cleanups: Array<() => void> = [];

    // Tweens that skip a missing target (no GSAP warnings, no failed build).
    const ok = (t: Target | Target[]): t is Element | Element[] => (Array.isArray(t) ? t.some(Boolean) : !!t);
    const list = (t: Target | Target[]) => (Array.isArray(t) ? (t.filter(Boolean) as Element[]) : (t as Element));
    const fromTo = (t: Target | Target[], from: Vars, to: Vars, at: number) => ok(t) && tl.fromTo(list(t), from, to, at);
    const to = (t: Target | Target[], vars: Vars, at: number) => ok(t) && tl.to(list(t), vars, at);
    const set = (t: Target | Target[], vars: Vars, at?: number) => ok(t) && (at === undefined ? gsap.set(list(t), vars) : tl.set(list(t), vars, at));

    // Layers by their page-unique state ids: the section's [data-screens] may sit in the stage
    // (beside another section's for a moment while the stage crossfades).
    const layer = (id: string) =>
      section.querySelector<HTMLElement>(`[data-screen="${id}"]`) ?? document.querySelector<HTMLElement>(`[data-screen="${id}"]`);
    const pre = layer('lock-1414-activity');
    const tapped = layer('lock-1414-tapped');
    const home = layer('home-1416-island-compact');
    const screens = tapped?.parentElement ?? ctx.screens;
    const inPre = (sel: string) => pre?.querySelector<HTMLElement>(sel) ?? null;
    const inTap = (sel: string) => tapped?.querySelector<HTMLElement>(sel) ?? null;
    const inHome = (sel: string) => home?.querySelector<HTMLElement>(sel) ?? null;
    const useCallouts = isDesk && !!stage;

    // ---- The headline: lines mask up once, at 'top 75%' (not scrubbed) ----
    const h2 = section.querySelector<HTMLElement>('#lock-screen-h');
    if (h2) {
      const split = SplitText.create(h2, { type: 'lines', mask: 'lines', aria: 'auto' });
      gsap.from(split.lines, {
        yPercent: 100,
        duration: 0.7,
        stagger: 0.08,
        ease: 'power3.out',
        scrollTrigger: { trigger: h2, start: 'top 75%', once: true },
      });
    }

    // ---- Layers at progress 0: the 2:01 lock screen ----
    util.show(screens, 'lock-1414-activity');

    // The strips move by --ls-shift, in whole button steps (LockScreen.astro turns it into a
    // CSS translate of the button width plus the gap), so no pixel value is ever cached and a
    // resize can't leave a strip half a step out.

    // ---- Zoom geometry (desktop: around the stage phone; mobile: the section phone in place) ----
    let L: DeskLayout | null = null;
    const slot = stage?.phone.parentElement ?? null;
    const callRoot = section.querySelector<HTMLElement>('[data-ls-callouts]');
    const header = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--chrome-h')) || 59;
    /** A wrapped pill hugs its longest line (CSS leaves it at its max-width). */
    const hug = (pill: HTMLElement) => {
      pill.style.width = '';
      const walker = document.createTreeWalker(pill, NodeFilter.SHOW_TEXT);
      const range = document.createRange();
      let lines = 0;
      let lo = Infinity;
      let hi = -Infinity;
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        range.selectNodeContents(n);
        for (const r of Array.from(range.getClientRects())) {
          if (r.width < 1) continue;
          lines += 1;
          lo = Math.min(lo, r.left);
          hi = Math.max(hi, r.right);
        }
      }
      if (lines < 2 || !Number.isFinite(lo)) return;
      const cs = getComputedStyle(pill);
      const pad = ['paddingLeft', 'paddingRight', 'borderLeftWidth', 'borderRightWidth'].reduce((t, k) => t + (parseFloat(cs[k as 'paddingLeft']) || 0), 0);
      pill.style.width = `${Math.ceil(hi - lo + pad + 1)}px`;
    };
    const layout = () => {
      if (!useCallouts || !slot || !callRoot) return;
      const r = slot.getBoundingClientRect();
      const geo = {
        phone: { left: r.left, top: r.top, width: r.width, height: r.height },
        viewport: { width: ctx.frame?.getBoundingClientRect().width || innerWidth, height: innerHeight, top: header() },
      };
      // Pass 1: the label columns' widths decide the wrapping, and so each label's height.
      const first = deskLayout(geo);
      const sizes: LabelSizes = {};
      for (const c of first.callouts) {
        const li = callRoot.querySelector<HTMLElement>(`[data-callout="${c.n}"]`);
        const pill = li?.querySelector<HTMLElement>('.pill');
        li?.style.setProperty('--max', Math.max(160, c.label.maxWidth).toFixed(0));
        if (pill) {
          pill.style.width = '';
          sizes[c.n] = pill.offsetHeight;
        }
      }
      // Pass 2: stack the measured labels clear of each other and of the ghost.
      L = deskLayout({ ...geo, sizes });
      for (const c of L.callouts) {
        const g = callRoot.querySelector(`[data-line-for="${c.n}"]`);
        g?.querySelector('[data-line]')?.setAttribute('d', c.path);
        const dot = g?.querySelector('[data-dot]');
        dot?.setAttribute('cx', c.dot.x.toFixed(1));
        dot?.setAttribute('cy', c.dot.y.toFixed(1));
        const li = callRoot.querySelector<HTMLElement>(`[data-callout="${c.n}"]`);
        li?.style.setProperty('--x', c.label.x.toFixed(1));
        li?.style.setProperty('--y', c.label.y.toFixed(1));
        const pill = li?.querySelector<HTMLElement>('.pill');
        if (pill) hug(pill);
      }
      const g = callRoot.querySelector<HTMLElement>('[data-ls-ghost-at]');
      g?.style.setProperty('--x', L.ghost.x.toFixed(1));
      g?.style.setProperty('--y', L.ghost.y.toFixed(1));
    };
    layout();
    if (useCallouts) {
      ScrollTrigger.addEventListener('refreshInit', layout);
      cleanups.push(() => ScrollTrigger.removeEventListener('refreshInit', layout));
    }
    const gutter = () => parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--gutter')) || 16;
    const phoneBox = () => ({ width: phone?.offsetWidth ?? 0, height: phone?.offsetHeight ?? 0 });
    const zoom = () => (useCallouts && L ? { scale: L.zoom, x: L.x, y: L.y } : mobZoom(phoneBox(), innerWidth, gutter()));
    // Mobile pins are drawn at 22px / zoom, so they land at 22px whatever the zoom.
    const pinRoot = inTap('[data-pins]');
    const pinZoom = () => {
      if (!useCallouts) pinRoot?.style.setProperty('--pin-zoom', zoom().scale.toFixed(3));
    };
    pinZoom();
    if (!useCallouts) {
      ScrollTrigger.addEventListener('refreshInit', pinZoom);
      cleanups.push(() => ScrollTrigger.removeEventListener('refreshInit', pinZoom));
    }
    // Mobile: the controls card hangs past the end of the track (it arrives after the island
    // card); the section's tail is as tall as the overhang, plus a gap, so it never covers the
    // field chapter's heading. Measured from layout offsets, so scrolling never changes it.
    const controlsCard = section.querySelector<HTMLElement>('.ls-controls-beat');
    const tail = () => {
      if (useCallouts || !controlsCard) return;
      const track = controlsCard.offsetParent as HTMLElement | null;
      if (!track) return;
      const over = controlsCard.offsetTop + controlsCard.offsetHeight - track.offsetHeight;
      section.style.setProperty('--ls-tail', `${Math.max(0, Math.ceil(over + 40))}px`);
    };
    if (!useCallouts) {
      tail();
      ScrollTrigger.addEventListener('refreshInit', tail);
      cleanups.push(() => {
        ScrollTrigger.removeEventListener('refreshInit', tail);
        section.style.removeProperty('--ls-tail');
      });
    }
    /** The island close-up: mobile, and stage phones too small to read the island at 1×. */
    const islandClose = () =>
      islandZoom({ phone: phoneBox(), viewportWidth: innerWidth, gutter: gutter(), desk: useCallouts, top: useCallouts ? undefined : 10 });

    // ---- [0, .08] 2:01 → 2:14 ----
    day.to(tl, MOMENTS.lockScreen, T.step[0], T.step[1], MOMENTS.status);
    util.sheen(tl, 0.012, 0.05);
    // Row 35's last eight trees land at 2:12 (≈ .068): trees, field bar and the buttons move on.
    util.odometer(tl, inPre('[data-trees]'), BEFORE.trees, WORKING.trees, 0.058, 0.014);
    fromTo(inPre('[data-fieldbar]'), { scaleX: BEFORE.fieldPct }, { scaleX: WORKING.fieldPct, duration: 0.016, ease: 'power2.out' }, 0.058);
    fromTo(inPre('[data-strip-track]'), { '--ls-shift': 1 }, { '--ls-shift': 0, duration: 0.018, ease: 'power2.inOut' }, 0.06);

    // The tapped layer takes over, identical at this instant (before the tap): Row 36 is in
    // (its strip one step back; the tap's tween below renders that from-state immediately).
    set(pre, { opacity: 0 }, T.step[1]);
    set(tapped, { opacity: 1 }, T.step[1]);
    const strip = inTap('[data-strip-track]');
    util.odometer(tl, inTap('[data-trees]'), WORKING.trees, TAPPED.trees, 0.54, 0.03);
    const bar = inTap('[data-fieldbar]');
    const undo = inTap('[data-undo]');
    const dim = inTap('[data-dim]');

    // ---- [.08, .2] zoom in ----
    if (phone) {
      set(phone, { transformOrigin: `${(ORIGIN.x * 100).toFixed(3)}% ${(ORIGIN.y * 100).toFixed(3)}%` }, T.zoomIn[0] - 0.0005);
      fromTo(
        phone,
        { scale: 1, x: 0, y: 0 },
        { scale: () => zoom().scale, x: () => zoom().x, y: () => zoom().y, duration: T.zoomIn[1] - T.zoomIn[0], ease: 'power2.inOut', immediateRender: false },
        T.zoomIn[0],
      );
    }
    fromTo(dim, { opacity: 0 }, { opacity: 0.45, duration: 0.1, ease: 'none', immediateRender: false }, T.zoomIn[0] + 0.01);
    // The headline steps aside as the zoomed phone reaches into the copy column (desktop) or
    // grows over the intro's last lines (mobile).
    if (useCallouts) to(ctx.beats[0], { opacity: 0, duration: 0.06, ease: 'power1.in' }, T.zoomIn[0] + 0.01);
    else to(ctx.beats[0], { opacity: 0, duration: 0.045, ease: 'power1.in' }, T.zoomIn[0] + 0.005);

    // ---- [.2, .45] callouts (desktop) or pins (mobile); 5 after the tap, at the Undo ----
    const win = calloutWindows();
    const lines = Array.from(callRoot?.querySelectorAll<SVGPathElement>('[data-line]') ?? []);
    const dots = Array.from(callRoot?.querySelectorAll<SVGCircleElement>('[data-dot]') ?? []);
    const labels = Array.from(callRoot?.querySelectorAll<HTMLElement>('[data-callout]') ?? []);
    const ghost = callRoot?.querySelector<HTMLElement>('[data-ls-ghost]') ?? null;
    const strike = ghost?.querySelector<HTMLElement>('[data-ls-strike]') ?? null;
    if (useCallouts) {
      set([...labels, ...dots, ghost], { opacity: 0 });
      set(lines, { strokeDasharray: 1, strokeDashoffset: 1 });
      set(strike, { scaleX: 0 });
      CALLOUTS.forEach((c, i) => {
        const [a, b] = win[c.n];
        const w = b - a;
        fromTo(dots[i], { opacity: 0, scale: 0, transformOrigin: '50% 50%' }, { opacity: 1, scale: 1, duration: w * 0.25, ease: 'back.out(2)', immediateRender: false }, a);
        util.callout(tl, { line: lines[i], label: labels[i], from: c.side === 'left' ? 'right' : 'left' }, a, w);
        if (c.n === 6) {
          fromTo(ghost, { opacity: 0, x: -8 }, { opacity: 1, x: 0, duration: w * 0.4, ease: 'power2.out', immediateRender: false }, a + w * 0.4);
          fromTo(strike, { scaleX: 0 }, { scaleX: 1, duration: w * 0.25, ease: 'power2.inOut', immediateRender: false }, b - w * 0.25);
        }
      });
    } else {
      const pins = Array.from(inTap('[data-pins]')?.querySelectorAll<HTMLElement>('[data-pin]') ?? []);
      const rules = q<HTMLElement>('[data-ls-notes] [data-note-rule]');
      const nums = q<HTMLElement>('[data-ls-notes] .ls-num');
      set(pins, { opacity: 0, scale: 0 });
      // Note 5 lights in the tap card, beside the Undo; in card 1 it waits its turn unlit.
      const tapNote = section.querySelector<HTMLElement>('[data-ls-tap-note]');
      const ruleFor = (n: number) => (n === 5 ? tapNote?.querySelector<HTMLElement>('[data-note-rule]') : rules[n - 1]);
      const numFor = (n: number) => (n === 5 ? tapNote?.querySelector<HTMLElement>('.ls-num') : nums[n - 1]);
      CALLOUTS.forEach((c, i) => {
        const [a, b] = win[c.n];
        const w = b - a;
        fromTo(pins[i], { opacity: 0, scale: 0 }, { opacity: 1, scale: 1, duration: w * 0.3, ease: 'back.out(2.2)', immediateRender: false }, a);
        to(pins[i], { keyframes: { scale: [1, 1.28, 1] }, duration: w * 0.45, ease: 'power1.inOut' }, a + w * 0.35);
        fromTo(ruleFor(c.n), { scaleY: 0 }, { scaleY: 1, duration: w * 0.25, ease: 'power2.out', immediateRender: false }, a);
        // Each rule hands over to the next; the last of card 1 stays until the card goes.
        if (c.n !== 6) to(ruleFor(c.n), { scaleY: 0, duration: w * 0.25, ease: 'power2.in' }, c.n === 5 ? T.zoomOut[0] : b);
        to(numFor(c.n), { keyframes: { scale: [1, 1.18, 1] }, duration: w * 0.45, ease: 'power1.inOut' }, a + w * 0.35);
      });
      to(rules[5], { scaleY: 0, duration: 0.012, ease: 'power2.in' }, 0.49);
      to(pins, { opacity: 0, duration: 0.03, stagger: 0.004, ease: 'power1.in' }, T.zoomOut[0]);

      // The caption slot: notes [.19, .5], the tap [.515, .66], the island [.69, .87].
      const card = (sel: string, a: number, b: number) => {
        const el = section.querySelector<HTMLElement>(sel);
        // autoAlpha: a card at 0 is visibility: hidden too, so it never takes a tap or a
        // screen reader's touch while it waits over the other chapters (it is position: fixed).
        fromTo(el, { autoAlpha: 0, y: 14 }, { autoAlpha: 1, y: 0, duration: 0.02, ease: 'power2.out', immediateRender: true }, a);
        to(el, { autoAlpha: 0, y: -10, duration: 0.018, ease: 'power1.in' }, b);
      };
      card('.ls-notes-beat', 0.185, 0.505);
      card('.ls-tap-beat', 0.52, 0.665);
      card('.ls-island-beat', 0.69, 0.87);
    }

    // ---- [.5, .62] the tap on Row 36 ----
    util.tap(tl, inTap(`[data-row="${TAPPED.undoRow}"]`), CUE.tap, { shake: false });
    // The 2px haptic shake, on top of the zoom (util.tap's own would reset x to 0).
    if (phone) [2, -2, 2, -2, 0].forEach((dx, i) => to(phone, { x: () => zoom().x + dx, duration: 0.008, ease: 'none' }, CUE.tap + i * 0.008));
    // The strip's only tween, and immediateRender: ScrollTrigger's refresh (on resize) reverts
    // and invalidates the timeline, then re-renders exactly these, so the step survives it.
    const [s0, s1] = CUE.strip;
    fromTo(strip, { '--ls-shift': 1 }, { '--ls-shift': 0, duration: s1 - s0, ease: 'power2.inOut', immediateRender: true }, s0);
    fromTo(bar, { scaleX: WORKING.fieldPct }, { scaleX: TAPPED.fieldPct, duration: 0.03, ease: 'power2.out' }, 0.54);
    const [u0, u1] = CUE.undo;
    fromTo(undo, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: u1 - u0, ease: 'power2.out' }, u0);

    // ---- [.62, .7] the callouts go, then the zoom back ----
    const [o0, o1] = CUE.calloutsOut;
    if (useCallouts) {
      // Right side first (6, 5, 3), then the left (4, 1, 2): all gone by .64.
      const order = [6, 5, 3, 4, 1, 2].map((n) => n - 1);
      const each = 0.001;
      to(ghost, { opacity: 0, duration: o1 - o0, ease: 'power1.in' }, o0);
      order.forEach((i, k) =>
        to([labels[i], lines[i], dots[i]], { opacity: 0, duration: o1 - o0 - each * (order.length - 1), ease: 'power1.in' }, o0 + k * each),
      );
    }
    if (phone) {
      const [z0, z1] = CUE.zoomOut;
      to(phone, { scale: 1, x: 0, y: 0, duration: z1 - z0, ease: 'power2.inOut' }, z0);
      set(phone, { transformOrigin: '50% 50%' }, z1);
    }
    to(dim, { opacity: 0, duration: 0.07, ease: 'none' }, T.zoomOut[0]);

    // Desktop: the island copy rises through the callouts' column unseen and fades in once the
    // phone is back at rest; the controls copy waits for the island to collapse.
    const islandBeat = section.querySelector('.ls-island-beat');
    const controlsBeat = section.querySelector('.ls-controls-beat');
    if (useCallouts) {
      fromTo(islandBeat, { opacity: 0 }, { opacity: 1, duration: 0.045, ease: 'power1.out' }, 0.665);
      const [b0, b1] = CUE.controls.beat;
      fromTo(controlsBeat, { opacity: 0 }, { opacity: 1, duration: b1 - b0, ease: 'power1.out' }, b0);
      // One message leads: the island line steps back as the controls arrive.
      to(islandBeat, { opacity: 0.45, duration: b1 - b0, ease: 'power1.inOut' }, b0);
    }

    // ---- [.7, .85] unlock, 2:14 → 2:16, the island ----
    day.to(tl, ISLAND_AT, T.unlock[0], T.unlock[1]);
    const island = inHome('[data-island]');
    const compact = inHome('[data-island-compact]');
    const expanded = inHome('[data-island-expanded]');
    if (island) {
      // The morph tweens three numbers (pt) that drive width, height and radius, so it holds
      // at any phone size; it is one absolutely positioned element with contain: layout.
      island.style.width = 'calc(var(--isl-w) * var(--isl-pt))';
      island.style.height = 'calc(var(--isl-h) * var(--isl-pt))';
      island.style.borderRadius = 'calc(var(--isl-r) * var(--isl-pt))';
      cleanups.push(() => {
        for (const p of ['width', 'height', 'border-radius', '--isl-w', '--isl-h', '--isl-r']) island.style.removeProperty(p);
      });
    }
    const size = (k: keyof typeof ISLAND) => ({ '--isl-w': ISLAND[k][0], '--isl-h': ISLAND[k][1], '--isl-r': ISLAND[k][2] });

    set(home, { opacity: 1 }, T.unlock[0]);
    fromTo(tapped, { yPercent: 0 }, { yPercent: -100, duration: 0.045, ease: 'power2.inOut', immediateRender: false }, T.unlock[0]);
    fromTo(home, { scale: 0.94 }, { scale: 1, duration: 0.05, ease: 'power2.out', immediateRender: false }, T.unlock[0] + 0.004);
    util.sheen(tl, T.unlock[0] + 0.01, 0.05);

    // Each morph does its geometry early in its window, then holds so the state can be read.
    const I = CUE.island;
    const span = (w: readonly [number, number]) => w[1] - w[0];

    // The close-up: the phone zooms about the island (a no-op on a large stage phone).
    if (phone) {
      set(phone, { transformOrigin: `${ISLAND_ORIGIN.x * 100}% ${(ISLAND_ORIGIN.y * 100).toFixed(3)}%` }, I.zoomIn[0] - 0.0005);
      fromTo(
        phone,
        { scale: 1, x: 0, y: 0 },
        { scale: () => islandClose().scale, y: () => islandClose().y, duration: span(I.zoomIn), ease: 'power2.inOut', immediateRender: false },
        I.zoomIn[0],
      );
    }

    // The first tween on each of these renders its from-state at once (immediateRender), the
    // rest island with no content, and ScrollTrigger re-renders exactly those after the revert
    // its refresh does on a resize, so the island is never left without a size.
    fromTo(island, size('rest'), { ...size('compact'), duration: span(I.compact.size), ease: 'power3.inOut', immediateRender: true }, I.compact.size[0]);
    fromTo(home, { '--island-yield': 0 }, { '--island-yield': 1, duration: span(I.compact.size), ease: 'power3.inOut', immediateRender: true }, I.compact.size[0]);
    fromTo(compact, { opacity: 0 }, { opacity: 1, duration: span(I.compact.content), ease: 'none', immediateRender: true }, I.compact.content[0]);

    to(island, { ...size('expanded'), duration: span(I.expanded.size), ease: 'power3.inOut' }, I.expanded.size[0]);
    to(home, { '--island-yield': 2, duration: span(I.expanded.size), ease: 'power3.inOut' }, I.expanded.size[0]);
    to(compact, { opacity: 0, duration: span(I.compact.out), ease: 'none' }, I.compact.out[0]);
    fromTo(expanded, { opacity: 0 }, { opacity: 1, duration: span(I.expanded.content), ease: 'none', immediateRender: true }, I.expanded.content[0]);

    // ---- [.85, .95] the island collapses, the lock screen returns, the controls ----
    to(expanded, { opacity: 0, duration: span(I.expanded.out), ease: 'none' }, I.expanded.out[0]);
    to(island, { ...size('rest'), duration: span(I.rest), ease: 'power3.inOut' }, I.rest[0]);
    to(home, { '--island-yield': 0, duration: span(I.rest), ease: 'power3.inOut' }, I.rest[0]);
    if (phone) {
      to(phone, { scale: 1, y: 0, duration: span(I.zoomOut), ease: 'power2.inOut' }, I.zoomOut[0]);
      set(phone, { transformOrigin: '50% 50%' }, I.zoomOut[1] + 0.0005);
    }
    to(tapped, { yPercent: 0, duration: span(I.lock), ease: 'power2.inOut' }, I.lock[0]);
    to(home, { scale: 0.96, duration: span(I.lock), ease: 'power2.in' }, I.lock[0]);
    set(home, { opacity: 0 }, I.homeOff);

    const controls = section.querySelector<HTMLElement>('[data-controls]');
    // Desktop: after beat 3's copy. Mobile: ControlsCard sits under its copy in the last card,
    // which scrolls up from the bottom; it fades up as it comes into view.
    const cAt = useCallouts ? CUE.controls.card : 0.9;
    const fAt = useCallouts ? CUE.controls.footnote : cAt + 0.02;
    fromTo(controls, { opacity: 0, y: 24 }, { opacity: 1, y: 0, duration: 0.05, ease: 'power2.out' }, cAt);
    // The footnote follows the card, so the copy never shows a hole where the card will be.
    fromTo(section.querySelector('[data-ls-footnote]'), { opacity: 0 }, { opacity: 1, duration: 0.04, ease: 'power1.out' }, fAt);
    fromTo(controls?.querySelector('[data-action-label]'), { opacity: 0, x: -8 }, { opacity: 1, x: 0, duration: 0.04, ease: 'power2.out' }, cAt + 0.02);
    fromTo(controls?.querySelector('[data-action-button]'), { opacity: 0 }, { keyframes: { opacity: [0, 1, 0.2, 1, 0.2, 1] }, duration: Math.min(0.09, 0.995 - (cAt + 0.02)), ease: 'none' }, cAt + 0.02);

    section.dataset.lsScene = 'built';
    return () => {
      delete section.dataset.lsScene;
      cleanups.forEach((f) => f());
    };
  },
  { dayStart: MOMENTS.status },
);
