/**
 * SCENE: LOCK SCREEN · 2:14 PM (brief: .sections[lock-screen].animation; progress units 0–1).
 *
 *   [0, .08]    2:01 → 2:14: the timer runs 6:14 → 6:27, trees 212 → 220, the buttons step
 *               from Row 35 to Row 36 as row 35 is finished (2:12), the sheen sweeps
 *   [.08, .2]   the phone zooms (1.7 desktop, 1.4 mobile) about the Live Activity's centre;
 *               the lock screen dims to .45 under the card
 *   [.2, .5]    desktop: six callouts draw in .05 slots, the ghost Clock out with the sixth,
 *               its strike last. Mobile: pins 1–6 pop and pulse while card 1's notes light up
 *   [.5, .62]   the tap on Row 36: the strip moves one step, trees 220 → 230, the field bar
 *               creeps on, 'Row 36 marked · Undo' rises in
 *   [.62, .7]   zoom back, callouts fade, the dim lifts
 *   [.7, .85]   unlock to the home screen, 2:14 → 2:16; the island goes rest → compact
 *               [.74, .78] → expanded [.78, .85]
 *   [.85, .95]  the island collapses, the lock screen returns, ControlsCard fades up and the
 *               Action button glows twice
 *   [.95, 1]    rest on the lock screen in the tapped state
 *
 * Geometry and copy come from src/sections/lock-screen/model.ts; numbers from the ledger.
 * Every hook is optional: a real capture swapped in for a layer turns its part into a still.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS } from '../../data/ledger.ts';
import {
  BEFORE,
  CALLOUTS,
  deskLayout,
  ISLAND_AT,
  mobZoom,
  ORIGIN,
  slots,
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

    /** One strip step in px: two neighbouring row buttons' layout distance (transforms ignored). */
    const stepOf = (root: Element | null) => () => {
      const rows = root ? Array.from(root.querySelectorAll<HTMLElement>('[data-row]')) : [];
      return rows.length > 1 ? rows[1]!.offsetLeft - rows[0]!.offsetLeft : 0;
    };
    const stepPre = stepOf(pre);
    const stepTap = stepOf(tapped);

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
    const zoom = () => (useCallouts && L ? { scale: L.zoom, x: L.x, y: L.y } : mobZoom(phone?.offsetHeight ?? 0));

    // ---- [0, .08] 2:01 → 2:14 ----
    day.to(tl, MOMENTS.lockScreen, T.step[0], T.step[1], MOMENTS.status);
    util.sheen(tl, 0.012, 0.05);
    // Row 35's last eight trees land at 2:12 (≈ .068): trees, field bar and the buttons move on.
    util.odometer(tl, inPre('[data-trees]'), BEFORE.trees, WORKING.trees, 0.058, 0.014);
    fromTo(inPre('[data-fieldbar]'), { scaleX: BEFORE.fieldPct }, { scaleX: WORKING.fieldPct, duration: 0.016, ease: 'power2.out' }, 0.058);
    fromTo(inPre('[data-strip-track]'), { x: () => stepPre() }, { x: 0, duration: 0.018, ease: 'power2.inOut' }, 0.06);

    // The tapped layer takes over, identical at this instant (before the tap).
    set(pre, { opacity: 0 }, T.step[1]);
    set(tapped, { opacity: 1 }, T.step[1]);
    const strip = inTap('[data-strip-track]');
    set(strip, { x: () => stepTap() });
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
    // Desktop: the headline steps aside as the zoomed phone reaches into the copy column.
    if (useCallouts) to(ctx.beats[0], { opacity: 0, duration: 0.06, ease: 'power1.in' }, T.zoomIn[0] + 0.01);

    // ---- [.2, .5] callouts (desktop) or pins (mobile) ----
    const s = slots(T.callouts[0], T.callouts[1], CALLOUTS.length);
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
        const [a, b] = s[i]!;
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
      CALLOUTS.forEach((_, i) => {
        const [a, b] = s[i]!;
        const w = b - a;
        fromTo(pins[i], { opacity: 0, scale: 0 }, { opacity: 1, scale: 1, duration: w * 0.3, ease: 'back.out(2.2)', immediateRender: false }, a);
        to(pins[i], { keyframes: { scale: [1, 1.28, 1] }, duration: w * 0.45, ease: 'power1.inOut' }, a + w * 0.35);
        fromTo(rules[i], { scaleY: 0 }, { scaleY: 1, duration: w * 0.25, ease: 'power2.out', immediateRender: false }, a);
        to(rules[i], { scaleY: 0, duration: w * 0.25, ease: 'power2.in' }, i < CALLOUTS.length - 1 ? b : T.tap[0] + 0.02);
        to(nums[i], { keyframes: { scale: [1, 1.18, 1] }, duration: w * 0.45, ease: 'power1.inOut' }, a + w * 0.35);
      });
      to(pins, { opacity: 0, duration: 0.03, stagger: 0.004, ease: 'power1.in' }, T.zoomOut[0]);

      // The caption slot: notes [.19, .5], the tap [.515, .66], the island [.69, .87].
      const card = (sel: string, a: number, b: number) => {
        const el = section.querySelector<HTMLElement>(sel);
        fromTo(el, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: 0.02, ease: 'power2.out', immediateRender: true }, a);
        to(el, { opacity: 0, y: -10, duration: 0.018, ease: 'power1.in' }, b);
      };
      card('.ls-notes-beat', 0.185, 0.505);
      card('.ls-tap-beat', 0.52, 0.665);
      card('.ls-island-beat', 0.69, 0.87);
    }

    // ---- [.5, .62] the tap on Row 36 ----
    util.tap(tl, inTap(`[data-row="${TAPPED.undoRow}"]`), T.tap[0], { shake: false });
    // The 2px haptic shake, on top of the zoom (util.tap's own would reset x to 0).
    if (phone) [2, -2, 2, -2, 0].forEach((dx, i) => to(phone, { x: () => zoom().x + dx, duration: 0.008, ease: 'none' }, T.tap[0] + i * 0.008));
    fromTo(strip, { x: () => stepTap() }, { x: 0, duration: 0.04, ease: 'power2.inOut', immediateRender: false }, 0.535);
    fromTo(bar, { scaleX: WORKING.fieldPct }, { scaleX: TAPPED.fieldPct, duration: 0.03, ease: 'power2.out' }, 0.54);
    fromTo(undo, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.035, ease: 'power2.out' }, 0.56);

    // ---- [.62, .7] zoom back ----
    if (phone) {
      to(phone, { scale: 1, x: 0, y: 0, duration: T.zoomOut[1] - T.zoomOut[0], ease: 'power2.inOut' }, T.zoomOut[0]);
      set(phone, { transformOrigin: '50% 50%' }, T.zoomOut[1]);
    }
    to(dim, { opacity: 0, duration: 0.07, ease: 'none' }, T.zoomOut[0]);
    if (useCallouts) {
      const order = [6, 5, 3, 4, 1, 2].map((n) => n - 1);
      to(ghost, { opacity: 0, duration: 0.03, ease: 'power1.in' }, T.zoomOut[0]);
      to(
        order.flatMap((i) => [labels[i], lines[i], dots[i]]),
        { opacity: 0, duration: 0.03, stagger: 0.0015, ease: 'power1.in' },
        T.zoomOut[0] + 0.005,
      );
    }

    // Desktop: the island and controls copy rise through the callouts' column unseen, then
    // fade in once the phone is back at rest.
    if (useCallouts) {
      const islandBeat = section.querySelector('.ls-island-beat');
      const controlsBeat = section.querySelector('.ls-controls-beat');
      fromTo(islandBeat, { opacity: 0 }, { opacity: 1, duration: 0.045, ease: 'power1.out' }, 0.665);
      fromTo(controlsBeat, { opacity: 0 }, { opacity: 1, duration: 0.05, ease: 'power1.out' }, 0.69);
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
    set(island, size('rest'));
    set([compact, expanded], { opacity: 0 });
    set(home, { '--island-yield': 0 });

    set(home, { opacity: 1 }, T.unlock[0]);
    fromTo(tapped, { yPercent: 0 }, { yPercent: -100, duration: 0.045, ease: 'power2.inOut', immediateRender: false }, T.unlock[0]);
    fromTo(home, { scale: 0.94 }, { scale: 1, duration: 0.05, ease: 'power2.out', immediateRender: false }, T.unlock[0] + 0.004);
    util.sheen(tl, T.unlock[0] + 0.01, 0.05);

    const [c0, c1] = T.compact;
    fromTo(island, size('rest'), { ...size('compact'), duration: c1 - c0, ease: 'power3.inOut', immediateRender: false }, c0);
    fromTo(home, { '--island-yield': 0 }, { '--island-yield': 1, duration: c1 - c0, ease: 'power3.inOut', immediateRender: false }, c0);
    fromTo(compact, { opacity: 0 }, { opacity: 1, duration: (c1 - c0) * 0.3, ease: 'none', immediateRender: false }, c0 + (c1 - c0) * 0.7);

    const [e0, e1] = T.expanded;
    to(island, { ...size('expanded'), duration: e1 - e0, ease: 'power3.inOut' }, e0);
    to(home, { '--island-yield': 2, duration: e1 - e0, ease: 'power3.inOut' }, e0);
    to(compact, { opacity: 0, duration: (e1 - e0) * 0.2, ease: 'none' }, e0);
    fromTo(expanded, { opacity: 0 }, { opacity: 1, duration: (e1 - e0) * 0.3, ease: 'none', immediateRender: false }, e0 + (e1 - e0) * 0.7);

    // ---- [.85, .95] the island collapses, the lock screen returns, the controls ----
    to(expanded, { opacity: 0, duration: 0.01, ease: 'none' }, T.collapse[0]);
    to(island, { ...size('rest'), duration: 0.035, ease: 'power3.inOut' }, T.collapse[0] + 0.002);
    to(home, { '--island-yield': 0, duration: 0.035, ease: 'power3.inOut' }, T.collapse[0] + 0.002);
    to(tapped, { yPercent: 0, duration: 0.05, ease: 'power2.inOut' }, 0.865);
    to(home, { scale: 0.96, duration: 0.05, ease: 'power2.in' }, 0.865);
    set(home, { opacity: 0 }, 0.93);

    const controls = section.querySelector<HTMLElement>('[data-controls]');
    // Mobile: ControlsCard sits under its copy in the last card, which scrolls up from the
    // bottom; it fades up as it comes into view.
    const cAt = useCallouts ? T.collapse[0] : 0.9;
    fromTo(controls, { opacity: 0, y: 24 }, { opacity: 1, y: 0, duration: 0.06, ease: 'power2.out' }, cAt);
    // The footnote arrives with the card, so the copy never shows a hole where the card will be.
    fromTo(section.querySelector('[data-ls-footnote]'), { opacity: 0 }, { opacity: 1, duration: 0.05, ease: 'power1.out' }, cAt + 0.02);
    fromTo(controls?.querySelector('[data-action-label]'), { opacity: 0, x: -8 }, { opacity: 1, x: 0, duration: 0.04, ease: 'power2.out' }, cAt + 0.03);
    fromTo(controls?.querySelector('[data-action-button]'), { opacity: 0 }, { keyframes: { opacity: [0, 1, 0.2, 1, 0.2, 1] }, duration: Math.min(0.09, 0.995 - (cAt + 0.02)), ease: 'none' }, cAt + 0.02);

    section.dataset.lsScene = 'built';
    return () => {
      delete section.dataset.lsScene;
      cleanups.forEach((f) => f());
    };
  },
  { dayStart: MOMENTS.status },
);
