/**
 * THE CREW SCENE · 2:44 → 3:00 PM (brief: sections[crew].animation; schedule in
 * src/sections/crew/schedule.ts, story in src/sections/crew/story.ts).
 *
 *   enter    Sam's phone slides out from behind yours, names, the server, the wires draw
 *   offline  your bars go one by one, No Service, the key light dims, your wire goes faint
 *   Sam      Sam taps row 12 on his phone; it fills gold; his change goes up to the server
 *   you      you tap rows 11 and 12 with no signal; both fill gold and wait on the phone
 *   sync     3:00: bars back, your two changes go up, Sam's row comes down; row 11 stays
 *            gold, row 12 turns green, Synced, and the banner: the first mark wins
 *   owner    the second phone becomes the owner's: the Team tab comes forward, yours recedes,
 *            "Workers see only their own hours and pay."
 *   exit     everything goes back; the stage phone rests
 *
 * Only transform, opacity and stroke-dashoffset animate (plus the map dots' --g/--e fill
 * opacities, a discrete row-label class swap for the current-row capsule, and z-index sets).
 */
import { registerScene } from '../scene.ts';
import { TEAM } from '../../data/ledger.ts';
import { setOdometer } from '../odometer.ts';
import { AT, AT_MOB, DAY_FROM, DAY_TRACK, DAY_TRACK_MOB } from '../../sections/crew/schedule.ts';
import { POSES, PULL, posePoint, wirePath, type Pose } from '../../sections/crew/geometry.ts';
import { CONFLICT, KEPT, REJECTED, WAITING, WAITING_FIRST } from '../../sections/crew/story.ts';

type Win = readonly [number, number];
const span = (w: Win) => w[1] - w[0];
const pose = (p: Pose) => ({ xPercent: p.x * 100, yPercent: p.y * 100, rotation: p.rotate, scale: p.scale });
/** Where the wires leave each phone: a fraction along its top edge (mobile: straight up from yours). */
const ANCHOR = { desk: { alex: 0.3, sam: 0.17 }, mob: { alex: 0.5, sam: 0.17 } };
const toMinutes = (hm: string) => {
  const [h = 0, m = 0] = hm.split(':').map(Number);
  return h * 60 + m;
};
const fmtHours = (v: number) => `${String(Math.floor(v / 60)).padStart(2, '0')}:${String(v % 60).padStart(2, '0')}`;

interface Packet {
  el: SVGGElement;
  path: SVGPathElement;
  t: number;
}

registerScene(
  'crew',
  (ctx) => {
    const { tl, day, util, gsap, section, isDesk } = ctx;
    // Mobile has its own schedule: the copy cards pass over the phone there (see AT_MOB).
    const A = isDesk ? AT : AT_MOB;
    // ctx.screens can be the previous chapter's container while the stage crossfades (both sit in
    // the stage phone for .35 s), so find this chapter's own by its hook, wherever it is now.
    const screens = section.querySelector<HTMLElement>('[data-crew-screens]') ?? document.querySelector<HTMLElement>('[data-crew-screens]') ?? ctx.screens;
    const one = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string) => root?.querySelector<T>(sel) ?? null;
    const all = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string) =>
      root ? Array.from(root.querySelectorAll<T>(sel)) : [];

    // ---- The DayClock: 2:44 → 3:00, each tap on its mark's minute ----
    for (const d of isDesk ? DAY_TRACK : DAY_TRACK_MOB) day.to(tl, d.min, d.start, d.end);

    // ---- Nodes ----
    const layer = (root: ParentNode | null, id: string) => one(root, `:scope > [data-screen="${id}"]`);
    const peekScreens = one(section, '[data-crew-peek-screens]');
    /**
     * The offline map and the owner's Team tab are drawn once, in the static figure (hidden under
     * motion); borrow them into the moving phones for as long as the scene lives.
     */
    const borrowed: Array<[Element, ParentNode, Element | null]> = [];
    const borrow = (node: Element | null, into: Element | null, before: Element | null) => {
      if (!node?.parentNode || !into || node.parentNode === into) return;
      borrowed.push([node, node.parentNode, node.nextElementSibling]);
      into.insertBefore(node, before);
    };
    borrow(one(section, '.crew-cell--off [data-screen="trees-1456-offline"]'), screens, layer(screens, 'trees-1500-synced'));
    borrow(one(section, '.crew-cell--owner [data-screen="team-1500"]'), peekScreens, null);
    const giveBack = () => {
      for (const [node, parent, next] of borrowed.reverse()) parent.insertBefore(node, next && next.parentNode === parent ? next : null);
      borrowed.length = 0;
    };
    const L0 = layer(screens, 'trees-1447-block3');
    const L1 = layer(screens, 'trees-1456-offline');
    const L2 = layer(screens, 'trees-1500-synced');
    const rig = one(section, '[data-crew-rig]');
    const peek = one(section, '[data-crew-peek]');
    const peekPhone = one(peek, '[data-phone]');
    const S = layer(peekScreens, 'sam-1449-trees');
    const T = layer(peekScreens, 'team-1500');
    if (!screens || !L0 || !L1 || !L2 || !rig || !peek || !peekPhone || !peekScreens || !S || !T) {
      giveBack();
      return;
    }

    const P = isDesk ? POSES.desk : POSES.mob;
    /** The rig's size and the server's anchor in it, set by layout() (offsets, not rects: the camera may scale the rig). */
    const geo = { w: 0, h: 0, srv: { x: 0, y: 0 } };
    const chip = (k: string) => one(section, `[data-crew-chip="${k}"]`);
    const svg = one<SVGSVGElement>(section, '[data-crew-wires]');
    const wires = one<SVGGElement>(svg, '[data-wires]');
    const wire = { sam: one<SVGPathElement>(svg, '[data-wire="sam"]'), alex: one<SVGPathElement>(svg, '[data-wire="alex"]') };
    const reveal = { sam: one<SVGPathElement>(svg, '[data-wire-reveal="sam"]'), alex: one<SVGPathElement>(svg, '[data-wire-reveal="alex"]') };
    const nosig = one<SVGGElement>(svg, '[data-wire-nosig]');
    const nosigAt = one<SVGGElement>(svg, '[data-wire-nosig-at]');
    const srvIn = one(section, '[data-crew-server-in]');
    const srvAnchor = one(section, '[data-srv-anchor]');
    // The moving server's own ring (the static figure's glyph comes first in the section).
    const pulse = one(srvIn, '[data-server-pulse]');
    const srvGlyph = one(srvIn, '[data-server-glyph]');
    const srvLabel = one(srvIn, '.crew-server-label');
    const dim = one(section, '[data-crew-dim]');
    const workers = one(section, '[data-crew-workers]');

    const dots = (root: ParentNode, row: number) => all(root, `[data-map-row="${row}"] [data-tree]`);
    /**
     * A dot's from-state is its data-s (ring | earlier | today), set on the element itself and
     * not with gsap.set: ScrollTrigger reverts the timeline on every refresh, and a reverted
     * CSS-variable tween drops the inline value, so the stylesheet must already hold the start.
     */
    const swapped: Array<[Element, string]> = [];
    const dotState = (els: Element[], state: 'ring' | 'earlier' | 'today') => {
      for (const e of els) {
        swapped.push([e, e.getAttribute('data-s') ?? 'ring']);
        e.setAttribute('data-s', state);
      }
    };
    const label = (root: ParentNode, row: number) => one(root, `[data-row-label="${row}"]`);
    /** A row filling tree by tree, each dot popping a touch as it changes. */
    const fillRow = (els: Element[], w: Win, vars: Record<string, number>) => {
      if (!els.length) return;
      const s = span(w) / (els.length + 2);
      tl.to(els, { ...vars, duration: s * 3, stagger: s, ease: 'power1.out' }, w[0]);
      tl.to(els, { keyframes: { scale: [1, 1.16, 1] }, duration: s * 3, stagger: s, ease: 'none' }, w[0]);
    };
    /**
     * A touch indicator (like a screen recording's) held on the row number from the tap until
     * the row has filled, so the action reads in a still frame and while scrubbing slowly.
     * util.tap still does the press, the ring and the haptic shake.
     */
    const made: Element[] = [];
    const touch = (el: Element | null, at: number, until: number) => {
      if (!el) return;
      const dot = document.createElement('span');
      dot.className = 'crew-touch';
      dot.setAttribute('aria-hidden', 'true');
      el.appendChild(dot);
      made.push(dot);
      tl.fromTo(dot, { opacity: 0, scale: 0.55 }, { opacity: 1, scale: 1, duration: 0.008, ease: 'power2.out', immediateRender: false }, at - 0.006);
      tl.to(dot, { opacity: 0, scale: 1.2, duration: 0.012, ease: 'power1.in' }, until);
    };
    const pulseAt = (w: Win) => {
      if (pulse) tl.to(pulse, { keyframes: { opacity: [0, 0.95, 0], scale: [0.6, 1.5, 2.8] }, duration: span(w), ease: 'none' }, w[0]);
    };

    // ---- The headline: lines mask-reveal once at 'top 75%' (not scrubbed); then the eyebrow and body ----
    // Created a beat later: a tween's ScrollTrigger made in the same tick as this chapter's
    // (still unrefreshed) timeline trigger force-refreshes it mid-refresh, and its scrub never starts.
    const heading = one(section, `#${section.id}-h`);
    if (heading) {
      const head = heading.closest('.beat-head');
      const rest = [one(head, '.eyebrow'), one(head, '.beat-intro')].filter(Boolean);
      const once = { trigger: heading, start: 'top 75%', once: true };
      gsap.set([heading, ...rest], { autoAlpha: 0 });
      gsap.delayedCall(0.05, () => {
        gsap.set([heading, ...rest], { autoAlpha: 1 });
        // Already past its start (a jump into the chapter): leave it as it is, no late reveal.
        if (heading.getBoundingClientRect().top < innerHeight * 0.75) return;
        ctx.SplitText.create(heading, {
          type: 'lines',
          mask: 'lines',
          autoSplit: true,
          onSplit: (self) => gsap.from(self.lines, { yPercent: 100, duration: 0.7, stagger: 0.08, ease: 'power3.out', scrollTrigger: once }),
        });
        if (rest.length) gsap.from(rest, { opacity: 0, y: 14, duration: 0.6, delay: 0.18, stagger: 0.08, ease: 'power2.out', scrollTrigger: once });
      });
    }

    // ---- Progress 0: block 3 on your phone, Sam's map on his, everything else waiting ----
    util.show(screens, 'trees-1447-block3');
    util.show(peekScreens, 'sam-1449-trees');
    gsap.set(peek, { ...pose(P.hidden), opacity: 0, zIndex: -1, transformOrigin: '50% 50%' });

    // ================= [0, .08] enter =================
    // Desktop: pull back a touch so the second phone, the names and the server all fit.
    const cam = isDesk && ctx.phone ? [ctx.phone, rig] : [];
    if (cam.length) {
      gsap.set(rig, { transformOrigin: '50% 50%' });
      tl.to(cam, { scale: PULL.scale, yPercent: PULL.y * 100, duration: span(A.pull), ease: 'power2.inOut' }, A.pull[0]);
    }
    tl.to(peek, { ...pose(P.rest), opacity: 1, duration: span(A.peekIn), ease: 'power2.out', onUpdate: () => samWire() }, A.peekIn[0]);
    // Start states live in the stylesheet (opacity 0) and each tween only goes to its end state:
    // a staggered fromTo keeps only its first target's from-state when scrubbed forward.
    tl.to([chip('sam'), chip('you')], { opacity: 1, y: 0, startAt: { y: 4 }, duration: span(A.chips) - 0.008, stagger: 0.008, ease: 'power2.out' }, A.chips[0]);
    if (srvIn) tl.fromTo(srvIn, { opacity: 0, scale: 0.86 }, { opacity: 1, scale: 1, duration: span(A.server), ease: 'power2.out' }, A.server[0]);
    util.drawLine(tl, reveal.sam, A.wires[0], span(A.wires) - 0.006);
    util.drawLine(tl, reveal.alex, A.wires[0] + 0.006, span(A.wires) - 0.006);

    // ================= [.08, .16] offline =================
    const sb0 = one(L0, '[data-statusbar]');
    const bars0 = [4, 3, 2, 1].map((n) => one(sb0, `[data-bar="${n}"]`)).filter(Boolean);
    const barStep = (span(A.barsOut) - 0.012) / 3;
    tl.to(bars0, { opacity: 0, duration: 0.012, stagger: barStep, ease: 'power1.in' }, A.barsOut[0]);
    tl.to(one(sb0, '[data-wifi]'), { opacity: 0, duration: 0.012 }, A.barsOut[1] - 0.012);
    tl.fromTo(one(sb0, '[data-no-service]'), { opacity: 0 }, { opacity: 1, duration: span(A.noService) }, A.noService[0]);
    if (dim) tl.to(dim, { opacity: 1, duration: span(A.dim) }, A.dim[0]);
    if (wire.alex) tl.to(wire.alex, { opacity: 0.26, duration: span(A.alexWireDim) }, A.alexWireDim[0]);
    if (nosig) {
      gsap.set(nosig, { transformOrigin: '50% 50%' });
      tl.fromTo(nosig, { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.02, ease: 'back.out(2)' }, A.alexWireDim[1] - 0.02);
    }

    // The offline layer takes over looking exactly like block 3 does now.
    const sync1 = one(L1, '[data-sync-line]');
    const [row11] = KEPT.map((m) => m.row);
    const row12 = REJECTED.row;
    const d11 = row11 ? dots(L1, row11) : [];
    const d12 = dots(L1, row12);
    dotState([...d11, ...d12], 'ring');
    if (sync1) gsap.set(sync1, { opacity: 0, yPercent: 60 });
    // The current-row capsule follows Alex: row 11, then 12, then where the static layer has it.
    const capEnd = one(L1, '.tm-cur');
    const lab11 = row11 ? label(L1, row11) : null;
    const lab12 = label(L1, row12);
    const capClass = capEnd?.getAttribute('class') ?? 'tm-rl tm-cur';
    const plainClass = capClass.replace(/\s*tm-cur\b/, '');
    if (capEnd && lab11 && lab12) {
      gsap.set(capEnd, { attr: { class: plainClass } });
      gsap.set(lab11, { attr: { class: capClass } });
    }
    const sb1 = one(L1, '[data-statusbar]');
    const bars1 = [1, 2, 3, 4].map((n) => one<SVGRectElement>(sb1, `[data-bar="${n}"]`)).filter((b): b is SVGRectElement => !!b);
    gsap.set(bars1, { opacity: 0 });
    const count = one(sync1, '[data-sync-count]');
    const plural = one(sync1, '[data-sync-plural]');
    const setCount = (n: number) => {
      if (count) setOdometer(count, String(n));
      if (plural) plural.textContent = n === 1 ? '' : 's';
    };
    setCount(WAITING_FIRST);
    tl.set(L0, { opacity: 0 }, A.offlineLayer);
    tl.set(L1, { opacity: 1 }, A.offlineLayer);

    // ================= [.16, .26] Sam marks row 12 first =================
    const samLab = label(S, CONFLICT.row);
    const samDots = dots(S, CONFLICT.row);
    dotState(samDots, 'ring');
    // His phone swings further out for the tap, so row 12 filling gold reads, then settles back.
    tl.to(peek, { ...pose(P.swing), duration: span(A.swingOut), ease: 'power2.inOut', onUpdate: () => samWire() }, A.swingOut[0]);
    tl.to(peek, { ...pose(P.rest), duration: span(A.swingBack), ease: 'power2.inOut', onUpdate: () => samWire() }, A.swingBack[0]);
    util.tap(tl, samLab, A.tap.sam, { shake: false });
    touch(samLab, A.tap.sam, A.samFill[1]);
    tl.to(peekPhone, { keyframes: { x: [0, 2, -2, 2, -2, 0] }, duration: 0.04, ease: 'none' }, A.tap.sam);
    fillRow(samDots, A.samFill, { '--g': 1 });

    // ---- Packets on the wires ----
    const packet = (k: string, path: SVGPathElement | null, t: number): Packet | null => {
      const el = one<SVGGElement>(svg, `[data-packet="${k}"]`);
      return el && path ? { el, path, t } : null;
    };
    const place = (p: Packet) => {
      const len = p.path.getTotalLength();
      const pt = p.path.getPointAtLength(len * Math.min(1, Math.max(0, p.t)));
      p.el.setAttribute('transform', `translate(${pt.x.toFixed(1)} ${pt.y.toFixed(1)})`);
    };
    const travel = (p: Packet | null, w: Win, from: number, to: number, fade: 'both' | 'out' | 'in' = 'both') => {
      if (!p) return;
      tl.fromTo(p, { t: from }, { t: to, duration: span(w), ease: 'power1.inOut', immediateRender: false, onUpdate: () => place(p) }, w[0]);
      const op = fade === 'both' ? [0, 1, 1, 1, 0] : fade === 'out' ? [1, 1, 1, 1, 0] : [0, 1, 1, 1, 1];
      tl.to(p.el, { keyframes: { opacity: op }, duration: span(w), ease: 'none' }, w[0]);
    };
    const pkSam = packet('sam', wire.sam, 0);
    const pkA1 = packet('alex-1', wire.alex, 0.17);
    const pkA2 = packet('alex-2', wire.alex, 0.06);
    const pkDownAlex = packet('down-alex', wire.alex, 1);
    const pkDownSam = packet('down-sam', wire.sam, 1);
    const packets = [pkSam, pkA1, pkA2, pkDownAlex, pkDownSam].filter((p): p is Packet => !!p);

    travel(pkSam, A.packetSam, 0, 1);
    pulseAt(A.pulseSam);

    // ================= [.26, .42] you mark rows 11 and 12 with no signal =================
    util.tap(tl, lab11, A.tap.row11);
    touch(lab11, A.tap.row11, A.fill11[1]);
    fillRow(d11, A.fill11, { '--g': 1 });
    if (lab11 && lab12) {
      tl.set(lab11, { attr: { class: plainClass } }, A.fill11[1]);
      tl.set(lab12, { attr: { class: capClass } }, A.fill11[1]);
    }
    if (sync1) tl.to(sync1, { opacity: 1, yPercent: 0, duration: span(A.syncIn), ease: 'power3.out' }, A.syncIn[0]);
    // Each offline change waits on the wire by your phone.
    if (pkA1) tl.to(pkA1.el, { opacity: 1, duration: span(A.queue1) }, A.queue1[0]);
    util.tap(tl, lab12, A.tap.row12);
    touch(lab12, A.tap.row12, A.fill12[1]);
    fillRow(d12, A.fill12, { '--g': 1 });
    if (capEnd && lab12) {
      tl.set(lab12, { attr: { class: plainClass } }, A.fill12[1]);
      tl.set(capEnd, { attr: { class: capClass } }, A.fill12[1]);
    }
    // Row 12's ten tree marks join the outbox together: 10 → 20 changes, a whole row at a time.
    const n = { v: WAITING_FIRST };
    const per = Math.max(1, WAITING_FIRST);
    tl.fromTo(n, { v: WAITING_FIRST }, { v: WAITING, duration: span(A.count), ease: 'none', immediateRender: false, onUpdate: () => setCount(Math.round(n.v / per) * per) }, A.count[0]);
    if (pkA2) tl.to(pkA2.el, { opacity: 1, duration: span(A.queue2) }, A.queue2[0]);

    // ================= [.42, .6] back in range: sync, first mark wins =================
    const barsSvg = bars1[0]?.ownerSVGElement ?? null;
    if (barsSvg) tl.set(barsSvg, { opacity: 1 }, A.barsIn[0]);
    tl.to(bars1, { opacity: 1, duration: 0.01, stagger: (span(A.barsIn) - 0.022) / 3 }, A.barsIn[0]);
    tl.to(one(sb1, '[data-no-service]'), { opacity: 0, duration: 0.01 }, A.barsIn[0]);
    tl.to(one(sb1, '[data-wifi]'), { opacity: 1, duration: 0.012 }, A.barsIn[1] - 0.012);
    if (dim) tl.to(dim, { opacity: 0, duration: span(A.undim) }, A.undim[0]);
    if (wire.alex) tl.to(wire.alex, { opacity: 1, duration: 0.03 }, A.barsIn[0]);
    if (nosig) tl.to(nosig, { opacity: 0, scale: 0.6, duration: 0.014 }, A.barsIn[0]);
    // Your two changes go up (they were waiting), and Sam's row 12 comes down to you.
    travel(pkA1, [A.packetsUp[0], A.packetsUp[1] - 0.02], 0.17, 1, 'out');
    travel(pkA2, [A.packetsUp[0] + 0.02, A.packetsUp[1]], 0.06, 1, 'out');
    pulseAt(A.pulseSync);
    travel(pkDownAlex, A.packetDown, 1, 0);
    // …and your row 11 reaches Sam's map (green there: someone else shaped it).
    travel(pkDownSam, A.packetDown, 1, 0);
    if (row11) fillRow(dots(S, row11), [A.packetDown[1], A.packetDown[1] + 0.018], { '--e': 1 });

    // The offline line rolls out, the synced layer takes over, Synced rolls in.
    if (sync1) tl.to(sync1, { opacity: 0, yPercent: -60, duration: span(A.syncOut), ease: 'power2.in' }, A.syncOut[0]);
    const sync2 = one(L2, '[data-sync-line]');
    const g12 = dots(L2, row12);
    dotState(g12, 'today');
    if (sync2) gsap.set(sync2, { opacity: 0, yPercent: 60 });
    tl.set(L1, { opacity: 0 }, A.swap);
    tl.set(L2, { opacity: 1 }, A.swap);
    if (sync2) {
      tl.to(sync2, { opacity: 1, yPercent: 0, duration: span(A.syncedIn), ease: 'power3.out' }, A.syncedIn[0]);
      const check = one(sync2, 'svg');
      if (check) tl.fromTo(check, { scale: 0.4 }, { scale: 1, duration: span(A.syncedIn), ease: 'back.out(2.4)', immediateRender: false }, A.syncedIn[0] + 0.004);
    }
    // Row 12 was Sam's first: gold → green on your phone (the green is laid under the gold
    // first, so each dot turns cleanly instead of through a muddy mix over white).
    tl.to(g12, { '--e': 1, duration: 0.002 }, A.green[0]);
    fillRow(g12, A.green, { '--g': 0 });
    const banner = one(L2, '[data-banner]');
    if (banner) {
      tl.fromTo(banner, { opacity: 0, yPercent: 40, scale: 0.96 }, { opacity: 1, yPercent: 0, scale: 1, duration: span(A.banner), ease: 'power3.out' }, A.banner[0]);
      // [.6, .66] the banner goes.
      tl.to(banner, { opacity: 0, yPercent: 30, scale: 0.98, duration: span(A.bannerOut), ease: 'power2.in' }, A.bannerOut[0]);
    }

    // ================= [.66, .9] the owner's phone =================
    tl.to(chip('sam'), { opacity: 0, duration: span(A.relabel) * 0.5 }, A.relabel[0]);
    tl.fromTo(chip('owner'), { opacity: 0, y: 4 }, { opacity: 1, y: 0, duration: span(A.relabel) * 0.6, ease: 'power2.out' }, A.relabel[0] + span(A.relabel) * 0.4);
    // A tab switch is instant on iOS: a cut, made while this phone is still behind yours.
    tl.set(S, { opacity: 0 }, A.teamCut);
    tl.set(T, { opacity: 1 }, A.teamCut);
    tl.to([wires, nosig], { opacity: 0, duration: span(A.wiresDim) }, A.wiresDim[0]);
    // The server steps back while the owner's phone has the floor: the glyph dims and its label
    // goes (a dimmed label would fail contrast). Mobile: the owner's name tag sits right where
    // the server is, so the glyph goes too.
    if (srvGlyph) tl.to(srvGlyph, { opacity: isDesk ? 0.4 : 0, duration: span(A.wiresDim) }, A.wiresDim[0]);
    if (srvLabel) tl.to(srvLabel, { opacity: 0, duration: span(A.wiresDim) * 0.6 }, A.wiresDim[0]);
    // The z swap: the second phone comes in front of yours. Desktop: above the stage phone (the
    // frame goes over the stage); mobile: the rig goes over the section phone's cell.
    tl.set(peek, { zIndex: 4 }, A.zSwap);
    if (isDesk && ctx.frame) tl.set(ctx.frame, { zIndex: 7 }, A.zSwap);
    if (!isDesk) tl.set(rig, { zIndex: 3 }, A.zSwap);
    tl.to(peek, { ...pose(P.front), duration: span(A.forward), ease: 'power2.inOut' }, A.forward[0]);
    const rest = cam.length ? PULL.scale : 1;
    if (ctx.phone) tl.to(ctx.phone, { scale: rest * 0.92, opacity: 0.7, duration: span(A.forward), ease: 'power2.inOut' }, A.forward[0]);
    tl.to(chip('you'), { opacity: 0, duration: 0.02 }, A.forward[0]);

    // This week's rows come in and their hours roll up from the ledger.
    const rows = all(T, '[data-team-row]');
    if (rows.length) tl.to(rows, { opacity: 1, y: 0, startAt: { y: 10 }, duration: 0.03, stagger: 0.012, ease: 'power2.out' }, A.rows[0]);
    const hours: Array<[HTMLElement, string]> = [];
    rows.forEach((row, i) => {
      const h = one(row, '[data-hours]');
      const r = TEAM.find((m) => m.name === row.dataset.teamRow);
      if (!h || !r) return;
      hours.push([h, r.hours]);
      util.odometer(tl, h, 0, toMinutes(r.hours), A.rows[0] + 0.008 + i * 0.012, span(A.rows) - 0.034, fmtHours);
    });
    const after = [one(T, '[data-team-total]'), one(T, '[data-invite]'), one(T, '[data-fields-row]')].filter(Boolean);
    if (after.length) tl.to(after, { opacity: 1, y: 0, startAt: { y: 8 }, duration: span(A.invite) - 0.008, stagger: 0.004, ease: 'power2.out' }, A.invite[0]);
    if (workers) tl.to(workers, { opacity: 1, y: 0, startAt: { y: 8 }, duration: span(A.workers), ease: 'power2.out' }, A.workers[0]);
    // Beat 5: the farm's own server. The owner's tag makes way for it first (on short screens
    // it sits right over the glyph).
    tl.to(chip('owner'), { opacity: 0, duration: span(A.ownerOut) }, A.ownerOut[0]);
    const srvParts = [srvGlyph, srvLabel].filter(Boolean);
    if (srvParts.length) tl.to(srvParts, { opacity: 1, duration: 0.02 }, A.serverLit[0]);
    pulseAt(A.serverLit);

    // ================= [.9, 1] back to rest: the entrance in reverse =================
    // The owner's phone steps back to rest while yours comes up to full strength behind it; then
    // it goes behind yours and recedes, fading only once it is hidden (no double exposure).
    tl.to(peek, { ...pose(P.rest), duration: span(A.exitBack), ease: 'power2.inOut' }, A.exitBack[0]);
    if (ctx.phone) tl.to(ctx.phone, { scale: rest, opacity: 1, duration: span(A.exitBack), ease: 'power2.inOut' }, A.exitBack[0]);
    tl.set(peek, { zIndex: -1 }, A.exitSwap);
    if (isDesk && ctx.frame) tl.set(ctx.frame, { zIndex: 'auto' }, A.exitSwap);
    if (!isDesk) tl.set(rig, { zIndex: 1 }, A.exitSwap);
    tl.to(peek, { ...pose(P.hidden), duration: span(A.exitHide), ease: 'power2.inOut' }, A.exitHide[0]);
    tl.to(peek, { opacity: 0, duration: span(A.exitFade), ease: 'power1.in' }, A.exitFade[0]);
    // Desktop: the camera comes back as the stage phone heads on to the next chapter.
    if (cam.length) tl.to(cam, { scale: 1, yPercent: 0, duration: span(A.exitHide), ease: 'power2.inOut' }, A.exitHide[0]);
    // Mobile keeps the lit server above the phone as the section scrolls away (its line is up).
    const decor = [chip('owner'), workers, isDesk ? srvIn : null].filter(Boolean);
    if (decor.length) tl.to(decor, { opacity: 0, duration: span(A.exitDecor) }, A.exitDecor[0]);

    // ---- Wires: drawn from the real layout, redrawn on every refresh ----
    const slot = isDesk ? (ctx.stage?.phone.parentElement ?? null) : null;
    /** The second phone's pose right now (it moves: in, the swing for Sam's tap, back). */
    const poseNow = (): Pose => ({
      x: Number(gsap.getProperty(peek, 'xPercent')) / 100,
      y: Number(gsap.getProperty(peek, 'yPercent')) / 100,
      rotate: Number(gsap.getProperty(peek, 'rotation')),
      scale: Number(gsap.getProperty(peek, 'scale')),
    });
    /** Sam's wire comes out of his name tag (top centre), wherever his phone is now (a no-op until layout()). */
    function samWire() {
      const { w, h, srv } = geo;
      if (!w || !h || !wire.sam) return;
      const A2 = isDesk ? ANCHOR.desk : ANCHOR.mob;
      const tag = chip('sam');
      const now = poseNow();
      const sam = tag?.offsetWidth
        ? posePoint({ w, h }, now, (tag.offsetLeft + tag.offsetWidth / 2) / w, (tag.offsetTop + 1) / h)
        : posePoint({ w, h }, now, A2.sam, 0.004);
      const d = wirePath(sam, srv);
      wire.sam.setAttribute('d', d);
      reveal.sam?.setAttribute('d', d);
      for (const p of [pkSam, pkDownSam]) if (p) place(p);
    }
    const layout = () => {
      if (slot) {
        const r = slot.getBoundingClientRect();
        const set = (k: string, v: number) => rig.style.setProperty(k, `${v.toFixed(1)}px`);
        set('--crew-sx', r.left);
        set('--crew-sy', r.top);
        set('--crew-sw', r.width);
        set('--crew-sh', r.height);
      }
      const w = rig.offsetWidth;
      const h = rig.offsetHeight;
      if (!w || !h || !srvAnchor || !wire.sam || !wire.alex) return;
      const srv = { x: 0, y: 0 };
      for (let e: HTMLElement | null = srvAnchor; e && e !== rig; e = e.offsetParent as HTMLElement | null) {
        srv.x += e.offsetLeft;
        srv.y += e.offsetTop;
      }
      Object.assign(geo, { w, h, srv });
      // Your wire leaves your name tag the same way (mobile has no tag: straight up from the phone).
      const you = chip('you');
      const alex = you?.offsetWidth
        ? { x: you.offsetLeft + you.offsetWidth / 2, y: you.offsetTop + 1 }
        : { x: (isDesk ? ANCHOR.desk : ANCHOR.mob).alex * w, y: 1 };
      const dA = wirePath(alex, srv);
      wire.alex.setAttribute('d', dA);
      reveal.alex?.setAttribute('d', dA);
      if (nosigAt) {
        const mid = wire.alex.getPointAtLength(wire.alex.getTotalLength() * 0.5);
        nosigAt.setAttribute('transform', `translate(${mid.x.toFixed(1)} ${mid.y.toFixed(1)})`);
      }
      samWire();
      packets.forEach(place);
    };
    layout();
    /**
     * After a global refresh, make sure the scrub caught up. ScrollTrigger queues a refresh
     * ~200 ms after a lazily built scene creates its trigger; if that lands while this scrub is
     * still catching up (a jump into the middle of the chapter), the scrub tween is left paused
     * part-way and nothing moves until the next scroll. Re-sync once the refresh has settled.
     */
    let raf = 0;
    const resync = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const st = tl.scrollTrigger;
        const tw = st?.getTween?.();
        if (st && !(tw && tw.isActive()) && Math.abs(tl.progress() - st.progress) > 0.001) tl.progress(st.progress);
      });
    };
    const onRefresh = () => {
      layout();
      resync();
    };
    const ST = ctx.ScrollTrigger;
    ST.addEventListener('refresh', onRefresh);
    // The same stall can come from another chapter's trigger made in this tick: check twice.
    gsap.delayedCall(0.2, resync);
    gsap.delayedCall(1, resync);

    return () => {
      cancelAnimationFrame(raf);
      ST.removeEventListener('refresh', onRefresh);
      for (const k of ['--crew-sx', '--crew-sy', '--crew-sw', '--crew-sh']) rig.style.removeProperty(k);
      // Put the static markup's values back (the DOM writes GSAP does not revert).
      setCount(WAITING);
      for (const m of made) m.remove();
      for (const [e, state] of swapped) e.setAttribute('data-s', state);
      for (const [h, text] of hours) setOdometer(h, text);
      giveBack();
    };
  },
  { dayStart: DAY_FROM },
);
