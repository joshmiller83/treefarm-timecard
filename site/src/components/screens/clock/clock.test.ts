import { describe, expect, it } from 'vitest';
import { MOMENTS, SHIFT_NOTE, t } from '../../../data/ledger';
import { clockTab, minutesText, percentShaped } from './clock';

const everyString = (v: unknown): string[] =>
  typeof v === 'string' ? [v] : Array.isArray(v) ? v.flatMap(everyString) : v && typeof v === 'object' ? Object.values(v).flatMap(everyString) : [];

describe('clockTab at 3:40 PM (the pace chapter)', () => {
  const m = clockTab(MOMENTS.pace);

  it('status card reads like the brief', () => {
    expect(m.status.phase).toBe('working');
    expect(m.status.pill).toBe('On the clock');
    expect(m.status.timer).toBe('7:39:00');
    expect(m.status.workedLabel).toBe('worked today');
    expect(m.status.clockedIn).toBe('Clocked in at 7:02 AM');
    expect(m.status.meta).toBe('Clocked in at 7:02 AM · Breaks 59 min');
    expect(m.status.date).toBe('Friday, Oct 16');
    expect(m.status.breakLine).toBeNull();
  });

  it('now working: North field, block 2, row 39 with the next three rows', () => {
    expect(m.now).not.toBeNull();
    expect(m.now!.field).toBe('North field');
    expect(m.now!.place).toBe('Block 2 · Row 39');
    expect(m.now!.rows).toEqual([39, 40, 41]);
    expect(m.now!.waiting).toBeNull();
  });

  it('trees this shift and the field line', () => {
    expect(m.trees.label).toBe('Trees this shift');
    expect(m.trees.big).toBe('260');
    expect(m.trees.line).toBe('2,460 of 8,540 trees shaped in North field · 29%');
    expect(m.trees.fraction).toBeCloseTo(2460 / 8540, 5);
  });

  it('pace rows match the ledger and the brief', () => {
    expect(m.pace.range).toBe('today');
    expect(m.pace.treesHour).toEqual({ value: '34', unit: 'trees an hour' });
    expect(m.pace.perTree).toEqual({ value: '1:46', unit: 'a tree' });
    expect(m.pace.pay).toEqual({ label: 'Pay per tree', value: '•••' });
    expect(m.pace.best).toBe('Best day · Thu, Oct 15 · 318 trees');
    expect(m.pace.left).toBe('About 179 hours left in North field at your pace');
  });

  it('shift notes carry the 2:36 dictated note', () => {
    expect(m.notes.text).toBe(SHIFT_NOTE);
  });

  it('hours: the week chart, today in gold, pay hidden', () => {
    const labels = m.hours.days.map((d) => `${d.label} ${d.hm}`);
    expect(labels).toEqual(['Mon 8:37', 'Tue 8:18', 'Wed 5:45', 'Thu 8:45', 'Fri 7:39', 'Sat –', 'Sun –']);
    expect(m.hours.days.filter((d) => d.today).map((d) => d.key)).toEqual(['fri']);
    // Thursday is the longest day, so it fills the chart; the rest scale against it.
    expect(m.hours.days.find((d) => d.key === 'thu')!.fraction).toBe(1);
    expect(m.hours.days.find((d) => d.key === 'wed')!.fraction).toBeCloseTo(345 / 525, 5);
    expect(m.hours.days.find((d) => d.key === 'sat')!.fraction).toBe(0);
    expect(m.hours.today).toBe('7:39');
    expect(m.hours.week).toBe('39:04');
    expect(m.hours.pay).toBe('•••');
    expect(m.hours.footnote).toBe('Mon, Oct 12 – Fri, Oct 16. Breaks don’t count toward hours. Pay never shows on the report.');
  });

  it('never shows a currency figure', () => {
    for (const s of everyString(m)) expect(s).not.toMatch(/\$|USD|€|£/);
  });
});

describe('clockTab at other moments', () => {
  it('on the sharpening break at 2:33 PM the card turns to the break state', () => {
    const m = clockTab(MOMENTS.treeNote);
    expect(m.status.phase).toBe('break');
    expect(m.status.pill).toBe('On break');
    expect(m.status.timer).toBe('6:43:00');
    expect(m.status.workedLabel).toBe('worked today · paused while you’re on break');
    expect(m.status.breakLine).toBe('Break started 2:30 PM · Sharpening shears');
    expect(m.status.breakSoFar).toBe('0:03:00');
    expect(m.status.meta).toBe('Clocked in at 7:02 AM');
    expect(m.now!.waiting).toBe('Row 37 is next when you’re back.');
    expect(m.trees.big).toBe('230');
    // The shift note comes at 2:36, so the editor is still empty here.
    expect(m.notes.text).toBe('');
  });

  it('lunch says lunch and leaves out the reason', () => {
    const m = clockTab(t(12, 10));
    expect(m.status.phase).toBe('lunch');
    expect(m.status.pill).toBe('On lunch');
    expect(m.status.breakLine).toBe('Lunch started 12:01 PM');
    expect(m.status.breakSoFar).toBe('0:09:00');
  });

  it('helping Sam on block 3 at 2:47 PM', () => {
    const m = clockTab(MOMENTS.crew);
    expect(m.now!.place).toBe('Block 3 · Row 11');
    expect(m.now!.rows).toEqual([11, 12, 13]);
  });

  it('after clock-out the card is off the clock', () => {
    const m = clockTab(t(16, 40));
    expect(m.status.phase).toBe('off');
    expect(m.status.pill).toBe('Off the clock');
    expect(m.status.timer).toBe('8:30:00');
    expect(m.status.meta).toBe('Last clocked out at 4:31 PM.');
    expect(m.now).toBeNull();
    expect(m.trees.label).toBe('Field');
    // 2,190 earlier + Alex's 290 + Sam's 10 = 2,490 of 8,540.
    expect(m.trees.big).toBe('29%');
    expect(m.trees.line).toBe('2,490 of 8,540 trees shaped in North field');
  });

  it('before clock-in nothing is counted yet', () => {
    const m = clockTab(t(6, 50));
    expect(m.status.phase).toBe('off');
    expect(m.status.meta).toBe('Not clocked in yet today.');
    expect(m.status.timer).toBe('0:00:00');
    expect(m.pace.treesHour.value).toBe('–');
    expect(m.pace.perTree.value).toBe('–');
  });

  it('the week range uses every shift this week', () => {
    const m = clockTab(MOMENTS.pace, 'week');
    // Mon–Thu 1,057 trees in 31:25, plus Friday's 260 in 7:39: 1,317 trees in 39:04.
    expect(m.pace.range).toBe('week');
    expect(m.pace.treesHour.value).toBe(String(Math.round(1317 / (2344 / 60))));
    expect(m.pace.perTree.value).toBe('1:47');
  });
});

describe('helpers', () => {
  it('minutesText reads like the app', () => {
    expect(minutesText(0)).toBe('0 min');
    expect(minutesText(59 * 60)).toBe('59 min');
    expect(minutesText(60 * 60)).toBe('1 h');
    expect(minutesText(65 * 60)).toBe('1 h 5 min');
  });

  it('percentShaped never says 100 until every tree is done', () => {
    expect(percentShaped(0, 0)).toBe(0);
    expect(percentShaped(8539, 8540)).toBe(99);
    expect(percentShaped(8540, 8540)).toBe(100);
    expect(percentShaped(2460, 8540)).toBe(29);
  });
});
