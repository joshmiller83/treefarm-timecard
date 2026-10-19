import { describe, expect, it } from 'vitest';
import { MOMENTS } from '../../../data/ledger.ts';
import {
  activityLabel,
  activityView,
  bottomInset,
  buttonWidth,
  cardHeight,
  contentWidth,
  LA,
  nextBreakAt,
  stripStep,
  stripWidth,
} from './activity.ts';

describe('Live Activity geometry (brief: LockScreen and LiveActivity)', () => {
  it('is 361 pt wide with its bottom at y 760', () => {
    expect(LA.width).toBe(361);
    expect(LA.left * 2 + LA.width).toBe(393);
    expect(bottomInset).toBe(92);
  });
  it('fits in 160 pt', () => {
    expect(cardHeight).toBeLessThanOrEqual(160);
    expect(cardHeight).toBeGreaterThanOrEqual(150);
  });
  it('shares the row between four equal buttons with 8 pt gaps', () => {
    expect(contentWidth).toBe(333);
    expect(buttonWidth).toBeCloseTo(77.25, 5);
    expect(buttonWidth * 4 + LA.gap * 3).toBeCloseTo(contentWidth, 5);
    expect(stripWidth + LA.gap + buttonWidth).toBeCloseTo(contentWidth, 5);
  });
  it('advances the strip by one button plus the gap', () => {
    expect(stripStep).toBeCloseTo(85.25, 5);
    // After one step, the waiting fourth button sits exactly where the third was.
    const third = 2 * stripStep;
    const fourth = 3 * stripStep;
    expect(fourth - stripStep).toBeCloseTo(third, 5);
    // …and before it, the fourth button starts past the strip's right edge.
    expect(fourth).toBeGreaterThan(stripWidth);
  });
  it('uses 46 pt buttons with a 14 pt radius', () => {
    expect(LA.btnH).toBe(46);
    expect(LA.rows.buttons).toBe(46);
    expect(LA.btnR).toBe(14);
  });
});

describe('activityView from the ledger', () => {
  it('7:02 clock-in: working, nothing shaped yet, rows 14–16', () => {
    const v = activityView({ at: MOMENTS.clockIn });
    expect(v.state).toBe('working');
    expect(v.pill).toBe('On the clock');
    expect(v.timer).toBe('0:00:00');
    expect(v.trees).toBe(0);
    expect(v.place).toBe('North field · Block 2');
    expect(v.fieldPctText).toBe('26');
    expect(v.rows).toEqual([14, 15, 16]);
    expect(v.track).toEqual([14, 15, 16, 17]);
    expect(v.lead).toBe(false);
    expect(v.undoRow).toBeNull();
    expect(v.timerMode).toBe('auto');
  });

  it('7:19 after the first row: 10 trees, rows 15–17', () => {
    const v = activityView({ at: MOMENTS.firstRow });
    expect(v.trees).toBe(10);
    expect(v.rows).toEqual([15, 16, 17]);
  });

  it('12:01 lunch: gold face, lunch timer from zero, worked time held', () => {
    const v = activityView({ at: MOMENTS.lunch });
    expect(v.state).toBe('lunch');
    expect(v.onBreak).toBe(true);
    expect(v.pill).toBe('On lunch');
    expect(v.timer).toBe('0:00:00');
    expect(v.worked).toBe('4:44:00');
  });

  it('2:01 status: 212 trees at 6:14:00', () => {
    const v = activityView({ at: MOMENTS.status });
    expect(v.trees).toBe(212);
    expect(v.worked).toBe('6:14:00');
    expect(v.rows).toEqual([35, 36, 37]);
  });

  it('2:14 before the tap: 6:27:00, 220 trees, 28%, rows 36–38 and 39 waiting', () => {
    const v = activityView({ at: MOMENTS.lockScreen });
    expect(v.state).toBe('working');
    expect(v.timer).toBe('6:27:00');
    expect(v.trees).toBe(220);
    expect(v.fieldPct).toBeCloseTo(0.282, 3);
    expect(v.fieldPctText).toBe('28');
    expect(v.track).toEqual([36, 37, 38, 39]);
  });

  it('2:14 after the tap: 230 trees, Row 36 marked · Undo, rows 37–39', () => {
    const v = activityView({ at: MOMENTS.tapped });
    expect(v.state).toBe('tapped');
    expect(v.trees).toBe(230);
    expect(v.undoRow).toBe(36);
    expect(v.rows).toEqual([37, 38, 39]);
    expect(v.fieldPct).toBeCloseTo(0.283, 3);
    // Row 36 waits off the left edge so a scene can replay the advance.
    expect(v.track).toEqual([36, 37, 38, 39, 40]);
    expect(v.lead).toBe(true);
  });

  it('2:30 break: the voice reason on the pill, 6:43:00 worked, Undo gone', () => {
    const v = activityView({ at: MOMENTS.break });
    expect(v.state).toBe('break');
    expect(v.pill).toBe('On break · Sharpening shears');
    expect(v.timer).toBe('0:00:00');
    expect(v.worked).toBe('6:43:00');
    expect(v.undoRow).toBeNull();
  });

  it('3:40 pace: 7:39:00, 260 trees, rows 39–41', () => {
    const v = activityView({ at: MOMENTS.pace });
    expect(v.worked).toBe('7:39:00');
    expect(v.trees).toBe(260);
    expect(v.rows).toEqual([39, 40, 41]);
  });

  it('4:31 clock-out: 8:30:00, 290 trees, 29%, rows 42–44', () => {
    const v = activityView({ at: MOMENTS.clockOut });
    expect(v.worked).toBe('8:30:00');
    expect(v.trees).toBe(290);
    expect(v.fieldPctText).toBe('29');
    expect(v.rows).toEqual([42, 43, 44]);
  });
});

describe('activityView overrides', () => {
  it('explicit props win over the ledger', () => {
    const v = activityView({ at: MOMENTS.clockIn, trees: 99, rows: [5, 6, 7], field: 'South field', block: 'Block 9' });
    expect(v.treesText).toBe('99');
    expect(v.track).toEqual([5, 6, 7, 8]);
    expect(v.place).toBe('South field · Block 9');
  });

  it('state working at the tapped moment drops Undo', () => {
    const v = activityView({ at: MOMENTS.tapped, state: 'working' });
    expect(v.tapped).toBe(false);
    expect(v.undoRow).toBeNull();
    expect(v.track).toEqual([37, 38, 39, 40]);
  });

  it('state tapped without an undo row marks the row before the strip', () => {
    const v = activityView({ at: MOMENTS.lockScreen, state: 'tapped', rows: [37, 38, 39], undoRow: undefined });
    expect(v.undoRow).toBe(36);
  });

  it('a break from the card button carries no reason', () => {
    const v = activityView({ at: MOMENTS.lockScreen, state: 'break', breakReason: null });
    expect(v.pill).toBe('On break');
  });

  it('fixed freezes the timers', () => {
    const v = activityView({ at: MOMENTS.lockScreen, fixed: true });
    expect(v.timerMode).toBe('fixed');
    expect(v.workedMode).toBe('fixed');
  });

  it('the hidden gold face names the next break', () => {
    expect(activityView({ at: MOMENTS.clockIn }).pillBreak).toBe('On break');
    expect(activityView({ at: MOMENTS.back - 60 }).pillBreak).toBe('On lunch');
    expect(nextBreakAt(MOMENTS.clockOut)).toBeNull();
  });
});

describe('activityLabel', () => {
  it('describes the tapped card without a clock-out button', () => {
    const label = activityLabel(activityView({ at: MOMENTS.tapped }));
    expect(label).toContain('On the clock');
    expect(label).toContain('230 trees this shift');
    expect(label).toContain('Row 36 marked with Undo');
    expect(label).toContain('buttons for row 37, row 38, row 39 and Break');
    expect(label.toLowerCase()).not.toContain('clock out');
  });
  it('describes a break', () => {
    const label = activityLabel(activityView({ at: MOMENTS.break }));
    expect(label).toContain('On break · Sharpening shears');
    expect(label).toContain('6:43:00 worked');
    expect(label).toContain('Back to work');
  });
  it('never mentions pay', () => {
    for (const at of Object.values(MOMENTS)) {
      expect(activityLabel(activityView({ at }))).not.toMatch(/\$|pay/i);
    }
  });
});
