import { describe, expect, it } from 'vitest';
import { liveActivityAt, MOMENTS, rowsAt, treesAt } from '../../data/ledger.ts';
import { cardHeight, LA } from '../../components/system/lockscreen/activity.ts';
import {
  BEFORE,
  calloutWindows,
  CALLOUTS,
  CARD,
  CARD_CENTER,
  CUE,
  deskLayout,
  deskZoom,
  FRAME,
  ISLAND_AT,
  ISLAND_DESK_W,
  ISLAND_ORIGIN,
  ISLAND_PHONE_EDGE,
  ISLAND_PT,
  islandZoom,
  MOB_CAPTION,
  MOB_CAPTION_ISLAND,
  mobZoom,
  ORIGIN,
  phoneLabel,
  PIN_PT,
  PIN_PX,
  ROWS,
  separate,
  slots,
  T,
  TAPPED,
  ZOOM,
} from './model.ts';

describe('the story the section tells (from the ledger)', () => {
  it('starts at 2:01 with rows 35–37 and 212 trees, and steps to 2:14', () => {
    expect(BEFORE.rows).toEqual(rowsAt(MOMENTS.status));
    expect(BEFORE.trees).toBe(treesAt(MOMENTS.status));
    expect(BEFORE.trees).toBe(212);
    const at214 = liveActivityAt(MOMENTS.lockScreen);
    expect(at214.state).toBe('working');
    expect(at214.worked).toBe('6:27:00');
    expect(at214.trees).toBe(220);
    expect(at214.rows).toEqual([36, 37, 38]);
    // The step is one row: Row 35 leaves on the left as row 38 arrives.
    expect(at214.rows[0]).toBe(BEFORE.rows[0] + 1);
  });

  it('after the tap reads Row 37, Row 38, Row 39, Break and 230 trees', () => {
    expect(TAPPED.state).toBe('tapped');
    expect(TAPPED.rows).toEqual([37, 38, 39]);
    expect(TAPPED.trees).toBe(230);
    expect(TAPPED.undoRow).toBe(36);
    expect(TAPPED.worked).toBe('6:27:00');
  });

  it('opens the island 10 seconds after 2:16 (6:29:10)', () => {
    expect(ISLAND_AT).toBeCloseTo(MOMENTS.island + 10 / 60, 6);
  });

  it('builds the brief’s phone label, word for word', () => {
    expect(phoneLabel()).toBe(
      'iPhone lock screen at 2:14 PM. The Time Card Live Activity shows On the clock, 6 hours 27 minutes worked, North field, Block 2, 230 trees this shift, Row 36 marked with Undo, and buttons for row 37, row 38, row 39 and Break. There is no clock-out button.',
    );
  });
});

describe('the card’s geometry', () => {
  it('matches the Live Activity (361 × 159 pt, bottom at y 760)', () => {
    expect(CARD).toEqual({ x: 16, y: 760 - cardHeight, w: 361, h: cardHeight });
    expect(CARD_CENTER.x).toBeCloseTo(196.5, 5);
    expect(CARD_CENTER.y).toBeCloseTo(760 - cardHeight / 2, 5);
  });

  it('puts the zoom origin at the card’s centre, as fractions of the 420 × 879 frame', () => {
    expect(ORIGIN.x).toBeCloseTo(0.5, 6);
    expect(ORIGIN.y).toBeCloseTo((FRAME.inset + CARD_CENTER.y) / FRAME.h, 6);
  });

  it('knows the centre line of each row', () => {
    expect(ROWS.pill).toBeCloseTo(CARD.y + LA.padY + 11, 5);
    expect(ROWS.buttons).toBeCloseTo(LA.bottomY - LA.padY - 23, 5);
    expect(ROWS.pill).toBeLessThan(ROWS.timer);
    expect(ROWS.timer).toBeLessThan(ROWS.trees);
    expect(ROWS.trees).toBeLessThan(ROWS.buttons);
  });
});

describe('callouts', () => {
  it('are six, numbered 1–6, three a side', () => {
    expect(CALLOUTS.map((c) => c.n)).toEqual([1, 2, 3, 4, 5, 6]);
    expect(CALLOUTS.filter((c) => c.side === 'left')).toHaveLength(3);
    expect(CALLOUTS.filter((c) => c.side === 'right')).toHaveLength(3);
  });

  it('use the brief’s words', () => {
    expect(CALLOUTS.map((c) => [c.label, c.sub].filter(Boolean).join(' '))).toEqual([
      'Worked time. Ticks on its own.',
      'On the clock, on lunch or on break.',
      'Your field, your block, your trees.',
      'Big buttons. One tap marks the whole row.',
      'Wrong row? Undo is right there.',
      'No clock-out button. On purpose. A bump in your pocket can’t end your day.',
    ]);
  });

  it('point at targets inside the card', () => {
    for (const c of CALLOUTS) {
      expect(c.target.x).toBeGreaterThan(CARD.x);
      expect(c.target.x).toBeLessThan(CARD.x + CARD.w);
      expect(c.target.y).toBeGreaterThan(CARD.y);
      expect(c.target.y).toBeLessThan(CARD.y + CARD.h);
    }
  });

  it('slots() splits a window evenly', () => {
    const s = slots(0.2, 0.5, 6);
    expect(s[0]).toEqual([0.2, 0.25]);
    expect(s[5]![1]).toBeCloseTo(0.5, 9);
  });

  it('draw 1–4 and 6 in .05 slots over [.2, .45], in that order', () => {
    const w = calloutWindows();
    const order = [1, 2, 3, 4, 6] as const;
    order.forEach((n, i) => {
      expect(w[n][0]).toBeCloseTo(0.2 + i * 0.05, 9);
      expect(w[n][1] - w[n][0]).toBeCloseTo(0.05, 9);
    });
    expect(w[6][1]).toBeCloseTo(0.45, 9);
  });

  it('draw 5 only once the Undo it points at is there, and before the zoom-out', () => {
    const w = calloutWindows();
    const [u0, u1] = CUE.undo;
    expect(CUE.undo[0]).toBeGreaterThan(CUE.tap);
    // The leader reaches its dot when the Undo is at least two thirds in.
    expect(w[5][0]).toBeGreaterThanOrEqual(u0 + ((u1 - u0) * 2) / 3);
    expect(w[5][1]).toBeLessThanOrEqual(CUE.calloutsOut[0]);
    expect(w[5][1]).toBeLessThanOrEqual(T.tap[1]);
  });

  it('all fade out together, done before the card has moved far', () => {
    const [f0, f1] = CUE.calloutsOut;
    expect(f0).toBeCloseTo(T.zoomOut[0], 9);
    expect(f1 - f0).toBeLessThanOrEqual(0.02 + 1e-9);
    // The zoom starts after the fade, and the fade is over in its first ~15%.
    expect(CUE.zoomOut[0]).toBeGreaterThan(f0);
    expect(CUE.zoomOut[1]).toBeCloseTo(T.zoomOut[1], 9);
    expect((f1 - CUE.zoomOut[0]) / (CUE.zoomOut[1] - CUE.zoomOut[0])).toBeLessThan(0.17);
  });
});

describe('the island beat', () => {
  const I = CUE.island;
  const within = (w: readonly [number, number], outer: readonly [number, number]) => {
    expect(w[0]).toBeGreaterThanOrEqual(outer[0] - 1e-9);
    expect(w[1]).toBeLessThanOrEqual(outer[1] + 1e-9);
  };

  it('morphs inside the brief’s windows, the geometry early in each', () => {
    within(I.compact.size, T.compact);
    within(I.expanded.size, T.expanded);
    expect(I.compact.size[1] - I.compact.size[0]).toBeLessThanOrEqual(0.4 * (T.compact[1] - T.compact[0]));
    expect(I.expanded.size[1] - I.expanded.size[0]).toBeLessThanOrEqual(0.3 * (T.expanded[1] - T.expanded[0]));
  });

  it('fades each state’s content in at about 70% of its morph', () => {
    for (const st of [I.compact, I.expanded]) {
      const at = (st.content[0] - st.size[0]) / (st.size[1] - st.size[0]);
      expect(at).toBeGreaterThanOrEqual(0.7);
      expect(at).toBeLessThanOrEqual(0.85);
    }
  });

  it('holds the compact island and the expanded island long enough to read', () => {
    // Fully visible from the end of its fade-in to the start of its fade-out.
    expect(I.compact.out[0] - I.compact.content[1]).toBeGreaterThanOrEqual(0.02 - 1e-9);
    expect(I.expanded.out[0] - I.expanded.content[1]).toBeGreaterThanOrEqual(0.05 - 1e-9);
    expect(I.compact.out[0]).toBeCloseTo(I.expanded.size[0], 9);
    // The review’s checkpoints: compact at .77, expanded at .82 and .855.
    for (const p of [0.77]) expect(p > I.compact.content[1] && p < I.compact.out[0]).toBe(true);
    for (const p of [0.82, 0.855]) expect(p > I.expanded.content[1] && p < I.expanded.out[0]).toBe(true);
  });

  it('collapses in order: content out, island to rest, lock screen back, home screen off', () => {
    expect(I.rest[0]).toBeGreaterThan(I.expanded.out[0]);
    expect(I.rest[0]).toBeLessThan(I.expanded.out[1] + 1e-9);
    expect(I.lock[0]).toBeGreaterThan(I.rest[0]);
    expect(I.homeOff).toBeGreaterThan(I.lock[1]);
    expect(I.lock[1]).toBeLessThanOrEqual(T.collapse[1]);
  });

  it('zooms in on the island as it opens, and back once it has collapsed', () => {
    expect(I.zoomIn[0]).toBeGreaterThanOrEqual(T.zoomOut[1]);
    expect(I.zoomIn[0]).toBeLessThanOrEqual(I.compact.size[0]);
    expect(I.zoomIn[1]).toBeLessThanOrEqual(I.compact.content[1]);
    expect(I.zoomOut[0]).toBeGreaterThanOrEqual(I.expanded.out[1]);
    expect(I.zoomOut[1]).toBeLessThanOrEqual(T.collapse[1]);
  });

  it('brings beat 3, ControlsCard and the footnote in only as the island collapses', () => {
    const C = CUE.controls;
    expect(C.beat[0]).toBeGreaterThanOrEqual(I.expanded.out[0] - 0.005);
    expect(C.card).toBeGreaterThanOrEqual(0.87);
    expect(C.footnote).toBeGreaterThanOrEqual(C.card);
    expect(C.footnote).toBeLessThan(T.collapse[1]);
  });
});

describe('the island close-up', () => {
  it('zooms about the island’s centre (43 u down the 879 u frame)', () => {
    expect(ISLAND_PT.cy).toBe(29.5);
    expect(ISLAND_ORIGIN.x).toBe(0.5);
    expect(ISLAND_ORIGIN.y).toBeCloseTo(43 / 879, 9);
  });

  // Mobile phones: --phone-h-mob = min(52svh, 460px).
  for (const [vw, vh] of [
    [320, 640],
    [375, 667],
    [375, 812],
    [390, 844],
  ] as const) {
    it(`on a ${vw} × ${vh} phone fits the expanded island inside the gutters, at 1.8–2×`, () => {
      const h = Math.min(0.52 * vh, 460);
      const w = (h * 420) / 879;
      const z = islandZoom({ phone: { width: w, height: h }, viewportWidth: vw, gutter: 16, desk: false, top: 10 });
      const ppt = (w / 420) * z.scale;
      expect(z.scale).toBeGreaterThan(1.8);
      expect(z.scale).toBeLessThanOrEqual(2);
      expect(ISLAND_PT.expandedW * ppt).toBeLessThanOrEqual(vw - 32 + 0.01);
      // The zoomed phone itself stays on screen (no sideways scroll on a phone).
      expect(w * z.scale).toBeLessThanOrEqual(vw - 2 * ISLAND_PHONE_EDGE + 0.01);
      // 'Row 37' (13.5 pt) reads at 10px or more (it was 5px at 1×); the gutters cap it at 320.
      expect(13.5 * ppt).toBeGreaterThanOrEqual(10);
      // The island's top lands `top` px under the phone's own top.
      const islandTop = ISLAND_ORIGIN.y * h + z.y - (ISLAND_PT.restH / 2) * ppt;
      expect(islandTop).toBeCloseTo(10, 6);
    });
  }

  it('on desktop leaves a large enough stage phone alone', () => {
    expect(islandZoom({ phone: { width: 335, height: 701 }, viewportWidth: 1440, gutter: 24, desk: true })).toEqual({ scale: 1, y: 0 });
  });

  it('on desktop zooms a small stage phone to ISLAND_DESK_W, in place', () => {
    const z = islandZoom({ phone: { width: 224, height: 468 }, viewportWidth: 1280, gutter: 24, desk: true });
    expect(z.y).toBe(0);
    expect(224 * z.scale).toBeCloseTo(ISLAND_DESK_W, 0);
    expect(islandZoom({ phone: { width: 120, height: 251 }, viewportWidth: 900, gutter: 24, desk: true }).scale).toBe(2);
  });

  it('never shrinks, and survives an unmeasured phone', () => {
    expect(islandZoom({ phone: { width: 0, height: 0 }, viewportWidth: 375, gutter: 16, desk: false, top: 10 })).toEqual({ scale: 1, y: 0 });
    expect(islandZoom({ phone: { width: 460, height: 963 }, viewportWidth: 375, gutter: 16, desk: false, top: 10 }).scale).toBe(1);
  });
});

describe('mobile pins', () => {
  // A pin is 22px after the zoom, but never more than 33 pt (small phones).
  const d = PIN_PT;
  it('are 22px on an 812px-tall phone screen', () => {
    const pxPerPt = ((0.52 * 812) / FRAME.h) * ZOOM.mob;
    expect(PIN_PT * pxPerPt).toBeGreaterThanOrEqual(PIN_PX);
  });

  it('never overlap', () => {
    for (let i = 0; i < CALLOUTS.length; i += 1)
      for (let j = i + 1; j < CALLOUTS.length; j += 1) {
        const a = CALLOUTS[i]!.pin;
        const b = CALLOUTS[j]!.pin;
        expect(Math.hypot(a.x - b.x, a.y - b.y), `pins ${i + 1} and ${j + 1}`).toBeGreaterThanOrEqual(d * 0.98);
      }
  });

  it('stay on the screen, by the card', () => {
    for (const c of CALLOUTS) {
      expect(c.pin.x - d / 2).toBeGreaterThanOrEqual(0);
      expect(c.pin.x + d / 2).toBeLessThanOrEqual(393);
      expect(c.pin.y).toBeGreaterThan(CARD.y);
      expect(c.pin.y).toBeLessThan(CARD.y + CARD.h + d / 2);
    }
  });

  it('keep clear of the button labels (pin 4 and 6 hang under the button row)', () => {
    const labelBottom = ROWS.buttons + 9;
    for (const n of [4, 6]) expect(CALLOUTS[n - 1]!.pin.y - d / 2).toBeGreaterThanOrEqual(labelBottom);
  });
});

describe('the zoom', () => {
  const viewport = { width: 1440, height: 900, top: 59 };
  // The stage phone at 1440 × 900: min(78svh, 760px) tall, centred in columns 7–12.
  const h = 0.78 * 900;
  const w = (h * 420) / 879;
  const phone = { left: 1036 - w / 2, top: 59 + (900 - 59 - h) / 2, width: w, height: h };

  it('is 1.7 on a wide desktop and 1.4–1.8 on mobile', () => {
    expect(deskZoom(phone.width, viewport.width)).toBe(ZOOM.desk);
    expect(ZOOM.mob).toBe(1.4);
    expect(ZOOM.mobMax).toBe(1.8);
  });

  it('shrinks on narrow desktops so the callouts keep room', () => {
    const z = deskZoom(286, 1024);
    expect(z).toBeLessThan(ZOOM.desk);
    expect((1024 - 286 * z) / 2).toBeGreaterThanOrEqual(260 + 48 - 0.001);
    expect(deskZoom(261, 900)).toBe(ZOOM.min);
  });

  it('moves the card’s centre to the centre of the viewport under the header', () => {
    const L = deskLayout({ phone, viewport });
    expect(L.card.x + L.card.width / 2).toBeCloseTo(720, 3);
    expect(L.card.y + L.card.height / 2).toBeCloseTo(59 + (900 - 59) / 2, 3);
    expect(L.card.width).toBeCloseTo((361 / 420) * w * 1.7, 3);
  });

  it('keeps every label on screen and clear of the zoomed phone', () => {
    const L = deskLayout({ phone, viewport });
    for (const c of L.callouts) {
      if (c.side === 'left') {
        expect(c.label.x).toBeLessThanOrEqual(L.phone.x);
        expect(c.label.x - c.label.maxWidth).toBeGreaterThanOrEqual(24 - 0.001);
      } else {
        expect(c.label.x).toBeGreaterThanOrEqual(L.phone.x + L.phone.width);
        expect(c.label.x + c.label.maxWidth).toBeLessThanOrEqual(1440 - 24 + 0.001);
      }
      expect(c.label.y).toBeGreaterThan(59);
      expect(c.label.y).toBeLessThan(900);
    }
  });

  it('starts each leader line at its dot and ends it at its label (or the ghost)', () => {
    const L = deskLayout({ phone, viewport });
    for (const c of L.callouts) {
      expect(c.path.startsWith(`M${c.dot.x.toFixed(1)} ${c.dot.y.toFixed(1)}`)).toBe(true);
      const end = c.n === 6 ? L.ghost.x : c.label.x;
      expect(c.path.endsWith(`H${end.toFixed(1)}`)).toBe(true);
    }
  });

  it('sets the ghost level with the button row, right of the phone', () => {
    const L = deskLayout({ phone, viewport });
    const six = L.callouts.find((c) => c.n === 6)!;
    expect(L.ghost.y).toBeCloseTo(six.dot.y, 3);
    expect(L.ghost.x).toBeGreaterThan(L.phone.x + L.phone.width);
  });

  it('on mobile lifts the card to the upper part of the phone', () => {
    const z = mobZoom({ width: 202, height: 422 }, 375, 16);
    expect(z.x).toBe(0);
    expect(z.y).toBeLessThan(0);
    expect(ORIGIN.y * 422 + z.y).toBeCloseTo(0.35 * 422, 3);
  });

  it('on mobile makes the card as wide as the gutters allow, 1.4× to 1.8×', () => {
    expect(mobZoom({ width: 202, height: 422 }, 375, 16).scale).toBe(1.8);
    // A phone already wide for its screen keeps 1.4×.
    expect(mobZoom({ width: 300, height: 628 }, 375, 16).scale).toBe(ZOOM.mob);
    const mid = mobZoom({ width: 230, height: 481 }, 375, 16).scale;
    expect(mid).toBeGreaterThan(1.4);
    expect(mid).toBeLessThan(1.8);
    expect((CARD.w * 230 * mid) / 420).toBeLessThanOrEqual(375 - 32 + 0.01);
  });

  // The caption slot sits MOB_CAPTION down the phone: the zoomed card and pins 4 and 6 stay above it.
  for (const [vw, vh] of [
    [320, 640],
    [375, 667],
    [375, 812],
    [390, 844],
    [768, 1024],
  ] as const) {
    it(`on a ${vw} × ${vh} phone keeps the zoomed card, its pins and the caption apart`, () => {
      const h = Math.min(0.52 * vh, 460);
      const w = (h * 420) / 879;
      const z = mobZoom({ width: w, height: h }, vw, 16);
      const ppt = (w / 420) * z.scale;
      const centre = ORIGIN.y * h + z.y;
      const pinPx = Math.min(PIN_PX, PIN_PT * (w / 420) * z.scale);
      const pinsBottom = centre + (CALLOUTS[3]!.pin.y - CARD_CENTER.y) * ppt + pinPx / 2;
      expect(pinsBottom).toBeLessThanOrEqual(MOB_CAPTION * h - 1);
      expect(centre - (CARD.h / 2) * ppt).toBeGreaterThan(0);
      expect(CARD.w * ppt).toBeLessThanOrEqual(vw - 32 + 0.01);
      expect(MOB_CAPTION_ISLAND).toBeGreaterThan(MOB_CAPTION);
    });
  }
});

describe('separate (label stacking)', () => {
  const boxes = (ys: number[], hs: number[]) => ys.map((y, i) => ({ top: y - hs[i]! / 2, bottom: y + hs[i]! / 2 }));
  const apart = (ys: number[], hs: number[], gap: number) => {
    const b = boxes(ys, hs).sort((p, q) => p.top - q.top);
    return b.every((x, i) => i === 0 || x.top - b[i - 1]!.bottom >= gap - 0.01);
  };

  it('leaves boxes that already clear each other where they are', () => {
    expect(separate([{ y: 100, h: 40 }, { y: 200, h: 40 }], 0, 1000, 12)).toEqual([100, 200]);
  });

  it('pushes overlapping boxes apart around their middle', () => {
    const ys = separate([{ y: 100, h: 40 }, { y: 120, h: 40 }], 0, 1000, 12);
    expect(apart(ys, [40, 40], 12)).toBe(true);
    expect((ys[0]! + ys[1]!) / 2).toBeCloseTo(110, 1);
  });

  it('never moves a fixed box', () => {
    const ys = separate([{ y: 100, h: 40 }, { y: 120, h: 60, fixed: true }], 0, 1000, 12);
    expect(ys[1]).toBe(120);
    expect(apart(ys, [40, 60], 12)).toBe(true);
  });

  it('keeps boxes inside the bounds', () => {
    const ys = separate([{ y: 10, h: 40 }, { y: 20, h: 40 }, { y: 30, h: 40 }], 0, 1000, 12);
    expect(ys[0]! - 20).toBeGreaterThanOrEqual(-0.01);
    expect(apart(ys, [40, 40, 40], 12)).toBe(true);
  });
});

describe('desk layout with measured labels', () => {
  for (const [w, h] of [
    [1440, 900],
    [1280, 800],
    [1024, 768],
    [900, 700],
  ] as const) {
    it(`stacks the labels and the ghost without overlaps at ${w} × ${h}`, () => {
      const ph = Math.min(0.78 * h, 760);
      const pw = (ph * 420) / 879;
      const phone = { left: w * 0.72 - pw / 2, top: 59 + (h - 59 - ph) / 2, width: pw, height: ph };
      // Labels that wrap to two lines in narrow columns.
      const sizes = { 1: 64, 2: 64, 3: 64, 4: 64, 5: 64, 6: 90 };
      const L = deskLayout({ phone, viewport: { width: w, height: h, top: 59 }, sizes });
      for (const side of ['left', 'right'] as const) {
        const items = L.callouts
          .filter((c) => c.side === side)
          .map((c) =>
            c.label.valign === 'top'
              ? { top: L.ghost.y - 23, bottom: c.label.y + sizes[c.n] }
              : { top: c.label.y - sizes[c.n] / 2, bottom: c.label.y + sizes[c.n] / 2 },
          )
          .sort((a, b) => a.top - b.top);
        items.forEach((it, i) => {
          if (i > 0) expect(it.top - items[i - 1]!.bottom).toBeGreaterThanOrEqual(7.9);
          expect(it.top).toBeGreaterThanOrEqual(59);
        });
      }
    });
  }
});
