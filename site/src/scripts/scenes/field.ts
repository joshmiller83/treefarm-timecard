/**
 * THE FIELD SCENE (2:15 PM). Spec: jq '.sections[] | select(.id=="field") | .animation' docs/landing/brief.json
 *
 * One scrubbed timeline (normalized 0–1). The canvas plays the map team's choreography
 * (fieldstate.ts: sceneState(p), BEATS) through one proxy tween, so it redraws only when
 * progress changes; the page around it follows src/sections/field/plan.ts (pure, tested):
 *
 *   [0, .1]     the stage phone fades to 0 and .96 (desktop); the field waits, tilted to the horizon
 *   [.1, .3]    it flattens; trees 0 → 8,540 and shaped 0 → 2,190 roll; strip, chip and legend fade in
 *   [.3, .52]   block 2 rows 14 → 36 flip to gold, today counts up ten a row; card 1
 *   [.52, .72]  zoom to block 2 rows 28–40; row 37 touched, filled, Undo tapped, back to rings; card 2
 *   [.72, .88]  next season: fills fade to rings and the counts to zero, the note stays and pulses; card 3
 *   [.88, 1]    this season again, the camera pulls out, the map fades and the phone comes back
 *
 * Leaves the stage phone at rest (opacity 1, scale 1) at 0 and 1.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS, fmtCount } from '../../data/ledger.ts';
import { ensureFieldMap, toScreen, zoomView } from '../fieldmap.ts';
import { BEATS, DEMO_ROW, ZOOM_TARGET, dotCenter, finalState } from '../fieldstate.ts';
import { setOdometer } from '../odometer.ts';
import { CARDS, COUNTS, WIN, countsAt, type Counts, type Win } from '../../sections/field/plan.ts';

const len = (w: Win) => w[1] - w[0];

registerScene(
  'field',
  (ctx) => {
    const { tl, day, q, q1, isDesk, phone, util, beats } = ctx;

    // The DayClock holds where the lock-screen beat ended (2:16 PM); notes picks up from there.
    day.to(tl, MOMENTS.island, 0, 0.02, MOMENTS.island);

    const fig = q1<HTMLElement>('[data-field-fig]');
    const cam = q1<HTMLElement>('[data-field-cam]');
    const canvas = q1<HTMLCanvasElement>('[data-field-fig] canvas[data-fieldmap]');
    const haze = q1<HTMLElement>('[data-field-haze]');
    const top = q1<HTMLElement>('[data-field-fig] .fm-top');
    const foot = q1<HTMLElement>('[data-field-fig] .fm-foot');
    const seasonCol = q1<HTMLElement>('[data-field-season-col]');
    const season = q1<HTMLElement>('[data-field-season]');
    const noteKey = q1<HTMLElement>('[data-field-legend-note] .sw-flag');
    const undo = q1<HTMLElement>('[data-field-undo]');
    const cards = q<HTMLElement>('[data-field-card]');
    const shot = q1<HTMLElement>('.fm-shot');
    const edges = q1<HTMLElement>('[data-field-edges]');
    const head = beats[0] ?? null;
    const countEls = {
      trees: q1<HTMLElement>('[data-field-count="trees"]'),
      shaped: q1<HTMLElement>('[data-field-count="shaped"]'),
      today: q1<HTMLElement>('[data-field-count="today"]'),
    };

    // ---- [0, .1] The stage phone steps aside (desktop); on phones the section's own comes back at the end.
    if (isDesk && phone) {
      tl.fromTo(phone, { opacity: 1, scale: 1 }, { opacity: 0, scale: 0.96, duration: len(WIN.phoneOut), ease: 'power1.in' }, WIN.phoneOut[0]);
      tl.fromTo(
        phone,
        { opacity: 0, scale: 0.96 },
        { opacity: 1, scale: 1, duration: len(WIN.phoneIn), ease: 'power2.out', immediateRender: false },
        WIN.phoneIn[0],
      );
    } else if (shot) {
      tl.fromTo(shot, { opacity: 0, scale: 0.96 }, { opacity: 1, scale: 1, duration: len(WIN.phoneIn), ease: 'power2.out' }, WIN.phoneIn[0]);
    }

    // The heading scrolls up over where the counter strip arrives: let it go first (desktop).
    if (isDesk && head) tl.fromTo(head, { opacity: 1 }, { opacity: 0, duration: len(WIN.headOut), ease: 'power1.in' }, WIN.headOut[0]);

    // ---- The field: tilted to the horizon (dot rows read as tree rows running away), then flat.
    if (cam) {
      tl.fromTo(
        cam,
        { transformPerspective: 1000, rotationX: isDesk ? 62 : 55, scale: 1.6, yPercent: isDesk ? 20 : 14, force3D: true },
        { rotationX: 0, scale: 1, yPercent: 0, duration: len(WIN.flatten), ease: 'power2.inOut' },
        WIN.flatten[0],
      );
    }
    if (haze) tl.fromTo(haze, { opacity: 1 }, { opacity: 0, duration: len(WIN.haze), ease: 'power1.in' }, WIN.haze[0]);
    // (Separate tweens, not a stagger: a staggered fromTo only renders its first from-state at build.)
    // The legend waits a little longer, until the field has nearly settled above it.
    [top, foot].forEach((el, i) => {
      if (el) tl.fromTo(el, { opacity: 0, y: 10 }, { opacity: 1, y: 0, duration: len(WIN.chrome) - 0.05, ease: 'power2.out' }, WIN.chrome[0] + i * 0.05);
    });

    // ---- The canvas and the counter strip, driven by one progress value.
    const map = canvas ? ensureFieldMap(canvas) : null;
    const shown: Partial<Record<keyof Counts, string>> = {};
    const writeCounts = (c: Counts) => {
      for (const k of ['trees', 'shaped', 'today'] as const) {
        const el = countEls[k];
        const text = fmtCount(c[k]);
        if (!el || shown[k] === text) continue;
        shown[k] = text;
        setOdometer(el, text);
      }
    };
    const proxy = { p: 0 };
    const update = () => {
      map?.setProgress(proxy.p);
      writeCounts(countsAt(proxy.p));
    };
    tl.fromTo(proxy, { p: 0 }, { p: 1, duration: 1, ease: 'none', onUpdate: update }, 0);
    update();

    // ---- The close-up's soft edges follow the camera.
    if (edges) {
      tl.fromTo(edges, { opacity: 0 }, { opacity: 1, duration: len(WIN.edgesIn), ease: 'power1.inOut' }, WIN.edgesIn[0]);
      tl.to(edges, { opacity: 0, duration: len(WIN.edgesOut), ease: 'power1.inOut' }, WIN.edgesOut[0]);
    }

    // ---- The three cards, one at a time.
    cards.forEach((card, i) => {
      const w = CARDS[i];
      if (!w) return;
      tl.fromTo(card, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: len(w.in), ease: 'power2.out' }, w.in[0]);
      tl.to(card, { opacity: 0, y: -8, duration: len(w.out), ease: 'power2.in' }, w.out[0]);
    });

    // ---- The Undo chip beside row 37 in the close-up: in, tapped, out (row 37 goes back to rings).
    let ro: ResizeObserver | null = null;
    if (undo && canvas) {
      const box = canvas.parentElement ?? canvas;
      const place = () => {
        const W = box.clientWidth;
        const H = box.clientHeight;
        if (!W || !H) return;
        const v = zoomView(ZOOM_TARGET, W, H, Math.min(2, window.devicePixelRatio || 1));
        const end = dotCenter(DEMO_ROW.block, DEMO_ROW.row, 10);
        const last = dotCenter(DEMO_ROW.block, ZOOM_TARGET.to, 10);
        const mid = dotCenter(DEMO_ROW.block, ZOOM_TARGET.to, 5.5);
        const right = toScreen(v, W, H, end.x + 0.95, end.y);
        const w = undo.offsetWidth || 96;
        // Beside the row when there is room; on a narrow canvas, centred under the block.
        const beside = right.x + w + 6 <= W;
        const p = beside ? right : toScreen(v, W, H, mid.x, last.y + 1.25);
        undo.style.setProperty('--ux', `${(beside ? p.x : p.x - w / 2).toFixed(1)}px`);
        undo.style.setProperty('--uy', `${p.y.toFixed(1)}px`);
      };
      // The vignette paints the stage tint: line its gradient up with the viewport.
      const frame = ctx.frame;
      const alignEdges = () => {
        if (!edges || !frame) return;
        let y = 0;
        for (let el: HTMLElement | null = box; el && el !== frame; el = el.offsetParent as HTMLElement | null) y += el.offsetTop;
        const stuck = parseFloat(getComputedStyle(frame).top) || 0;
        edges.style.setProperty('--edge-y', `${-(y + stuck - 1)}px`);
        edges.style.setProperty('--edge-vh', `${window.innerHeight}px`);
      };
      const layout = () => {
        place();
        alignEdges();
      };
      layout();
      ro = new ResizeObserver(layout);
      ro.observe(box);
      tl.fromTo(undo, { opacity: 0, scale: 0.88, y: 6 }, { opacity: 1, scale: 1, y: 0, duration: len(WIN.undoIn), ease: 'back.out(1.6)' }, WIN.undoIn[0]);
      util.tap(tl, undo, WIN.undoTap - 0.012, { dur: 0.03, shake: false });
      tl.to(undo, { opacity: 0, scale: 0.94, duration: len(WIN.undoOut), ease: 'power2.in' }, WIN.undoOut[0]);
    }

    // ---- Next season: the chip rolls, the note's key pulses with the flag on the map, then back.
    if (seasonCol) {
      tl.fromTo(seasonCol, { yPercent: 0 }, { yPercent: -50, duration: 0.035, ease: 'power2.inOut' }, BEATS.seasonOut[0]);
      tl.to(seasonCol, { yPercent: 0, duration: 0.025, ease: 'power2.inOut' }, BEATS.seasonIn[0]);
    }
    if (season) {
      // On phones the chip only shows for this beat (it would cover the overview's top row of blocks).
      if (!isDesk) {
        tl.fromTo(season, { opacity: 0, y: -6 }, { opacity: 1, y: 0, duration: 0.025, ease: 'power2.out' }, WIN.seasonChip[0]);
        tl.to(season, { opacity: 0, duration: 0.02, ease: 'power1.in' }, WIN.seasonChip[1]);
      }
      tl.to(season, { keyframes: { scale: [1, 1.06, 1] }, duration: 0.03, ease: 'none' }, BEATS.seasonOut[0]);
      tl.to(season, { keyframes: { scale: [1, 1.06, 1] }, duration: 0.025, ease: 'none' }, BEATS.seasonIn[0]);
    }
    if (noteKey) tl.to(noteKey, { keyframes: { scale: [1, 1.4, 1] }, duration: 0.05, ease: 'none', transformOrigin: '30% 85%' }, BEATS.pulse[0] + 0.01);

    // ---- [.88, 1] The camera pulls out (canvas), then the field fades and the phone is back.
    if (fig) tl.to(fig, { opacity: 0, scale: 0.97, duration: len(WIN.mapOut), ease: 'power1.in' }, WIN.mapOut[0]);

    return () => {
      ro?.disconnect();
      map?.draw(finalState('overview'));
      writeCounts({ trees: COUNTS.trees, shaped: COUNTS.shaped, today: COUNTS.today });
    };
  },
  { dayStart: MOMENTS.island },
);
