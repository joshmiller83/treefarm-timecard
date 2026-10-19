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
import { AT, DAY_FROM, DAY_TRACK } from '../../sections/crew/schedule.ts';
import { POSES, PULL, posePoint, wirePath, type Pose } from '../../sections/crew/geometry.ts';
import { CONFLICT, KEPT, REJECTED, WAITING } from '../../sections/crew/story.ts';

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
    // ctx.screens can be the previous chapter's container while the stage crossfades (both sit in
    // the stage phone for .35 s), so find this chapter's own by its hook, wherever it is now.
    const screens = section.querySelector<HTMLElement>('[data-crew-screens]') ?? document.querySelector<HTMLElement>('[data-crew-screens]') ?? ctx.screens;
    const one = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string) => root?.querySelector<T>(sel) ?? null;
    const all = <T extends Element = HTMLElement>(root: ParentNode | null | undefined, sel: string) =>
      root ? Array.from(root.querySelectorAll<T>(sel)) : [];

    // ---- The DayClock: 2:44 → 3:00, each tap on its mark's minute ----
    for (const d of DAY_TRACK) day.to(tl, d.min, d.start, d.end);

    // ---- Nodes ----
    const layer = (root: ParentNode | null, id: string) => one(root, `:scope > [data-screen="${id}"]`);
    const L0 = layer(screens, 'trees-1447-block3');
    const L1 = layer(screens, 'trees-1456-offline');
    const L2 = layer(screens, 'trees-1500-synced');
    const rig = one(section, '[data-crew-rig]');
    const peek = one(section, '[data-crew-peek]');
    const peekPhone = one(peek, '[data-phone]');
    const peekScreens = one(peek, '[data-crew-peek-screens]');
    const S = layer(peekScreens, 'sam-1449-trees');
    const T = layer(peekScreens, 'team-1500');
    if (!screens || !L0 || !L1 || !L2 || !rig || !peek || !peekPhone || !peekScreens || !S || !T) return;

    const P = isDesk ? POSES.desk : POSES.mob;
    const chip = (k: string) => one(section, `[data-crew-chip="${k}"]`);
    const svg = one<SVGSVGElement>(section, '[data-crew-wires]');
    const wires = one<SVGGElement>(svg, '[data-wires]');
    const wire = { sam: one<SVGPathElement>(svg, '[data-wire="sam"]'), alex: one<SVGPathElement>(svg, '[data-wire="alex"]') };
    const reveal = { sam: one<SVGPathElement>(svg, '[data-wire-reveal="sam"]'), alex: one<SVGPathElement>(svg, '[data-wire-reveal="alex"]') };
    const nosig = one<SVGGElement>(svg, '[data-wire-nosig]');
    const nosigAt = one<SVGGElement>(svg, '[data-wire-nosig-at]');
    const srvIn = one(section, '[data-crew-server-in]');
    const srvAnchor = one(section, '[data-srv-anchor]');
    const pulse = one(section, '[data-server-pulse]');
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
      tl.to(cam, { scale: PULL.scale, yPercent: PULL.y * 100, duration: span(AT.pull), ease: 'power2.inOut' }, AT.pull[0]);
    }
    tl.to(peek, { ...pose(P.rest), opacity: 1, duration: span(AT.peekIn), ease: 'power2.out' }, AT.peekIn[0]);
    tl.fromTo([chip('sam'), chip('you')], { opacity: 0, y: 4 }, { opacity: 1, y: 0, duration: span(AT.chips) - 0.008, stagger: 0.008, ease: 'power2.out' }, AT.chips[0]);
    if (srvIn) tl.fromTo(srvIn, { opacity: 0, scale: 0.86 }, { opacity: 1, scale: 1, duration: span(AT.server), ease: 'power2.out' }, AT.server[0]);
    util.drawLine(tl, reveal.sam, AT.wires[0], span(AT.wires) - 0.006);
    util.drawLine(tl, reveal.alex, AT.wires[0] + 0.006, span(AT.wires) - 0.006);

    // ================= [.08, .16] offline =================
    const sb0 = one(L0, '[data-statusbar]');
    const bars0 = [4, 3, 2, 1].map((n) => one(sb0, `[data-bar="${n}"]`)).filter(Boolean);
    const barStep = (span(AT.barsOut) - 0.012) / 3;
    tl.to(bars0, { opacity: 0, duration: 0.012, stagger: barStep, ease: 'power1.in' }, AT.barsOut[0]);
    tl.to(one(sb0, '[data-wifi]'), { opacity: 0, duration: 0.012 }, AT.barsOut[1] - 0.012);
    tl.fromTo(one(sb0, '[data-no-service]'), { opacity: 0 }, { opacity: 1, duration: span(AT.noService) }, AT.noService[0]);
    if (dim) tl.to(dim, { opacity: 1, duration: span(AT.dim) }, AT.dim[0]);
    if (wire.alex) tl.to(wire.alex, { opacity: 0.26, duration: span(AT.alexWireDim) }, AT.alexWireDim[0]);
    if (nosig) {
      gsap.set(nosig, { transformOrigin: '50% 50%' });
      tl.fromTo(nosig, { opacity: 0, scale: 0.6 }, { opacity: 1, scale: 1, duration: 0.02, ease: 'back.out(2)' }, AT.alexWireDim[1] - 0.02);
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
    setCount(1);
    tl.set(L0, { opacity: 0 }, AT.offlineLayer);
    tl.set(L1, { opacity: 1 }, AT.offlineLayer);

    // ================= [.16, .26] Sam marks row 12 first =================
    const samLab = label(S, CONFLICT.row);
    const samDots = dots(S, CONFLICT.row);
    dotState(samDots, 'ring');
    util.tap(tl, samLab, AT.tap.sam, { shake: false });
    touch(samLab, AT.tap.sam, AT.samFill[1]);
    tl.to(peekPhone, { keyframes: { x: [0, 2, -2, 2, -2, 0] }, duration: 0.04, ease: 'none' }, AT.tap.sam);
    fillRow(samDots, AT.samFill, { '--g': 1 });

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

    travel(pkSam, AT.packetSam, 0, 1);
    pulseAt(AT.pulseSam);

    // ================= [.26, .42] you mark rows 11 and 12 with no signal =================
    util.tap(tl, lab11, AT.tap.row11);
    touch(lab11, AT.tap.row11, AT.fill11[1]);
    fillRow(d11, AT.fill11, { '--g': 1 });
    if (lab11 && lab12) {
      tl.set(lab11, { attr: { class: plainClass } }, AT.fill11[1]);
      tl.set(lab12, { attr: { class: capClass } }, AT.fill11[1]);
    }
    if (sync1) tl.to(sync1, { opacity: 1, yPercent: 0, duration: span(AT.syncIn), ease: 'power3.out' }, AT.syncIn[0]);
    // Each offline change waits on the wire by your phone.
    if (pkA1) tl.to(pkA1.el, { opacity: 1, duration: span(AT.queue1) }, AT.queue1[0]);
    util.tap(tl, lab12, AT.tap.row12);
    touch(lab12, AT.tap.row12, AT.fill12[1]);
    fillRow(d12, AT.fill12, { '--g': 1 });
    if (capEnd && lab12) {
      tl.set(lab12, { attr: { class: plainClass } }, AT.fill12[1]);
      tl.set(capEnd, { attr: { class: capClass } }, AT.fill12[1]);
    }
    const n = { v: 1 };
    tl.fromTo(n, { v: 1 }, { v: WAITING, duration: span(AT.count), ease: 'none', immediateRender: false, onUpdate: () => setCount(Math.round(n.v)) }, AT.count[0]);
    if (pkA2) tl.to(pkA2.el, { opacity: 1, duration: span(AT.queue2) }, AT.queue2[0]);

    // ================= [.42, .6] back in range: sync, first mark wins =================
    const barsSvg = bars1[0]?.ownerSVGElement ?? null;
    if (barsSvg) tl.set(barsSvg, { opacity: 1 }, AT.barsIn[0]);
    tl.to(bars1, { opacity: 1, duration: 0.01, stagger: (span(AT.barsIn) - 0.022) / 3 }, AT.barsIn[0]);
    tl.to(one(sb1, '[data-no-service]'), { opacity: 0, duration: 0.01 }, AT.barsIn[0]);
    tl.to(one(sb1, '[data-wifi]'), { opacity: 1, duration: 0.012 }, AT.barsIn[1] - 0.012);
    if (dim) tl.to(dim, { opacity: 0, duration: span(AT.undim) }, AT.undim[0]);
    if (wire.alex) tl.to(wire.alex, { opacity: 1, duration: 0.03 }, AT.barsIn[0]);
    if (nosig) tl.to(nosig, { opacity: 0, scale: 0.6, duration: 0.014 }, AT.barsIn[0]);
    // Your two changes go up (they were waiting), and Sam's row 12 comes down to you.
    travel(pkA1, [AT.packetsUp[0], AT.packetsUp[1] - 0.02], 0.17, 1, 'out');
    travel(pkA2, [AT.packetsUp[0] + 0.02, AT.packetsUp[1]], 0.06, 1, 'out');
    pulseAt(AT.pulseSync);
    travel(pkDownAlex, AT.packetDown, 1, 0);
    // …and your row 11 reaches Sam's map (green there: someone else shaped it).
    travel(pkDownSam, AT.packetDown, 1, 0);
    if (row11) fillRow(dots(S, row11), [AT.packetDown[1], AT.packetDown[1] + 0.018], { '--e': 1 });

    // The offline line rolls out, the synced layer takes over, Synced rolls in.
    if (sync1) tl.to(sync1, { opacity: 0, yPercent: -60, duration: span(AT.syncOut), ease: 'power2.in' }, AT.syncOut[0]);
    const sync2 = one(L2, '[data-sync-line]');
    const g12 = dots(L2, row12);
    dotState(g12, 'today');
    if (sync2) gsap.set(sync2, { opacity: 0, yPercent: 60 });
    tl.set(L1, { opacity: 0 }, AT.swap);
    tl.set(L2, { opacity: 1 }, AT.swap);
    if (sync2) {
      tl.to(sync2, { opacity: 1, yPercent: 0, duration: span(AT.syncedIn), ease: 'power3.out' }, AT.syncedIn[0]);
      const check = one(sync2, 'svg');
      if (check) tl.fromTo(check, { scale: 0.4 }, { scale: 1, duration: span(AT.syncedIn), ease: 'back.out(2.4)', immediateRender: false }, AT.syncedIn[0] + 0.004);
    }
    // Row 12 was Sam's first: gold → green on your phone (the green is laid under the gold
    // first, so each dot turns cleanly instead of through a muddy mix over white).
    tl.to(g12, { '--e': 1, duration: 0.002 }, AT.green[0]);
    fillRow(g12, AT.green, { '--g': 0 });
    const banner = one(L2, '[data-banner]');
    if (banner) {
      tl.fromTo(banner, { opacity: 0, yPercent: 40, scale: 0.96 }, { opacity: 1, yPercent: 0, scale: 1, duration: span(AT.banner), ease: 'power3.out' }, AT.banner[0]);
      // [.6, .66] the banner goes.
      tl.to(banner, { opacity: 0, yPercent: 30, scale: 0.98, duration: span(AT.bannerOut), ease: 'power2.in' }, AT.bannerOut[0]);
    }

    // ================= [.66, .9] the owner's phone =================
    tl.to(chip('sam'), { opacity: 0, duration: span(AT.relabel) * 0.5 }, AT.relabel[0]);
    tl.fromTo(chip('owner'), { opacity: 0, y: 4 }, { opacity: 1, y: 0, duration: span(AT.relabel) * 0.6, ease: 'power2.out' }, AT.relabel[0] + span(AT.relabel) * 0.4);
    util.crossfade(tl, S, T, AT.team[0], span(AT.team));
    tl.to([wires, nosig], { opacity: 0, duration: span(AT.wiresDim) }, AT.wiresDim[0]);
    // Mobile: the server sits right where the owner's name tag goes, so it steps out fully.
    if (srvIn) tl.to(srvIn, { opacity: isDesk ? 0.4 : 0, duration: span(AT.wiresDim) }, AT.wiresDim[0]);
    // The z swap: the second phone comes in front of yours. Desktop: above the stage phone (the
    // frame goes over the stage); mobile: the rig goes over the section phone's cell.
    tl.set(peek, { zIndex: 4 }, AT.zSwap);
    if (isDesk && ctx.frame) tl.set(ctx.frame, { zIndex: 7 }, AT.zSwap);
    if (!isDesk) tl.set(rig, { zIndex: 3 }, AT.zSwap);
    tl.to(peek, { ...pose(P.front), duration: span(AT.forward), ease: 'power2.inOut' }, AT.forward[0]);
    const rest = cam.length ? PULL.scale : 1;
    if (ctx.phone) tl.to(ctx.phone, { scale: rest * 0.92, opacity: 0.7, duration: span(AT.forward), ease: 'power2.inOut' }, AT.forward[0]);
    tl.to(chip('you'), { opacity: 0, duration: 0.02 }, AT.forward[0]);

    // This week's rows come in and their hours roll up from the ledger.
    const rows = all(T, '[data-team-row]');
    if (rows.length) tl.fromTo(rows, { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: 0.03, stagger: 0.012, ease: 'power2.out' }, AT.rows[0]);
    const hours: Array<[HTMLElement, string]> = [];
    rows.forEach((row, i) => {
      const h = one(row, '[data-hours]');
      const r = TEAM.find((m) => m.name === row.dataset.teamRow);
      if (!h || !r) return;
      hours.push([h, r.hours]);
      util.odometer(tl, h, 0, toMinutes(r.hours), AT.rows[0] + 0.008 + i * 0.012, span(AT.rows) - 0.034, fmtHours);
    });
    const after = [one(T, '[data-team-total]'), one(T, '[data-invite]'), one(T, '[data-fields-row]')].filter(Boolean);
    if (after.length) tl.fromTo(after, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: span(AT.invite) - 0.008, stagger: 0.004, ease: 'power2.out' }, AT.invite[0]);
    if (workers) tl.fromTo(workers, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: span(AT.workers), ease: 'power2.out' }, AT.workers[0]);
    // Beat 5: the farm's own server (mobile: the owner's tag makes way for it).
    if (!isDesk) tl.to(chip('owner'), { opacity: 0, duration: 0.016 }, AT.serverLit[0] - 0.016);
    if (srvIn) tl.to(srvIn, { opacity: 1, duration: 0.02 }, AT.serverLit[0]);
    pulseAt(AT.serverLit);

    // ================= [.9, 1] back to rest =================
    tl.to(peek, { opacity: 0, duration: span(AT.exit) * 0.5, ease: 'power1.in' }, AT.exit[0]);
    tl.to(peek, { ...pose(P.hidden), duration: span(AT.exit), ease: 'power2.inOut' }, AT.exit[0]);
    tl.set(peek, { zIndex: -1 }, AT.exit[0] + span(AT.exit) * 0.55);
    if (isDesk && ctx.frame) tl.set(ctx.frame, { zIndex: 'auto' }, AT.exit[0] + span(AT.exit) * 0.55);
    if (!isDesk) tl.set(rig, { zIndex: 1 }, AT.exit[0] + span(AT.exit) * 0.55);
    if (ctx.phone) tl.to(ctx.phone, { scale: 1, yPercent: 0, opacity: 1, duration: span(AT.exit), ease: 'power2.inOut' }, AT.exit[0]);
    if (cam.length) tl.to(rig, { scale: 1, yPercent: 0, duration: span(AT.exit), ease: 'power2.inOut' }, AT.exit[0]);
    tl.to([chip('owner'), workers, srvIn].filter(Boolean), { opacity: 0, duration: span(AT.exitDecor) }, AT.exitDecor[0]);

    // ---- Wires: drawn from the real layout, redrawn on every refresh ----
    const slot = isDesk ? (ctx.stage?.phone.parentElement ?? null) : null;
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
      // Offsets, not rects: the rig itself may be scaled by the camera pull at this moment.
      const srv = { x: 0, y: 0 };
      for (let e: HTMLElement | null = srvAnchor; e && e !== rig; e = e.offsetParent as HTMLElement | null) {
        srv.x += e.offsetLeft;
        srv.y += e.offsetTop;
      }
      const A = isDesk ? ANCHOR.desk : ANCHOR.mob;
      // Sam's wire comes out of his name tag (top centre), wherever the tag sits on his phone.
      const tag = chip('sam');
      const sam = tag
        ? posePoint({ w, h }, P.rest, (tag.offsetLeft + tag.offsetWidth / 2) / w, (tag.offsetTop + 1) / h)
        : posePoint({ w, h }, P.rest, A.sam, 0.004);
      const alex = { x: A.alex * w, y: 1 };
      const dS = wirePath(sam, srv);
      const dA = wirePath(alex, srv);
      wire.sam.setAttribute('d', dS);
      wire.alex.setAttribute('d', dA);
      reveal.sam?.setAttribute('d', dS);
      reveal.alex?.setAttribute('d', dA);
      if (nosigAt) {
        const mid = wire.alex.getPointAtLength(wire.alex.getTotalLength() * 0.5);
        nosigAt.setAttribute('transform', `translate(${mid.x.toFixed(1)} ${mid.y.toFixed(1)})`);
      }
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
    };
  },
  { dayStart: DAY_FROM },
);
