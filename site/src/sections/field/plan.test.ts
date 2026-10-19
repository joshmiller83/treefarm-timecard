import { describe, expect, it } from 'vitest';
import { EARLIER_COUNT, FIELD_TREES, MOMENTS, fieldShapedAt, treesAt } from '../../data/ledger.ts';
import { BEATS, countStatus, treeStatus } from '../../scripts/fieldstate.ts';
import { CARDS, COUNTS, WIN, cardAt, countsAt, seasonAt, stripText } from './plan.ts';

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

  it('agrees with the map: 2,190 green plus 230 gold at 2:15 PM', () => {
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

  it('reach the ledger at the end of the reveal and hold through the zoom and the demo', () => {
    for (const p of [0.53, 0.6, 0.65, 0.7, 0.72]) expect(at(p)).toEqual({ trees: FIELD_TREES, shaped: COUNTS.shaped, today: COUNTS.today });
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

  it('the heading is gone before the counter strip fades in under it', () => {
    expect(WIN.headOut[1]).toBeLessThanOrEqual(WIN.chrome[0] + 0.05);
    expect(WIN.headOut[0]).toBeGreaterThanOrEqual(WIN.phoneOut[0]);
  });
});
