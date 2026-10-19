import { describe, expect, it } from 'vitest';
import { TEAM } from '../../../data/ledger';
import { parseHM, teamTab } from './team';

describe('teamTab', () => {
  const m = teamTab(TEAM);

  it('lists the ledger rows in order with mono-ready strings', () => {
    expect(m.rows.map((r) => [r.name, r.hours, r.trees])).toEqual([
      ['Alex', '38:24', '1,297'],
      ['Sam', '36:50', '1,214'],
      ['Rosa', '31:15', '1,046'],
    ]);
    expect(m.rows.map((r) => r.initial)).toEqual(['A', 'S', 'R']);
    // Each person keeps a distinct avatar tint.
    expect(new Set(m.rows.map((r) => r.tint)).size).toBe(3);
  });

  it('adds up the week', () => {
    // 38:24 + 36:50 + 31:15 = 106:29; 1,297 + 1,214 + 1,046 = 3,557.
    expect(m.total).toBe('3 people · 106:29 h · 3,557 trees');
  });

  it('never shows an invite code, an expiry or pay', () => {
    const text = JSON.stringify(m);
    expect(text).not.toMatch(/\$|code|expire|pay/i);
  });

  it('parseHM reads h:mm', () => {
    expect(parseHM('38:24')).toBe(38 * 60 + 24);
    expect(parseHM('0:05')).toBe(5);
    expect(() => parseHM('38.4')).toThrow();
  });
});
