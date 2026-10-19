import { describe, expect, it } from 'vitest';
import { t } from '../data/ledger.ts';
import { CHAPTERS } from '../data/chapters.ts';
import {
  DAY_END,
  DAY_START,
  createDay,
  dialAngle,
  readout,
  ribbonPct,
  ribbonTag,
  ringFraction,
  tickPct,
  timerAt,
} from './dayclock.ts';

describe('the 12-hour dial', () => {
  it('puts the fir hand at 211deg at 7:02, 360deg at noon and 495.5deg at 4:31', () => {
    expect(dialAngle(t(7, 2))).toBe(211);
    expect(dialAngle(t(12, 0))).toBe(360);
    expect(dialAngle(t(16, 31))).toBe(495.5);
  });

  it('keeps turning forward instead of wrapping, so scrubbing never spins backwards past noon', () => {
    expect(dialAngle(t(12, 1))).toBeGreaterThan(dialAngle(t(11, 59)));
  });

  it('fills the gold ring from 7 AM to now', () => {
    expect(ringFraction(t(7, 0))).toBe(0);
    expect(ringFraction(t(13, 0))).toBe(0.5);
    expect(ringFraction(t(16, 31))).toBeCloseTo(571 / 720, 6);
    expect(ringFraction(t(6, 0))).toBe(0);
    expect(ringFraction(t(23, 0))).toBe(1);
  });
});

describe('the shift ribbon', () => {
  it('starts at 7:02 and puts each chapter on its own evenly spaced tick', () => {
    expect(DAY_START).toBe(422);
    expect(DAY_END).toBe(991);
    CHAPTERS.forEach((c, i) => {
      expect(tickPct(i)).toBeCloseTo(i / (CHAPTERS.length - 1), 9);
      if (c.id !== 'open') expect(ribbonPct(c.minute), c.id).toBeCloseTo(tickPct(i), 9);
    });
  });

  it('is 0% at 7:02 and full once the shift is clocked out', () => {
    expect(ribbonPct(t(7, 2))).toBe(0);
    expect(ribbonPct(t(6, 0))).toBe(0);
    expect(ribbonPct(t(16, 31), 1)).toBe(1);
    expect(ribbonPct(t(16, 31), 0.5)).toBeCloseTo(7 / 8 + 0.5 / 8, 9);
  });

  it('never moves backwards as the day goes on', () => {
    let last = -1;
    for (let m = DAY_START - 5; m <= DAY_END + 5; m += 0.25) {
      const p = ribbonPct(m);
      expect(p).toBeGreaterThanOrEqual(last);
      last = p;
    }
  });

  it('interpolates inside a chapter', () => {
    // Halfway from 7:18 (voice) to 2:14 (lock screen) is halfway between their ticks.
    const mid = (t(7, 18) + t(14, 14)) / 2;
    expect(ribbonPct(mid)).toBeCloseTo(1.5 / 8, 9);
  });

  it('reads the ribbon tag at each chapter start exactly as the brief lists it', () => {
    for (const c of CHAPTERS) {
      expect(ribbonTag(c.minute, c.id)).toBe(c.ribbonTag);
    }
    expect(ribbonTag(t(14, 16), 'lock-screen')).toBe('2:16 PM · Lock screen');
    expect(ribbonTag(t(16, 31), 'clock-out', 1)).toBe('End of shift');
  });
});

describe('timers at any minute', () => {
  it('shows worked time while working', () => {
    expect(timerAt(t(14, 14))).toEqual({ kind: 'worked', seconds: 6 * 3600 + 27 * 60, text: '6:27:00' });
    expect(timerAt(t(7, 2) + 1 / 60).text).toBe('0:00:01');
  });

  it('shows the break timer on lunch and on a break, and can be forced to worked time', () => {
    expect(timerAt(t(12, 1))).toEqual({ kind: 'lunch', seconds: 0, text: '0:00:00' });
    expect(timerAt(t(12, 31) - 0.5).text).toBe('0:29:30');
    expect(timerAt(t(14, 33))).toEqual({ kind: 'break', seconds: 180, text: '0:03:00' });
    expect(timerAt(t(14, 33), 'worked').text).toBe('6:43:00');
    expect(timerAt(t(14, 1), 'break').text).toBe('0:00:00');
  });

  it('adds idle real-time seconds to the timer, but only while working', () => {
    expect(timerAt(t(7, 2), 'auto', 3).text).toBe('0:00:03');
    expect(timerAt(t(14, 30), 'worked', 4).text).toBe('6:43:00');
    expect(timerAt(t(14, 30), 'break', 4).text).toBe('0:00:04');
  });
});

describe('one readout for every surface', () => {
  it('derives the status bar, ribbon, tag and dial from one minute', () => {
    const r = readout({ min: t(14, 14), done: 0, chapter: 'lock-screen', idle: 0 });
    expect(r.clock).toBe('2:14');
    expect(r.tag).toBe('2:14 PM · Lock screen');
    expect(r.angle).toBe(427);
    expect(r.ribbon).toBeCloseTo(2 / 8, 9);
    expect(r.timer.text).toBe('6:27:00');
  });

  it('moves the status bar clock with idle seconds', () => {
    expect(readout({ min: t(7, 2) + 59 / 60, done: 0, chapter: 'hero', idle: 2 }).clock).toBe('7:03');
  });
});

describe('the shared day object', () => {
  const fakeTl = () => {
    const calls: Array<[object, Record<string, number>, Record<string, unknown>, number]> = [];
    return { calls, fromTo: (target: object, from: object, to: object, at?: number) => (calls.push([target, from as Record<string, number>, to as Record<string, unknown>, at ?? 0]), undefined) };
  };

  it('starts at 7:02 and records tweens on the section’s own track', () => {
    const day = createDay();
    expect(day.min).toBe(422);
    const tl = fakeTl();
    day.to(tl, t(14, 14), 0, 0.08, t(14, 1));
    expect(tl.calls).toHaveLength(1);
    const [target, from, to, at] = tl.calls[0]!;
    expect(target).toBe(day.peek(tl));
    expect(target).not.toBe(day);
    expect(day.peek(tl)!.min).toBe(t(14, 1));
    expect(from.min).toBe(t(14, 1));
    expect(to.min).toBe(t(14, 14));
    expect(to.duration as number).toBeCloseTo(0.08, 9);
    expect(to.ease).toBe('none');
    expect(to.immediateRender).toBe(false);
    expect(at).toBe(0);
  });

  it('chains from where the previous tween on the same timeline ended', () => {
    const day = createDay();
    const tl = fakeTl();
    day.to(tl, t(12, 1), 0.4, 0.5, t(7, 19));
    day.to(tl, t(12, 31), 0.5, 0.6);
    expect(tl.calls[1]![1].min).toBe(t(12, 1));
  });

  it('starts a track at the timeline’s dayStart', () => {
    const day = createDay();
    const tl = Object.assign(fakeTl(), { dayStart: t(15, 40) });
    day.to(tl, t(16, 31), 0, 0.08);
    expect(tl.calls[0]![1].min).toBe(t(15, 40));
  });

  it('shows only the active section’s track', () => {
    const day = createDay();
    const a = fakeTl();
    const b = fakeTl();
    day.to(a, t(12, 1), 0, 1, t(7, 18));
    day.to(b, t(14, 14), 0, 1, t(14, 1));
    expect(day.now().min).toBe(422);
    day.source = day.peek(b)!;
    expect(day.now().min).toBe(t(14, 1));
    day.complete(b, 0.3, 0.36);
    expect(b.calls[1]![2].done).toBe(1);
  });
});
