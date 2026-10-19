/**
 * THE FIELD SCENE (2:15 PM). Spec: jq '.sections[] | select(.id=="field") | .animation' docs/landing/brief.json
 *
 * One scrubbed timeline (normalized 0–1). The canvas plays the map team's choreography
 * (fieldstate.ts: sceneState(p), BEATS) through one proxy tween, so it redraws only when
 * progress changes; the page around it follows src/sections/field/plan.ts (pure, tested):
 *
 *   [0, .1]     the stage phone fades to 0 and .96 while the tilted field fades in under it (desktop)
 *   [.1, .3]    it flattens; trees 0 → 8,540 and shaped 0 → 2,190 roll; strip, chip and legend fade in
 *   [.3, .52]   block 2 rows 14 → 36 flip to gold, today counts up ten a row; card 1
 *   [.52, .72]  zoom to block 2 rows 28–40; row 37 touched, filled, Undo tapped, back to rings; card 2
 *   [.72, .88]  next season: fills fade to rings and the counts to zero, the note stays and pulses; card 3
 *   [.88, 1]    this season again, the camera pulls out, the map fades and the phone comes back
 *
 * The heading fades by position, not progress: each line goes just before it reaches the field
 * frame's own content (a mask, both layouts). On phones the map owns the frame under the counter
 * strip; the legend and the card sheet lie over its foot (with a scrim), and the close-up rises
 * just enough for rows 28–40 to clear each card.
 *
 * Performance (375×667, 4× CPU throttle, Chromium): the moving layers are promoted only while the
 * section is near (.fm-live: will-change), the phone comes back with opacity only, and the canvas
 * stops redrawing once the figure has faded out. Measured on a heavily loaded build Mac, so the
 * numbers are noisy: see the PR notes.
 *
 * Leaves the stage phone at rest (opacity 1, scale 1) at 0 and 1.
 */
import { registerScene } from '../scene.ts';
import { MOMENTS, fmtCount } from '../../data/ledger.ts';
import { ensureFieldMap, toScreen, zoomView } from '../fieldmap.ts';
import { BEATS, DEMO_ROW, DOT_R, TODAY_SCALE, ZOOM_TARGET, dotCenter, finalState, sceneState, targetRect } from '../fieldstate.ts';
import { setOdometer } from '../odometer.ts';
import { CARDS, COUNTS, SHEET, WIN, countsAt, headCut, phoneCloseUp, riseAt, sheetTopAt, type Counts, type Win } from '../../sections/field/plan.ts';

const len = (w: Win) => w[1] - w[0];
/** Gold dots are 20% larger: the edge of any dot in the close-up, in pitches from its centre. */
const DOT_EDGE = DOT_R * TODAY_SCALE;

registerScene(
  'field',
  (ctx) => {
    const { tl, day, q, q1, isDesk, phone, util, beats, section, frame } = ctx;

    // The field holds at 2:15 PM, the minute in its eyebrow and its tag.
    day.to(tl, MOMENTS.field, 0, 0.02, MOMENTS.field);

    const fig = q1<HTMLElement>('[data-field-fig]');
    const cam = q1<HTMLElement>('[data-field-cam]');
    const canvas = q1<HTMLCanvasElement>('[data-field-fig] canvas[data-fieldmap]');
    const haze = q1<HTMLElement>('[data-field-haze]');
    const top = q1<HTMLElement>('[data-field-fig] .fm-top');
    const foot = q1<HTMLElement>('[data-field-fig] .fm-foot');
    const legend = q1<HTMLElement>('[data-field-legend]');
    const sheet = q1<HTMLElement>('[data-field-sheet]');
    const seasonCol = q1<HTMLElement>('[data-field-season-col]');
    const season = q1<HTMLElement>('[data-field-season]');
    const noteKey = q1<HTMLElement>('[data-field-legend-note] .sw-flag');
    const undo = q1<HTMLElement>('[data-field-undo]');
    const overlay = undo?.parentElement ?? null;
    const cards = q<HTMLElement>('[data-field-card]');
    const cardBox = q1<HTMLElement>('[data-field-cards]');
    const shot = q1<HTMLElement>('.fm-shot');
    const edges = q1<HTMLElement>('[data-field-edges]');
    const head = beats[0] ?? null;
    const countEls = {
      trees: q1<HTMLElement>('[data-field-count="trees"]'),
      shaped: q1<HTMLElement>('[data-field-count="shaped"]'),
      today: q1<HTMLElement>('[data-field-count="today"]'),
    };

    // While the section is near, its moving layers get compositor layers of their own (CSS: .fm-live).
    ctx.trigger({ trigger: section, start: 'top bottom', end: 'bottom top', toggleClass: { targets: section, className: 'fm-live' } });

    /** px from the frame's top to an element's top (offsetParent chain; transforms ignored). */
    const inFrame = (el: HTMLElement | null) => {
      let y = 0;
      for (let e: HTMLElement | null = el; e && e !== frame; e = e.offsetParent as HTMLElement | null) y += e.offsetTop;
      return y;
    };

    // ---- The heading: each line fades just before it reaches the top of the field's own content
    // (the counter strip under the header; on phones the sticky frame's top, under the time chip).
    if (head) {
      let docTop = 0;
      let line = 0;
      let cut = -1;
      const measure = () => {
        docTop = head.getBoundingClientRect().top + window.scrollY;
        const stuck = frame ? parseFloat(getComputedStyle(frame).top) || 0 : 0;
        line = stuck + inFrame(fig) + (isDesk && top ? top.offsetHeight : 0);
      };
      const paint = (scroll: number) => {
        const c = Math.round(headCut(line, docTop - scroll));
        if (c === cut) return;
        cut = c;
        head.style.setProperty('--cut', `${c}px`);
      };
      ctx.trigger({
        trigger: head,
        start: 'top bottom',
        end: 'bottom top',
        onRefresh: (self) => {
          measure();
          paint(self.scroll());
        },
        onUpdate: (self) => paint(self.scroll()),
      });
      measure();
      paint(window.scrollY);
      // Desktop: a tall heading on a short screen may still have lines low down as the field
      // flattens under them; those go too.
      if (isDesk) tl.fromTo(head, { opacity: 1 }, { opacity: 0, duration: len(WIN.headOut), ease: 'power1.in' }, WIN.headOut[0]);
    }

    // ---- [0, .1] The stage phone steps aside (desktop) and the field fades in under it; on phones
    // the section's own phone comes back at the end (opacity only: scaling a DOM phone re-rasterises it).
    if (isDesk && phone) {
      tl.fromTo(phone, { opacity: 1, scale: 1 }, { opacity: 0, scale: 0.96, duration: len(WIN.phoneOut), ease: 'power1.in' }, WIN.phoneOut[0]);
      tl.fromTo(
        phone,
        { opacity: 0, scale: 0.96 },
        { opacity: 1, scale: 1, duration: len(WIN.phoneIn), ease: 'power2.out', immediateRender: false },
        WIN.phoneIn[0],
      );
    } else if (shot) {
      tl.fromTo(shot, { opacity: 0 }, { opacity: 1, duration: len(WIN.phoneIn), ease: 'power1.out' }, WIN.phoneIn[0]);
    }

    // ---- The field: tilted to the horizon (dot rows read as tree rows running away), then flat.
    if (cam) {
      if (isDesk) tl.fromTo(cam, { opacity: 0 }, { opacity: 1, duration: len(WIN.camIn), ease: 'power1.out' }, WIN.camIn[0]);
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

    // ---- The canvas, the counter strip and (phones) the close-up's rise, driven by one progress value.
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
    /** Phones: how far the close-up rises for card 2 and for card 3, and each card's top (px; layout() measures them). */
    let dz: readonly [number, number] = [0, 0];
    let tops: readonly [number, number, number] | null = null;
    let rise = NaN;
    let sheetY = NaN;
    const proxy = { p: 0 };
    const update = () => {
      const p = proxy.p;
      writeCounts(countsAt(p));
      // Once the figure has faded out there is nothing to draw (it redraws on the way back).
      if (p > WIN.mapOut[1]) return;
      map?.setProgress(p);
      if (!isDesk && cam) {
        const r = Math.round(riseAt(p, map ? map.state.camera : sceneState(p).camera, dz) * 2) / 2;
        if (r !== rise) {
          rise = r;
          cam.style.setProperty('--rise', `${r}px`);
        }
        // The scrim follows the card that shows (its height fits the tallest; it slides down for the others).
        if (sheet && tops) {
          const y = Math.round(sheetTopAt(p, tops) - Math.min(...tops));
          if (y !== sheetY) {
            sheetY = y;
            sheet.style.translate = `0 ${y}px`;
          }
        }
      }
    };
    tl.fromTo(proxy, { p: 0 }, { p: 1, duration: 1, ease: 'none', onUpdate: update }, 0);

    // ---- The close-up's soft edges: up before the camera really moves, gone once it is back.
    if (edges) {
      tl.fromTo(edges, { opacity: 0 }, { opacity: 1, duration: len(WIN.edgesIn), ease: 'power1.inOut' }, WIN.edgesIn[0]);
      tl.to(edges, { opacity: 0, duration: len(WIN.edgesOut), ease: 'power1.inOut' }, WIN.edgesOut[0]);
    }

    // ---- The three cards, one at a time (on phones over a scrim at the foot of the map).
    cards.forEach((card, i) => {
      const w = CARDS[i];
      if (!w) return;
      tl.fromTo(card, { opacity: 0, y: 14 }, { opacity: 1, y: 0, duration: len(w.in), ease: 'power2.out' }, w.in[0]);
      tl.to(card, { opacity: 0, y: -8, duration: len(w.out), ease: 'power2.in' }, w.out[0]);
    });
    if (sheet && !isDesk) {
      tl.fromTo(sheet, { opacity: 0 }, { opacity: 1, duration: len(SHEET.in), ease: 'power1.out' }, SHEET.in[0]);
      tl.to(sheet, { opacity: 0, duration: len(SHEET.out), ease: 'power1.in' }, SHEET.out[0]);
    }

    // ---- Layout: the Undo chip, the vignette and (phones) the close-up's rise and the season chip.
    let ro: ResizeObserver | null = null;
    if (canvas) {
      const box = canvas.parentElement ?? canvas;
      const target = targetRect(ZOOM_TARGET);
      const view = () => {
        const W = box.clientWidth;
        const H = box.clientHeight;
        return W && H ? { W, H, v: zoomView(ZOOM_TARGET, W, H, Math.min(2, window.devicePixelRatio || 1)) } : null;
      };
      type Z = NonNullable<ReturnType<typeof view>>;
      const besideAt = (z: Z) => {
        const end = dotCenter(DEMO_ROW.block, DEMO_ROW.row, 10);
        const p = toScreen(z.v, z.W, z.H, end.x + 0.95, end.y);
        return { ...p, fits: p.x + (undo?.offsetWidth || 96) + 6 <= z.W };
      };

      // Beside row 37 when the canvas has room; otherwise a toast in the legend's place (the app shows
      // its toasts just above its legend too). Decided on every layout, so a resize can switch it.
      let toast: boolean | null = null;
      const setToast = (on: boolean) => {
        if (on === toast || !undo) return;
        toast = on;
        fig?.toggleAttribute('data-toast', on);
        const home = on ? foot : overlay;
        if (home && undo.parentElement !== home) home.appendChild(undo);
      };
      const place = (z: Z) => {
        if (!undo) return;
        const b = besideAt(z);
        setToast(!b.fits || !foot);
        if (!toast || !foot) {
          undo.style.setProperty('--ux', `${b.x.toFixed(1)}px`);
          undo.style.setProperty('--uy', `${b.y.toFixed(1)}px`);
          return;
        }
        // Centred on the block, level with the legend.
        const w = undo.offsetWidth || 96;
        const mid = toScreen(z.v, z.W, z.H, dotCenter(DEMO_ROW.block, DEMO_ROW.row, 5.5).x, 0).x + (cam?.offsetLeft ?? 0) - foot.offsetLeft;
        const x = Math.max(4, Math.min(foot.clientWidth - w - 4, mid - w / 2));
        const y = legend ? legend.offsetTop + legend.offsetHeight / 2 : foot.clientHeight / 2;
        undo.style.setProperty('--ux', `${x.toFixed(1)}px`);
        undo.style.setProperty('--uy', `${y.toFixed(1)}px`);
      };

      // Phones: the map owns the frame, so rows 28–40 would sit under the card sheet. Measure where
      // the cards and the strip are and let the close-up rise just enough (plan.ts: phoneCloseUp).
      const phoneLayout = (z: Z) => {
        if (isDesk || !fig || !cam || !frame) return;
        frame.style.setProperty('--fm-foot', `${foot?.offsetHeight ?? 28}px`);
        const figTop = inFrame(fig);
        const camTop = cam.offsetTop;
        const yOf = (row: number, edge: number) => camTop + toScreen(z.v, z.W, z.H, 0, dotCenter(ZOOM_TARGET.block, row, 1).y + edge).y;
        const cardsBottom = cardBox ? inFrame(cardBox) + cardBox.offsetHeight - figTop : fig.clientHeight;
        const cardTop = (i: number) => cardsBottom - (cards[i]?.offsetHeight ?? 0);
        const stripBottom = top ? top.offsetTop + top.offsetHeight : 0;
        const r = phoneCloseUp({
          targetTop: yOf(ZOOM_TARGET.from, -DOT_EDGE),
          targetBottom: yOf(ZOOM_TARGET.to, DOT_EDGE),
          stripBottom,
          cardTops: [cardTop(1), cardTop(2)],
          chipH: season?.offsetHeight ?? 30,
        });
        dz = r.dz;
        season?.style.setProperty('--season-top', `${(r.chipTop - (top?.offsetTop ?? 0)).toFixed(1)}px`);
        // The scrim starts just above the card that shows (sized for the tallest; update() slides it).
        tops = [cardTop(0), cardTop(1), cardTop(2)];
        sheet?.style.setProperty('--sheet-h', `${Math.max(0, fig.clientHeight - Math.min(...tops) + 16).toFixed(0)}px`);
        rise = NaN;
        sheetY = NaN;
      };

      // The vignette paints the stage tint: line its gradient up with the viewport, and keep its
      // fades inside the context around rows 28–40 (never over the rows or their numbers).
      const alignEdges = (z: Z) => {
        if (!edges || !frame) return;
        const y = inFrame(box);
        const stuck = parseFloat(getComputedStyle(frame).top) || 0;
        const s = z.v.s;
        const ex = Math.max(8, Math.min(112, (z.W - target.w * s) / 2 + 0.6 * s));
        const ey = Math.max(8, Math.min(72, (z.H - target.h * s) / 2 + 0.7 * s));
        edges.style.setProperty('--edge-y', `${-(y + stuck - 1)}px`);
        edges.style.setProperty('--edge-vh', `${window.innerHeight}px`);
        edges.style.setProperty('--ex', `${ex.toFixed(1)}px`);
        edges.style.setProperty('--ey', `${ey.toFixed(1)}px`);
      };
      const layout = () => {
        const z = view();
        if (!z) return;
        phoneLayout(z);
        place(z);
        alignEdges(z);
        update();
      };
      layout();
      ro = new ResizeObserver(layout);
      ro.observe(box);

      if (undo) {
        tl.fromTo(undo, { opacity: 0, scale: 0.88, y: 6 }, { opacity: 1, scale: 1, y: 0, duration: len(WIN.undoIn), ease: 'back.out(1.6)' }, WIN.undoIn[0]);
        util.tap(tl, undo, WIN.undoTap - 0.012, { dur: 0.03, shake: false });
        tl.to(undo, { opacity: 0, scale: 0.94, duration: len(WIN.undoOut), ease: 'power2.in' }, WIN.undoOut[0]);
        // As a toast it takes the legend's place for a moment (CSS reads --toast-dim only under [data-toast]).
        if (foot) {
          tl.fromTo(foot, { '--toast-dim': 0 }, { '--toast-dim': 1, duration: len(WIN.undoIn), ease: 'power1.out' }, WIN.undoIn[0] - 0.004);
          tl.to(foot, { '--toast-dim': 0, duration: len(WIN.undoOut), ease: 'power1.in' }, WIN.undoOut[1]);
        }
      }
    } else update();

    // ---- Next season: the chip rolls, the note's key pulses with the flag on the map, then back.
    if (seasonCol) {
      tl.fromTo(seasonCol, { yPercent: 0 }, { yPercent: -50, duration: 0.035, ease: 'power2.inOut' }, BEATS.seasonOut[0]);
      tl.to(seasonCol, { yPercent: 0, duration: 0.025, ease: 'power2.inOut' }, BEATS.seasonIn[0]);
    }
    if (season) {
      // On phones the chip only shows for this beat, just above row 28 (layout() places it).
      if (!isDesk) {
        tl.fromTo(season, { opacity: 0, y: -6 }, { opacity: 1, y: 0, duration: 0.025, ease: 'power2.out' }, WIN.seasonChip[0]);
        tl.to(season, { opacity: 0, duration: 0.02, ease: 'power1.in' }, WIN.seasonChip[1]);
      }
      tl.to(season, { keyframes: { scale: [1, 1.06, 1] }, duration: 0.03, ease: 'none' }, BEATS.seasonOut[0]);
      tl.to(season, { keyframes: { scale: [1, 1.06, 1] }, duration: 0.025, ease: 'none' }, BEATS.seasonIn[0]);
    }
    if (noteKey) tl.to(noteKey, { keyframes: { scale: [1, 1.4, 1] }, duration: 0.05, ease: 'none', transformOrigin: '30% 85%' }, BEATS.pulse[0] + 0.01);

    // ---- [.88, 1] The camera pulls out (canvas), then the field fades and the phone is back.
    if (fig) {
      if (isDesk) tl.to(fig, { opacity: 0, scale: 0.97, duration: len(WIN.mapOut), ease: 'power1.in' }, WIN.mapOut[0]);
      else tl.to(fig, { opacity: 0, duration: len(WIN.mapOut), ease: 'power1.in' }, WIN.mapOut[0]);
    }

    return () => {
      ro?.disconnect();
      if (undo && overlay && undo.parentElement !== overlay) overlay.appendChild(undo);
      fig?.removeAttribute('data-toast');
      head?.style.removeProperty('--cut');
      cam?.style.removeProperty('--rise');
      if (sheet) sheet.style.translate = '';
      frame?.style.removeProperty('--fm-foot');
      section.classList.remove('fm-live');
      map?.draw(finalState('overview'));
      writeCounts({ trees: COUNTS.trees, shaped: COUNTS.shaped, today: COUNTS.today });
    };
  },
  { dayStart: MOMENTS.field },
);
