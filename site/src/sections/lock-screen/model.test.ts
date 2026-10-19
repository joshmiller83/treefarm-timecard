import { describe, expect, it } from 'vitest';
import { liveActivityAt, MOMENTS, rowsAt, treesAt } from '../../data/ledger.ts';
import { cardHeight, LA } from '../../components/system/lockscreen/activity.ts';
import {
  BEFORE,
  CALLOUTS,
  CARD,
  CARD_CENTER,
  deskLayout,
  deskZoom,
  FRAME,
  ISLAND_AT,
  mobZoom,
  ORIGIN,
  phoneLabel,
  PIN_PT,
  PIN_PX,
  ROWS,
  separate,
  slots,
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

  it('draw in .05 slots over [.2, .5]', () => {
    const s = slots(0.2, 0.5, 6);
    expect(s[0]).toEqual([0.2, 0.25]);
    expect(s[5]![1]).toBeCloseTo(0.5, 9);
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

  it('is 1.7 on a wide desktop and 1.4 on mobile', () => {
    expect(deskZoom(phone.width, viewport.width)).toBe(ZOOM.desk);
    expect(ZOOM.mob).toBe(1.4);
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

  it('on mobile lifts the card to the upper part of the phone, above the caption cards', () => {
    const z = mobZoom(422);
    expect(z.scale).toBe(1.4);
    expect(z.x).toBe(0);
    expect(z.y).toBeLessThan(0);
    // The card's centre lands in the upper part of the phone.
    expect(ORIGIN.y * 422 + z.y).toBeCloseTo(0.38 * 422, 3);
  });
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
