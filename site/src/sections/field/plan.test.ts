import { describe, expect, it } from 'vitest';
import { EARLIER_COUNT, FIELD_TREES, MOMENTS, fieldShapedAt, treesAt } from '../../data/ledger.ts';
import { BEATS, DOT_R, TODAY_SCALE, ZOOM_TARGET, blockRect, countStatus, dotCenter, targetRect, treeStatus } from '../../scripts/fieldstate.ts';
import {
  CARDS,
  CLEAR,
  COUNTS,
  HEAD_FADE,
  SETTLE,
  SHEET,
  WIN,
  cardAt,
  countsAt,
  headCut,
  phoneCloseUp,
  riseAt,
  seasonAt,
  sheetTopAt,
  stripText,
  zoomEdgeFade,
} from './plan.ts';

const at = (p: number) => countsAt(p);

describe('the field section: numbers come from the ledger', () => {
  it('the final counter strip is the brief’s: 8,540 trees · 2,420 shaped · 230 today', () => {
    expect(COUNTS).toEqual({
      trees: FIELD_TREES,
      earlier: EARLIER_COUNT,
      today: treesAt(MOMENTS.field),
      shaped: fieldShapedAt(MOMENTS.field),
    });
    expect(stripText(COUNTS)).toBe('8,540 trees · 2,420 shaped · 230 today');
  });

  it('agrees with the map: 2,190 green plus 230 gold at 2:16 PM', () => {
    const c = countStatus(treeStatus({ at: MOMENTS.field }));
    expect(c.earlier).toBe(COUNTS.earlier);
    expect(c.today).toBe(COUNTS.today);
    expect(c.earlier + c.today).toBe(COUNTS.shaped);
  });
});

describe('the counters at section progress p', () => {
  it('start at zero while the field is still tilted', () => {
    expect(at(0)).toEqual({ trees: 0, shaped: 0, today: 0 });
    expect(at(WIN.count[0])).toEqual({ trees: 0, shaped: 0, today: 0 });
  });

  it('roll to 8,540 trees and 2,190 shaped as the field flattens', () => {
    expect(at(WIN.count[1])).toEqual({ trees: FIELD_TREES, shaped: EARLIER_COUNT, today: 0 });
    const mid = at((WIN.count[0] + WIN.count[1]) / 2);
    expect(mid.trees).toBeGreaterThan(0);
    expect(mid.trees).toBeLessThan(FIELD_TREES);
    expect(mid.today).toBe(0);
  });

  it('count today’s rows ten trees at a time while they flip to gold', () => {
    let last = -1;
    for (let p = BEATS.reveal[0]; p <= BEATS.reveal[1] + 1e-9; p += 0.0025) {
      const c = at(p);
      expect(c.today % 10).toBe(0);
      expect(c.today).toBeGreaterThanOrEqual(last);
      expect(c.shaped).toBe(EARLIER_COUNT + c.today);
      last = c.today;
    }
    expect(at(BEATS.reveal[1])).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: COUNTS.today });
  });

  it('reach the ledger at the end of the reveal and hold through the zoom', () => {
    for (const p of [0.53, 0.56, 0.6, 0.705, 0.72]) expect(at(p)).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: COUNTS.today });
  });

  it('count row 37 while the demo has it gold, and give it back on Undo', () => {
    const mid = (BEATS.demoIn[1] + BEATS.demoOut[0]) / 2;
    expect(at(mid)).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped + 10, today: COUNTS.today + 10 });
    expect(at(BEATS.demoOut[1])).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: COUNTS.today });
  });

  it('go back to zero shaped next season (the trees stay), then return', () => {
    expect(at(0.85)).toEqual({ trees: FIELD_TREES, shaped: 0, today: 0 });
    const half = at((BEATS.seasonOut[0] + BEATS.seasonOut[1]) / 2);
    expect(half.shaped).toBeGreaterThan(0);
    expect(half.shaped).toBeLessThan(COUNTS.shaped);
    expect(at(BEATS.seasonIn[1])).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: COUNTS.today });
  });

  it('end on the ledger values, and never go out of range', () => {
    expect(at(1)).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: COUNTS.today });
    expect(at(-1)).toEqual(at(0));
    expect(at(2)).toEqual(at(1));
    for (let p = 0; p <= 1; p += 0.01) {
      const c = at(p);
      expect(Number.isInteger(c.trees) && Number.isInteger(c.shaped) && Number.isInteger(c.today)).toBe(true);
      expect(c.today).toBeLessThanOrEqual(c.shaped);
    }
  });
});

describe('the season chip', () => {
  it('reads This season, rolls to Next season with the flip, then rolls back', () => {
    expect(seasonAt(0.5)).toBe(0);
    expect(seasonAt(BEATS.seasonOut[1])).toBe(1);
    expect(seasonAt(0.86)).toBe(1);
    expect(seasonAt(BEATS.seasonIn[1])).toBe(0);
    expect(seasonAt(1)).toBe(0);
  });
});

describe('the three cards', () => {
  it('appear one at a time, in order, each inside its beat', () => {
    expect(CARDS).toHaveLength(3);
    for (let i = 0; i < CARDS.length; i += 1) {
      const c = CARDS[i]!;
      expect(c.in[0]).toBeLessThan(c.in[1]);
      expect(c.in[1]).toBeLessThan(c.out[0]);
      expect(c.out[0]).toBeLessThan(c.out[1]);
      if (i > 0) expect(c.in[0]).toBeGreaterThanOrEqual(CARDS[i - 1]!.out[1]);
    }
    // 1: while today's rows flip to gold. 2: the zoom and the row 37 demo. 3: the season flip.
    expect(CARDS[0]!.in[0]).toBeGreaterThanOrEqual(BEATS.reveal[0]);
    expect(CARDS[0]!.out[1]).toBeLessThanOrEqual(BEATS.zoomIn[0] + 0.03);
    expect(CARDS[1]!.in[1]).toBeLessThanOrEqual(BEATS.touch[0]);
    expect(CARDS[1]!.out[0]).toBeGreaterThanOrEqual(BEATS.demoOut[1]);
    expect(CARDS[2]!.in[1]).toBeLessThanOrEqual(BEATS.seasonOut[1]);
    expect(CARDS[2]!.out[0]).toBeGreaterThanOrEqual(BEATS.pulse[1]);
  });

  it('cardAt says which card shows (0 = none)', () => {
    expect(cardAt(0.1)).toBe(0);
    expect(cardAt(0.42)).toBe(1);
    expect(cardAt(0.65)).toBe(2);
    expect(cardAt(0.84)).toBe(3);
    expect(cardAt(0.99)).toBe(0);
  });
});

describe('the hand-offs', () => {
  it('the stage phone leaves before the field flattens and is back at rest by 1', () => {
    expect(WIN.phoneOut[0]).toBe(0);
    expect(WIN.phoneOut[1]).toBeLessThanOrEqual(WIN.flatten[0]);
    expect(WIN.phoneIn[1]).toBe(1);
    expect(WIN.phoneIn[0]).toBeGreaterThanOrEqual(BEATS.zoomOut[0]);
  });

  it('the map fades only as the camera settles on the overview, and mostly before the phone is back', () => {
    expect(WIN.mapOut[0]).toBeGreaterThan(BEATS.zoomOut[0] + 0.5 * (BEATS.zoomOut[1] - BEATS.zoomOut[0]));
    expect(WIN.mapOut[1]).toBeLessThanOrEqual(1);
    expect(WIN.phoneIn[0]).toBeGreaterThan(WIN.mapOut[0] + 0.3 * (WIN.mapOut[1] - WIN.mapOut[0]));
  });

  it('desktop: the field fades in under the leaving phone and is whole before it flattens far', () => {
    expect(WIN.camIn[0]).toBeGreaterThan(WIN.phoneOut[0]);
    expect(WIN.camIn[0]).toBeLessThan(WIN.phoneOut[1]);
    expect(WIN.camIn[1]).toBeLessThanOrEqual(WIN.flatten[0] + 0.25 * (WIN.flatten[1] - WIN.flatten[0]));
  });

  it('the close-up’s soft edges cover the whole camera move, in and out', () => {
    expect(WIN.edgesIn[0]).toBeLessThanOrEqual(BEATS.zoomIn[0]);
    expect(WIN.edgesIn[1]).toBeLessThanOrEqual(BEATS.zoomIn[0] + 0.03);
    expect(WIN.edgesOut[0]).toBeGreaterThanOrEqual(WIN.mapOut[0]);
    expect(WIN.edgesOut[1]).toBeGreaterThanOrEqual(BEATS.zoomOut[1]);
  });

  it('phones: the sheet’s scrim is up for exactly the three cards', () => {
    expect(SHEET.in).toEqual(CARDS[0]!.in);
    expect(SHEET.out).toEqual(CARDS[2]!.out);
    expect(SETTLE[0]).toBeGreaterThanOrEqual(CARDS[1]!.out[0]);
    expect(SETTLE[1]).toBeLessThanOrEqual(CARDS[2]!.in[1]);
  });
});

describe('the heading fades by position, not by progress', () => {
  it('desktop: what is left of it is gone before the field is nearly flat under it', () => {
    expect(WIN.headOut[0]).toBeGreaterThanOrEqual(WIN.flatten[0]);
    expect(WIN.headOut[1]).toBeLessThanOrEqual(WIN.flatten[0] + 0.65 * (WIN.flatten[1] - WIN.flatten[0]));
  });

  it('is whole until it nears the line, then fades over 48px, and is gone above it', () => {
    const line = 105;
    expect(headCut(line, 400)).toBe(0);
    expect(headCut(line, line + HEAD_FADE)).toBe(0);
    // Its top is at the line: the first 48px are fading, everything below is whole.
    expect(headCut(line, line)).toBe(HEAD_FADE);
    // 100px of it above the line: gone down to the line, fading to 48px below.
    expect(headCut(line, line - 100)).toBe(100 + HEAD_FADE);
  });
});

describe('the phone close-up clears the card sheet', () => {
  // 375×667: the strip ends at 44, rows 28–40 span 155–460 before rising, card 2 tops at 394, card 3 at 432.
  const short = { targetTop: 155, targetBottom: 460, stripBottom: 44, cardTops: [394, 432] as const, chipH: 30 };

  it('centres the rows between the strip and each card, clear of both, with the chip above row 28', () => {
    const { dz, chipTop } = phoneCloseUp(short);
    const mid = (short.targetTop + short.targetBottom) / 2;
    expect(dz[0]).toBe(mid - (44 + 394) / 2);
    expect(dz[1]).toBe(mid - (44 + 432) / 2);
    for (const [i, card] of [394, 432].entries()) {
      expect(short.targetBottom - dz[i]! + CLEAR).toBeLessThanOrEqual(card);
      expect(short.targetTop - dz[i]!).toBeGreaterThanOrEqual(short.stripBottom + CLEAR);
    }
    expect(chipTop).toBeGreaterThanOrEqual(short.stripBottom);
    expect(chipTop + short.chipH).toBeLessThanOrEqual(short.targetTop - dz[1] - 6);
  });

  it('clears a card first when centring is not enough', () => {
    // A tall card: centred, the rows would still touch it.
    const { dz } = phoneCloseUp({ ...short, cardTops: [330, 432] });
    expect(dz[0]).toBe(Math.min(155 - 44 - CLEAR, 460 + CLEAR - 330));
  });

  it('does not move when the rows already sit centred, and never slides them under the strip', () => {
    const centred = phoneCloseUp({ ...short, cardTops: [600, 600] });
    expect(centred.dz).toEqual([0, 0]);
    const tiny = phoneCloseUp({ ...short, cardTops: [200, 220] });
    expect(short.targetTop - tiny.dz[0]).toBe(short.stripBottom + CLEAR);
    expect(tiny.chipTop).toBe(short.stripBottom + 4);
  });

  it('rides the camera, and eases from card 2’s rise to card 3’s while the cards swap', () => {
    const dz = [80, 40] as const;
    expect(riseAt(0.3, 0, dz)).toBe(0);
    expect(riseAt(0.62, 1, dz)).toBe(80);
    expect(riseAt(0.62, 0.5, dz)).toBe(40);
    expect(riseAt(SETTLE[1], 1, dz)).toBe(40);
    const mid = riseAt((SETTLE[0] + SETTLE[1]) / 2, 1, dz);
    expect(mid).toBeGreaterThan(40);
    expect(mid).toBeLessThan(80);
    expect(riseAt(1, 0, dz)).toBe(0);
  });
});

describe('the phone card sheet’s scrim', () => {
  const tops = [541, 493, 541] as const;
  it('sits at the top of the card that shows, and moves only while the cards swap', () => {
    expect(sheetTopAt(0.2, tops)).toBe(541);
    expect(sheetTopAt(0.45, tops)).toBe(541);
    expect(sheetTopAt(0.6, tops)).toBe(493);
    expect(sheetTopAt(0.69, tops)).toBe(493);
    expect(sheetTopAt(0.8, tops)).toBe(541);
    expect(sheetTopAt(1, tops)).toBe(541);
    const swap = sheetTopAt((CARDS[0]!.out[0] + CARDS[1]!.in[1]) / 2, tops);
    expect(swap).toBeGreaterThan(493);
    expect(swap).toBeLessThan(541);
  });
});

describe('the static close-up’s soft edges', () => {
  const f = zoomEdgeFade();
  const r = targetRect(ZOOM_TARGET);
  const gold = DOT_R * TODAY_SCALE;

  it('fade only the dimmed context: every dot of rows 28–40 and the row numbers stay whole', () => {
    const top = dotCenter(2, ZOOM_TARGET.from, 1).y - gold - r.y;
    const bottom = r.y + r.h - (dotCenter(2, ZOOM_TARGET.to, 10).y + gold);
    const right = r.x + r.w - (dotCenter(2, 37, 10).x + gold);
    expect(f.top.solid).toBeLessThan(top);
    expect(f.bottom.solid).toBeLessThan(bottom);
    expect(f.right.solid).toBeLessThan(right);
    // Tree 10's whole gold dot is inside the opaque band (the old 86% stop cut it in half).
    expect(dotCenter(2, 37, 10).x + gold - r.x).toBeLessThan(r.w - f.right.solid);
    expect(f.left.solid).toBeLessThan(blockRect(2).x - 0.7 - 1.2 * 0.54 - r.x);
    for (const s of [f.left, f.right, f.top, f.bottom]) expect(s.clear).toBeLessThan(s.solid);
  });

  it('fade most of block 1’s last column and rows 27 and 41', () => {
    const col = dotCenter(1, 30, 10).x - r.x;
    expect(col).toBeGreaterThan(f.left.clear);
    expect(col).toBeLessThan(f.left.solid);
    expect(dotCenter(2, 27, 1).y - r.y).toBeLessThan(f.top.solid);
    expect(r.y + r.h - dotCenter(2, 41, 1).y).toBeLessThan(f.bottom.solid);
  });
});
