import { describe, expect, it } from 'vitest';
import { FLAGS, MOMENTS, breakAt, liveActivityAt, workedAt, fmtHMS } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { waveHeights } from '../../scripts/wave.ts';
import {
  ALTS,
  BREAK_ON_CARD,
  BREAK_PILL,
  FLAG_LIST,
  PHONE_LABEL,
  STAMPS,
  WORKED_ON_BREAK,
  answerChips,
} from './copy.ts';
import { AT, BEAT_KEYS, plan, type Mode, type Span } from './plan.ts';

describe('notes copy comes from the ledger and siri.ts', () => {
  it('names the flags exactly as the app does', () => {
    expect(FLAGS).toEqual(['Needs attention', 'Dead', 'Replant']);
    expect(FLAG_LIST).toBe('Needs attention, Dead or Replant');
  });

  it('builds the four answer chips from the tree note', () => {
    expect(answerChips().map((c) => c.text)).toEqual(['Row 36', 'Tree 7', 'Leader’s broken. Needs a stake.', 'Needs attention']);
    expect(answerChips().map((c) => c.kind)).toEqual(['row', 'tree', 'quote', 'flag']);
  });

  it('shows the break pill and the frozen worked time', () => {
    expect(BREAK_PILL).toBe('On break · Sharpening shears');
    expect(WORKED_ON_BREAK).toBe('6:43:00');
    // Worked time holds through the whole break.
    for (const m of [MOMENTS.break, MOMENTS.treeNote, MOMENTS.shiftNote, MOMENTS.backFromBreak]) {
      expect(fmtHMS(workedAt(m))).toBe('6:43:00');
    }
    expect(BREAK_ON_CARD).toBe('Sharpening shears 2:30–2:44');
  });

  it('ends back on the clock with rows 37, 38, 39 and 230 trees', () => {
    const la = liveActivityAt(MOMENTS.backFromBreak);
    expect(la.state).toBe('working');
    expect(la.worked).toBe('6:43:00');
    expect(la.trees).toBe(230);
    expect(la.rows).toEqual([37, 38, 39]);
  });

  it('uses the app’s Siri wording (decisions.md #1 and #3)', () => {
    expect(SIRI.breakReason.said).toBe('Take a break with Time Card.');
    expect(SIRI.breakReason.reply).toBe('Break for sharpening shears started at 2:30.');
    expect(SIRI.treeNote.said).toBe('Note a tree in Time Card.');
    expect(SIRI.treeNote.reply).toBe('Noted on block 2, row 36, tree 7.');
    expect(SIRI.shiftNote.said).toBe('Add a note in Time Card.');
    expect(SIRI.shiftNote.answer).toBe('Rows past 30 are tall. Slower going.');
    expect(SIRI.shiftNote.reply).toBe('Added to today’s notes.');
  });

  it('labels the phone exactly as the brief does', () => {
    expect(PHONE_LABEL).toBe(
      'Time Card tree note for block 2, row 36, tree 7: Needs attention. Leader’s broken. Needs a stake. Alex, today 2:33 PM. The map shows a flag on that tree.',
    );
    expect(ALTS.back).toContain('rows 37, 38, 39 and Break');
  });

  it('stamps each beat with its ledger time', () => {
    expect(STAMPS).toEqual({
      break: '2:30 PM · Break by voice',
      tree: '2:33 PM · Tree note',
      crew: '2:33 PM · On the map',
      shift: '2:36 PM · Shift note',
      back: '2:44 PM · Back to work',
    });
  });

  it('draws the same dictation wave for the same progress (scrubbing is deterministic)', () => {
    for (const p of [0.12, 0.5, 0.83]) expect(waveHeights(p, 7, 24)).toEqual(waveHeights(p, 7, 24));
  });
});

const inside = (v: number) => v >= 0 && v <= 1;
const ordered = (s: Span) => s[0] <= s[1];

describe.each<Mode>(['desk', 'mob'])('the %s plan', (mode) => {
  const P = plan(mode);
  const all: number[] = [];
  const walk = (o: unknown) => {
    if (typeof o === 'number') all.push(o);
    else if (Array.isArray(o)) o.forEach(walk);
    else if (o && typeof o === 'object') Object.values(o).forEach(walk);
  };
  walk({ ...P, mode: undefined, day: P.day.map((d) => [d.start, d.end]) });

  it('keeps every position inside the track', () => {
    for (const v of all) expect(inside(v), String(v)).toBe(true);
  });

  it('places the beats in story order', () => {
    const ats = BEAT_KEYS.map((b) => AT[mode][b]);
    expect([...ats].sort((a, b) => a - b)).toEqual(ats);
  });

  it('runs the day 2:16 → 2:30 → 2:33 → 2:36 → 2:44 without overlaps', () => {
    expect(P.day.map((d) => d.min)).toEqual([
      MOMENTS.break - 0.5 / 60,
      MOMENTS.break,
      MOMENTS.treeNote,
      MOMENTS.shiftNote,
      MOMENTS.backFromBreak - 0.5 / 60,
      MOMENTS.backFromBreak,
    ]);
    for (let i = 0; i < P.day.length; i += 1) {
      const d = P.day[i]!;
      expect(d.start).toBeLessThan(d.end);
      if (i > 0) expect(d.start).toBeGreaterThanOrEqual(P.day[i - 1]!.end);
    }
  });

  it('starts the break when Siri says it started, and ends it on the Back to work tap', () => {
    const reach = (min: number) => P.day.find((d) => d.min === min)!.end;
    expect(reach(MOMENTS.break)).toBe(P.break.start);
    expect(P.break.start).toBeGreaterThanOrEqual(P.break.reply[0]);
    expect(P.break.la[0]).toBe(P.break.start);
    expect(reach(MOMENTS.backFromBreak)).toBe(P.back.end);
    expect(P.back.tap).toBeLessThan(P.back.end);
    expect(P.back.la[0]).toBe(P.back.end);
    // Just before each boundary the ledger still reads the old state.
    expect(breakAt(MOMENTS.break - 0.5 / 60)).toBeNull();
    expect(breakAt(MOMENTS.backFromBreak - 0.5 / 60)?.reason).toBe('Sharpening shears');
    expect(breakAt(MOMENTS.backFromBreak)).toBeNull();
  });

  it('shows one Siri card at a time in each exchange', () => {
    expect(P.break.ask[1]).toBeLessThanOrEqual(P.break.wave[0]);
    expect(P.break.wave[1]).toBeLessThanOrEqual(P.break.reply[1]);
    expect(P.break.reply[1]).toBeLessThanOrEqual(P.break.cardOut[0]);
    expect(P.tree.wave[1]).toBeLessThanOrEqual(P.tree.reply[1]);
    expect(P.shift.wave[1]).toBeLessThanOrEqual(P.shift.reply[1]);
  });

  it('plays each beat in order', () => {
    const seq = [
      P.break.glow[0],
      P.break.said[0],
      P.break.ask[0],
      P.break.wave[0],
      P.break.reply[0],
      P.break.start,
      P.break.cardOut[0],
      P.break.swap,
      P.tree.glow[0],
      ...P.tree.chips,
      P.tree.reply[0],
      P.tree.unlock[0],
      P.tree.unlock[1],
      P.crew.drop[0],
      P.crew.scroll[0],
      P.crew.tap,
      P.crew.swap,
      P.crew.sheetUp[0],
      P.crew.sheetDown[0],
      P.crew.lockIn[0],
      P.crew.lockIn[1],
      P.shift.glow[0],
      P.shift.wave[0],
      P.shift.reply[0],
      P.shift.cardOut[0],
      P.shift.swap,
      P.back.tap,
      P.back.end,
      P.back.la[1],
    ];
    for (let i = 1; i < seq.length; i += 1) expect(seq[i]!, `step ${i}`).toBeGreaterThanOrEqual(seq[i - 1]!);
  });

  it('writes every span forwards', () => {
    const spans: Span[] = [];
    const take = (o: Record<string, unknown>) => {
      for (const v of Object.values(o)) if (Array.isArray(v) && v.length === 2 && typeof v[0] === 'number') spans.push(v as unknown as Span);
    };
    [P.break, P.tree, P.crew, P.shift, P.back].forEach((g) => take(g as unknown as Record<string, unknown>));
    for (const s of spans) expect(ordered(s), String(s)).toBe(true);
  });

  it('leaves the phone at rest by the end of the track', () => {
    expect(P.back.la[1]).toBeLessThanOrEqual(0.985);
  });
});
