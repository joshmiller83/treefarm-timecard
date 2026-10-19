import { describe, expect, it } from 'vitest';
import { BEST_DAY, MARKS, MOMENTS, rowsAt, treesAt, weekHoursAt, WEEK } from '../../data/ledger.ts';
import { clockTab } from '../../components/screens/clock/clock.ts';
import {
  AT,
  BEATS,
  beatsFor,
  bulletText,
  COPY,
  LAPSE,
  PACE_AT,
  PACE_FROM,
  ROLL_CELLS,
  ROLL_REST,
  bottomCropLabel,
  lapseEvents,
  leadRows,
  litAt,
  numParts,
  phoneLabel,
  rollHTML,
  rollStops,
  scrollStops,
  spokenMinSec,
  tilesAt,
  weekSentence,
} from './pace.ts';

describe('pace: the stat tiles', () => {
  it('match the ledger and the brief at 3:40 PM', () => {
    const tiles = tilesAt();
    expect(tiles.map((t) => t.text)).toEqual(['34', '1:46', '179']);
    expect(tiles.map((t) => t.unit)).toEqual(['trees an hour', 'a tree', 'hours of work left in this field at your pace']);
  });

  it('say the same as the phone’s pace card', () => {
    const p = clockTab(PACE_AT).pace;
    const [hour, each, left] = tilesAt();
    expect(hour!.text).toBe(p.treesHour.value);
    expect(each!.text).toBe(p.perTree.value);
    expect(p.left).toContain(` ${left!.text} hours left`);
  });

  it('pair each tile with a pace row on the phone', () => {
    expect(tilesAt().map((t) => t.row)).toEqual(['trees-hour', 'per-tree', 'left']);
  });

  it('have spoken forms for screen readers that match the numbers', () => {
    expect(tilesAt().map((t) => t.spoken)).toEqual(['34 trees an hour', '1 minute 46 seconds a tree', '179 hours of work left in this field at your pace']);
  });
});

describe('pace: the rolling digits', () => {
  /** The cell a column shows at a translateY of `stop` percent. */
  const cellAt = (stop: number) => ROLL_CELLS[Math.round((-stop / 100) * ROLL_CELLS.length)];

  it('rest unlit on a blank cell, so an unlit tile never shows a number', () => {
    expect(ROLL_CELLS).toHaveLength(21);
    expect(cellAt(ROLL_REST)).toBe('');
  });

  it('stop every column on its own digit in the second cycle (no rounding, no drift)', () => {
    for (const text of ['34', '1:46', '179']) {
      const stops = rollStops(text);
      expect(stops.map(cellAt).join('')).toBe(text.replace(':', ''));
      // Second cycle: at least eleven steps from the blank rest, whatever the digit.
      for (const s of stops) expect((-s / 100) * ROLL_CELLS.length).toBeGreaterThanOrEqual(11);
    }
    expect(rollStops('34')).toEqual([-(14 * 100) / 21, -(15 * 100) / 21]);
  });

  it('renders one 21-cell column per digit, at rest on the final reading, with static separators', () => {
    const html = rollHTML('1:46');
    expect(html.match(/class="roll-col"/g)).toHaveLength(3);
    expect(html.match(/<span>\d<\/span>/g)).toHaveLength(60);
    expect(html.match(/<span><\/span>/g)).toHaveLength(3);
    expect(html).toContain('<span class="roll-s">:</span>');
    for (const stop of rollStops('1:46')) expect(html).toContain(`translateY(${stop}%)`);
    // The digit at each stop reads back the text.
    const cols = [...html.matchAll(/data-digit="(\d)"/g)].map((m) => m[1]).join('');
    expect(cols).toBe('146');
  });

  it('splits a reading into digits and separators for the static number', () => {
    expect(numParts('1:46')).toEqual([{ t: '1' }, { t: ':', sep: true }, { t: '46' }]);
    expect(numParts('179')).toEqual([{ t: '179' }]);
  });
});

describe('pace: the 3:00 → 3:40 time-lapse', () => {
  it('starts where the crew chapter ends and lands on the pace moment', () => {
    expect(PACE_FROM).toBe(MOMENTS.synced);
    expect(PACE_AT).toBe(MOMENTS.pace);
  });

  it('steps once per row Alex marks, at the ledger’s minute, with trees that reconcile', () => {
    const ev = lapseEvents();
    const marks = MARKS.filter((m) => m.at > PACE_FROM && m.at <= PACE_AT && !m.rejected);
    expect(ev).toHaveLength(marks.length);
    expect(ev.map((e) => e.row)).toEqual(marks.map((m) => m.row));
    expect(ev[0]!.before).toBe(treesAt(PACE_FROM));
    expect(ev.at(-1)!.after).toBe(treesAt(PACE_AT));
    for (const e of ev) {
      expect(e.after - e.before).toBe(10);
      expect(e.p).toBeGreaterThan(LAPSE[0]);
      expect(e.p).toBeLessThan(LAPSE[1]);
    }
    // Linear in the minute: 3:15 sits 15/40 of the way through the window.
    expect(ev[0]!.p).toBeCloseTo(LAPSE[0] + ((MARKS.find((m) => m.row === 37)!.at - PACE_FROM) / (PACE_AT - PACE_FROM)) * (LAPSE[1] - LAPSE[0]), 6);
  });

  it('needs the rows the strip starts on before the final card’s first row', () => {
    expect(leadRows()).toEqual([37, 38]);
    expect(rowsAt(PACE_FROM)[0]).toBe(37);
    expect(rowsAt(PACE_AT)).toEqual([39, 40, 41]);
    expect(leadRows()).toHaveLength(lapseEvents().length);
  });
});

describe('pace: the scroll beats', () => {
  it('stay inside 0–1 and in the brief’s windows', () => {
    const flat = Object.values(BEATS).flat() as number[];
    for (const v of flat) {
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
    }
    expect(BEATS.lapse).toEqual([0, 0.1]);
    expect(BEATS.unlock).toEqual([0.1, 0.18]);
    expect(BEATS.toPace[0]).toBeGreaterThanOrEqual(0.18);
    expect(BEATS.tiles[0]).toBeGreaterThanOrEqual(0.28);
    expect(BEATS.tiles[0]).toBeLessThanOrEqual(0.33);
    expect(BEATS.toHours[1]).toBeLessThanOrEqual(0.75);
    expect(BEATS.tap).toBeGreaterThanOrEqual(0.75);
    expect(BEATS.tap + BEATS.tapDur).toBeLessThan(0.88);
    // The pay answers inside the tap, and the small print starts with it.
    expect(BEATS.nope).toBeGreaterThan(BEATS.tap);
    expect(BEATS.nope).toBeLessThan(BEATS.tap + BEATS.tapDur);
    expect(Math.abs(BEATS.small[0] - BEATS.tap)).toBeLessThanOrEqual(0.01);
    expect(BEATS.small[1]).toBeLessThan(BEATS.back[0]);
    expect(BEATS.back[0]).toBeGreaterThanOrEqual(0.88);
    expect(BEATS.relock[1]).toBeLessThanOrEqual(1);
  });

  it('reveal one tile per .1 or less, in order, after the phone reaches the pace card', () => {
    const t = BEATS.tiles;
    expect(t).toHaveLength(3);
    expect(t[0]).toBeGreaterThanOrEqual(BEATS.toPace[1]);
    for (let i = 1; i < t.length; i += 1) {
      expect(t[i]! - t[i - 1]!).toBeGreaterThan(0.04);
      expect(t[i]! - t[i - 1]!).toBeLessThanOrEqual(0.1);
    }
    expect(t.at(-1)!).toBeLessThan(BEATS.toHours[0]);
  });

  it('grow the bars as the hours card arrives, before the tap', () => {
    expect(BEATS.bars).toBeGreaterThan(BEATS.toHours[0]);
    expect(BEATS.bars).toBeLessThanOrEqual(BEATS.toHours[1] + 0.02);
    expect(BEATS.bars).toBeLessThan(BEATS.tap);
  });
});

describe('pace: mobile beats', () => {
  it('only move the moments a card would cover, and keep the same order', () => {
    const m = beatsFor(false);
    const d = beatsFor(true);
    expect(d).toEqual({ ...BEATS });
    expect(m.lapse).toEqual(d.lapse);
    expect(m.unlock).toEqual(d.unlock);
    expect(m.tap).toBe(d.tap);
    expect(m.tiles[0]).toBeGreaterThanOrEqual(m.toPace[1]);
    expect(m.tiles.at(-1)!).toBeLessThan(m.toHours[0]);
    expect(m.bars).toBeGreaterThan(m.toHours[0]);
    expect(m.bars).toBeLessThan(m.tap);
  });

  it('light each tile while its card sits low in a 375 × 812 viewport (track 260vh)', () => {
    // SectionShell: a beat's centre sits at 74svh when progress equals its --at.
    const vh = 812;
    const scroll = 2.6 * vh - vh;
    const half = 85; // the two-row tiles card is about 170px tall
    for (const p of beatsFor(false).tiles) {
      const centre = 0.74 * vh + (AT.statsMob - p) * scroll;
      expect(centre + half).toBeLessThanOrEqual(vh);
      expect(centre - half).toBeGreaterThan(0.5 * vh);
    }
  });
});

describe('pace: the in-phone scroll', () => {
  const geo = { layerH: 1865, screenH: 852, paceTop: 783, pt: 1 };

  it('parks the pace card under the toolbar, then scrolls to the end', () => {
    const s = scrollStops(geo);
    expect(s.pace).toBeCloseTo(783 - 110, 6);
    expect(s.end).toBe(1865 - 852);
  });

  it('works in percent of the layer, so any phone size gets the same crop', () => {
    const a = scrollStops(geo);
    const b = scrollStops({ layerH: 1865 * 0.5, screenH: 852 * 0.5, paceTop: 783 * 0.5, pt: 0.5 });
    expect(b.pacePct).toBeCloseTo(a.pacePct, 6);
    expect(b.endPct).toBeCloseTo(a.endPct, 6);
    expect(a.endPct).toBeCloseTo(-((1865 - 852) / 1865) * 100, 6);
  });

  it('never scrolls past either end', () => {
    const s = scrollStops({ layerH: 900, screenH: 852, paceTop: 783, pt: 1 });
    expect(s.pace).toBe(48);
    expect(s.end).toBe(48);
    const none = scrollStops({ layerH: 800, screenH: 852, paceTop: 100, pt: 1 });
    expect(none.pace).toBe(0);
    expect(none.end).toBe(0);
  });
});

describe('pace: the triggered pieces are level-triggered', () => {
  it('know what is lit at any progress, with no history (reload, restore, rebuild)', () => {
    const marks = [0.3, 0.4, 0.5];
    expect(litAt(0, marks)).toEqual([false, false, false]);
    expect(litAt(0.35, marks)).toEqual([true, false, false]);
    expect(litAt(0.4, marks)).toEqual([true, true, false]);
    expect(litAt(0.72, marks)).toEqual([true, true, true]);
    expect(litAt(1, marks)).toEqual([true, true, true]);
  });

  it('light every tile and grow the bars by the mid-section restore points on both breakpoints', () => {
    for (const desk of [true, false]) {
      const b = beatsFor(desk);
      expect(litAt(0.5, [...b.tiles])).toEqual([true, true, true]);
      expect(litAt(0.72, [...b.tiles, b.bars])).toEqual([true, true, true, true]);
    }
  });
});

describe('pace: words', () => {
  it('reads seconds the way a person says them', () => {
    expect(spokenMinSec(106)).toBe('1 minute 46 seconds');
    expect(spokenMinSec(60)).toBe('1 minute');
    expect(spokenMinSec(45)).toBe('45 seconds');
    expect(spokenMinSec(121)).toBe('2 minutes 1 second');
  });

  it('puts the week chart’s values in words (the chart itself is decorative)', () => {
    const s = weekSentence();
    for (const [i] of weekHoursAt(PACE_AT).entries()) expect(s).toContain(`${WEEK[i]!.long} `);
    // Durations, never clock-style strings a screen reader would announce as times of day.
    expect(s).not.toMatch(/\d:\d/);
    expect(s).toBe(
      'Monday 8 hours 37 minutes, Tuesday 8 hours 18 minutes, Wednesday 5 hours 45 minutes, Thursday 8 hours 45 minutes and Friday 7 hours 39 minutes so far',
    );
  });

  it('labels the phone with the brief’s sentence plus the week’s values', () => {
    expect(phoneLabel()).toBe(
      'Time Card Clock tab at 3:40 PM: on the clock 7 hours 39 minutes, 260 trees this shift, 34 trees an hour, ' +
        '1 minute 46 seconds a tree, best day Thursday with 318 trees, about 179 hours left in North field, ' +
        'and a week chart of hours worked, Monday 8 hours 37 minutes, Tuesday 8 hours 18 minutes, Wednesday 5 hours 45 minutes, ' +
        'Thursday 8 hours 45 minutes and Friday 7 hours 39 minutes so far, with pay hidden.',
    );
  });

  it('labels the bottom crop with what it shows: the pace card and Hours & pay', () => {
    expect(bottomCropLabel()).toBe(
      'The same Clock tab scrolled down: the pace card with 34 trees an hour, 1 minute 46 seconds a tree and pay per tree hidden, ' +
        'best day Thursday with 318 trees, about 179 hours left in North field, and Hours & pay with a bar for each day, ' +
        'Friday in gold, and pay hidden behind dots.',
    );
    expect(bottomCropLabel()).not.toMatch(/notes/i);
  });

  it('keeps the copy honest: no currency, best day from the ledger', () => {
    const all = JSON.stringify(COPY) + phoneLabel() + bottomCropLabel();
    expect(all).not.toMatch(/\$|USD|dollar/i);
    const plain = COPY.bullets.map(bulletText).map((t) => t.replace(/\u00a0/g, ' '));
    expect(plain[1]).toBe(`Your best day: ${BEST_DAY.long}, ${BEST_DAY.trees} trees.`);
    expect(plain).toEqual([
      'Trees an hour, time per tree and pay per tree, for today, this week and the season.',
      'Your best day: Thursday, 318 trees.',
      'This week’s hours and pay sit in a bar chart. Hide your pay with one tap.',
    ]);
    expect(COPY.small).toBe('Pay is hidden in every screen on this page, the way you can hide it in the app.');
  });
});
