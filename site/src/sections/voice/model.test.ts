import { describe, expect, it } from 'vitest';
import { BREAKS, MOMENTS, fmtClock, fmtTime, liveActivityAt, positionAt, treesAt } from '../../data/ledger.ts';
import { SIRI } from '../../data/siri.ts';
import { timerAt } from '../../scripts/dayclock.ts';
import {
  BACK,
  BEATS,
  daySteps,
  keepTogether,
  BEFORE_BACK,
  BEFORE_LUNCH,
  DAY_STEPS,
  EXCHANGES,
  LAYERS,
  LUNCH_SPLIT,
  LUNCH_STARTED,
  place,
  splitWords,
  voiceMinute,
  type Source,
} from './model.ts';

const all = (p: number, desk = true): Partial<Record<Source, number>> =>
  desk
    ? { main: p, misheard: p, next: p, lunch: p, status: p }
    : { main: p, misheard: p, next: p, lunchA: p, lunchB: p, status: p };

describe('the exchanges come from siri.ts and the ledger', () => {
  it('has five spoken lines, each naming Time Card', () => {
    const said = EXCHANGES.flatMap((x) => x.turns.filter((t) => t.who === 'you' && t.key !== 'answer').map((t) => t.text));
    expect(said).toEqual([
      SIRI.misheard.said,
      SIRI.nextRow.said,
      SIRI.takeLunch.said,
      SIRI.backToWork.said,
      SIRI.howMany.said,
    ]);
    for (const s of said) expect(s).toContain('Time Card');
  });

  it('uses the replies exactly as siri.ts has them', () => {
    const replies = EXCHANGES.flatMap((x) => x.turns.filter((t) => t.who === 'siri').map((t) => t.text));
    expect(replies).toEqual([SIRI.misheard.reply, SIRI.nextRow.reply, SIRI.backToWork.reply, SIRI.howMany.reply]);
    expect(replies).toContain('Row 40 in block 2? That’s 26 rows ahead.');
    expect(replies).toContain('212 trees today, 34 an hour. You’re on block 2, row 35.');
  });

  it('flags the misheard word and the row Siri heard instead', () => {
    const turns = EXCHANGES[0]!.turns;
    expect(turns[0]).toMatchObject({ key: 'said', mark: 'fourteen' });
    expect(turns[1]).toMatchObject({ key: 'reply', mark: '40' });
  });

  it('stamps each part with its ledger time', () => {
    const stamps = EXCHANGES.flatMap((x) => x.parts.map((p) => p.stamp));
    expect(stamps).toEqual(['7:18 AM', '7:19 AM', '12:01 PM', '12:31 PM', '2:01 PM']);
    expect(EXCHANGES.flatMap((x) => x.parts.map((p) => p.datetime))).toEqual(['07:18', '07:19', '12:01', '12:31', '14:01']);
  });

  it('keeps the pay privacy rule in the copy', () => {
    const status = EXCHANGES.find((x) => x.id === 'status')!;
    expect(status.parts[0]!.caption).toContain('Siri only says your pay out loud if you allow it');
  });

  it('has no dollar figures and no straight apostrophes in any copy', () => {
    const text = JSON.stringify(EXCHANGES);
    expect(text).not.toMatch(/\$\s?\d/);
    expect(text).not.toMatch(/[A-Za-z]'[A-Za-z]/);
  });
});

describe('screen layers match the registry and the ledger', () => {
  it('uses the voice state ids, the last one final', () => {
    expect(LAYERS.map((l) => l.id)).toEqual([
      'lock-0718-misheard',
      'lock-0719-next',
      'lock-1201-lunch',
      'lock-1231-back',
      'lock-1401-status',
    ]);
    expect(LAYERS.filter((l) => l.final).map((l) => l.id)).toEqual(['lock-1401-status']);
  });

  it('shows the Live Activity states from the brief', () => {
    const la = (id: string) => liveActivityAt(LAYERS.find((l) => l.id === id)!.at);
    expect(la('lock-0718-misheard')).toMatchObject({ state: 'working', trees: 0, rows: [14, 15, 16], worked: '0:16:00' });
    expect(la('lock-0719-next')).toMatchObject({ state: 'working', trees: 10, rows: [15, 16, 17] });
    expect(la('lock-1201-lunch')).toMatchObject({ state: 'lunch', pill: 'On lunch', breakTime: '0:00:00', worked: '4:44:00' });
    expect(la('lock-1231-back')).toMatchObject({ state: 'working', rows: [30, 31, 32], worked: '4:44:00' });
    expect(la('lock-1401-status')).toMatchObject({ state: 'working', trees: 212, worked: '6:14:00', rows: [35, 36, 37] });
  });

  it('agrees with what Siri says', () => {
    expect(treesAt(MOMENTS.firstRow)).toBe(10);
    expect(positionAt(MOMENTS.status)).toEqual({ block: 2, row: 35 });
  });
});

describe('the lunch edges read right on every clock', () => {
  const lunch = BREAKS.find((b) => b.kind === 'lunch')!;

  it('the lunch moments are the ledger’s', () => {
    expect(lunch.start).toBe(MOMENTS.lunch);
    expect(lunch.end).toBe(MOMENTS.back);
  });

  it('just before lunch: 12:01 on the clock, 4:44:00 worked, not on lunch yet', () => {
    expect(fmtClock(BEFORE_LUNCH)).toBe('12:01');
    expect(timerAt(BEFORE_LUNCH)).toMatchObject({ kind: 'worked', text: '4:44:00' });
  });

  it('lunch started: the timer reads 0:00:00 and worked stays 4:44:00', () => {
    expect(fmtClock(LUNCH_STARTED)).toBe('12:01');
    expect(timerAt(LUNCH_STARTED)).toMatchObject({ kind: 'lunch', text: '0:00:00' });
    expect(timerAt(LUNCH_STARTED, 'worked').text).toBe('4:44:00');
  });

  it('the last instant of lunch: 12:31 on the clock and the lunch timer at 0:30:00', () => {
    expect(fmtClock(BEFORE_BACK)).toBe('12:31');
    expect(timerAt(BEFORE_BACK)).toMatchObject({ kind: 'lunch', text: '0:30:00' });
  });

  it('back at 12:31: worked time picks up at 4:44:00', () => {
    expect(fmtClock(BACK)).toBe('12:31');
    expect(timerAt(BACK)).toMatchObject({ kind: 'worked', text: '4:44:00' });
  });
});

describe('voiceMinute: the day as a function of every exchange’s progress', () => {
  it('starts at clock-in and ends at the status question', () => {
    expect(voiceMinute(all(0), true)).toBe(MOMENTS.clockIn);
    expect(voiceMinute(all(1), true)).toBe(MOMENTS.status);
    expect(voiceMinute(all(0, false), false)).toBe(MOMENTS.clockIn);
    expect(voiceMinute(all(1, false), false)).toBe(MOMENTS.status);
  });

  it('never runs backwards as the page scrolls forward (desktop and mobile)', () => {
    for (const desk of [true, false]) {
      const order: Source[] = desk
        ? ['main', 'misheard', 'next', 'lunch', 'status']
        : ['main', 'misheard', 'next', 'lunchA', 'lunchB', 'status'];
      let prev = -Infinity;
      for (let i = 0; i < order.length; i += 1) {
        for (let s = 0; s <= 50; s += 1) {
          const p: Partial<Record<Source, number>> = {};
          order.forEach((k, j) => (p[k] = j < i ? 1 : j === i ? s / 50 : 0));
          const min = voiceMinute(p, desk);
          expect(min, `${order[i]} at ${s / 50}`).toBeGreaterThanOrEqual(prev);
          prev = min;
        }
      }
    }
  });

  it('holds 7:18 through the misheard check (nothing changes until you say yes)', () => {
    for (const p of [0.6, 0.7, 0.8, 0.9, 1]) {
      expect(fmtTime(voiceMinute({ main: 0.2, misheard: p }, true))).toBe('7:18 AM');
    }
  });

  it('reads each exchange’s time while its line is spoken', () => {
    expect(fmtTime(voiceMinute({ main: 1, misheard: 1, next: 0.3 }, true))).toBe('7:19 AM');
    expect(fmtTime(voiceMinute({ main: 1, misheard: 1, next: 1, lunch: place('lunchA', 0.4, true).p }, true))).toBe('12:01 PM');
    expect(fmtTime(voiceMinute({ main: 1, misheard: 1, next: 1, lunch: place('lunchB', 0.3, true).p }, true))).toBe('12:31 PM');
    expect(fmtTime(voiceMinute({ ...all(1), status: 0.3 }, true))).toBe('2:01 PM');
  });

  it('maps the lunch halves onto one desktop article and two mobile cards', () => {
    expect(place('lunchA', 1, true)).toEqual({ src: 'lunch', p: LUNCH_SPLIT });
    expect(place('lunchB', 0, true)).toEqual({ src: 'lunch', p: LUNCH_SPLIT });
    expect(place('lunchB', 1, true)).toEqual({ src: 'lunch', p: 1 });
    expect(place('lunchA', 0.5, false)).toEqual({ src: 'lunchA', p: 0.5 });
    // The desktop lunch spin sits at [.45, .55] as the brief asks.
    const spin = DAY_STEPS.find((s) => s.from === LUNCH_STARTED)!;
    expect(place(spin.part, spin.at[0], true).p).toBeCloseTo(0.45, 5);
    expect(place(spin.part, spin.at[1], true).p).toBeCloseTo(0.55, 2);
  });

  it('chains every step from where the last one ended (desktop and mobile)', () => {
    for (const steps of [DAY_STEPS, daySteps(false)]) {
      for (let i = 1; i < steps.length; i += 1) expect(steps[i]!.from).toBe(steps[i - 1]!.to);
    }
  });

  it('puts the lunch edges on the beats the scene flips the Live Activity at', () => {
    for (const desk of [true, false]) {
      const b = desk ? BEATS.desk : BEATS.mob;
      const steps = daySteps(desk);
      expect(steps.find((s) => s.to === LUNCH_STARTED)).toMatchObject({ part: 'lunchA', at: [b.lunchAt, expect.any(Number)] });
      expect(steps.find((s) => s.to === BACK)).toMatchObject({ part: 'lunchB', at: [b.backAt, expect.any(Number)] });
      // Just before the flip the clock already reads the spoken time; just after, lunch has begun (or ended).
      const p = (part: 'lunchA' | 'lunchB', u: number) => {
        const { src, p: v } = place(part, u, desk);
        const before: Partial<Record<Source, number>> = { main: 1, misheard: 1, next: 1, ...(part === 'lunchB' && !desk ? { lunchA: 1 } : {}) };
        return { ...before, [src]: v };
      };
      expect(timerAt(voiceMinute(p('lunchA', b.lunchAt - 0.01), desk))).toMatchObject({ kind: 'worked', text: '4:44:00' });
      expect(timerAt(voiceMinute(p('lunchA', b.lunchAt + 0.03), desk))).toMatchObject({ kind: 'lunch', text: '0:00:00' });
      expect(timerAt(voiceMinute(p('lunchB', b.backAt - 0.01), desk))).toMatchObject({ kind: 'lunch', text: '0:30:00' });
      expect(timerAt(voiceMinute(p('lunchB', b.backAt + 0.03), desk))).toMatchObject({ kind: 'worked', text: '4:44:00' });
    }
  });

  it('on mobile, changes everything on the Live Activity before its card slides over it (~.45)', () => {
    const b = BEATS.mob;
    for (const end of [b.nextDay[1], b.morning[1], b.lunchAt, b.spin[1], b.backAt, b.afternoon[1]]) expect(end).toBeLessThanOrEqual(0.36);
    // Each time-lapse finishes before the spoken line it leads to is lit (the clock reads the line's time).
    expect(b.morning[1]).toBeLessThan(b.lunchAt);
    expect(b.spin[1]).toBeLessThan(b.backAt);
  });

  it('reads each exchange’s time while its line is spoken on mobile', () => {
    const m = (p: Partial<Record<Source, number>>) => fmtTime(voiceMinute({ main: 1, ...p }, false));
    expect(m({ misheard: 1, next: 0.2 })).toBe('7:19 AM');
    expect(m({ misheard: 1, next: 1, lunchA: 0.2 })).toBe('12:01 PM');
    expect(m({ misheard: 1, next: 1, lunchA: 1, lunchB: 0.2 })).toBe('12:31 PM');
    expect(m({ misheard: 1, next: 1, lunchA: 1, lunchB: 1, status: 0.2 })).toBe('2:01 PM');
  });
});

describe('splitWords', () => {
  it('keeps numbers with their units, like the snippet in the phone', () => {
    expect(splitWords(SIRI.howMany.reply!).map((x) => x.w)).toEqual([
      '212\u00a0trees',
      'today,',
      '34\u00a0an\u00a0hour.',
      'You’re',
      'on',
      'block\u00a02,',
      'row\u00a035.',
    ]);
    expect(splitWords(SIRI.backToWork.reply!).map((x) => x.w)).toContain('30\u00a0minutes.');
  });

  it('leaves lines without numbers alone', () => {
    expect(keepTogether('Next row in Time Card.')).toBe('Next row in Time Card.');
  });

  it('splits on spaces and marks a word', () => {
    expect(splitWords('Mark row fourteen in Time Card.', 'fourteen')).toEqual([
      { w: 'Mark', mark: false },
      { w: 'row', mark: false },
      { w: 'fourteen', mark: true },
      { w: 'in', mark: false },
      { w: 'Time', mark: false },
      { w: 'Card.', mark: false },
    ]);
  });
});
