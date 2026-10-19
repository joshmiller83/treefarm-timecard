import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { MORE_TO_SAY, SIRI, SIRI_LINES, unverifiedLines } from './siri.ts';
import { CONFLICT_MESSAGE, MOMENTS, SHIFT, fmtSpokenTime, positionAt, treesAt } from './ledger.ts';

const decisions = readFileSync(fileURLToPath(new URL('../../../docs/landing/decisions.md', import.meta.url)), 'utf8');

/** The backticked lines in decisions.md item 1 ("Siri wording"). */
function decisionLines(): string[] {
  const item1 = decisions.split(/\n2\. /)[0]!.split(/\n1\. /)[1]!;
  return [...item1.matchAll(/`([^`]+)`/g)].map((m) => m[1]!);
}

describe('Siri lines match decisions.md character for character', () => {
  const expected = {
    clockIn: 'Clocked in at 7:02. You’re on block 2, row 14.',
    nextRow: 'Row 14 marked, 10 trees. Next is row 15.',
    misheard: 'Row 40 in block 2? That’s 26 rows ahead.',
    backToWork: 'Back at 12:31. Lunch was 30 minutes.',
    breakReason: 'Break for sharpening shears started at 2:30.',
    howMany: '212 trees today, 34 an hour. You’re on block 2, row 35.',
    treeNote: 'Noted on block 2, row 36, tree 7.',
    shiftNote: 'Added to today’s notes.',
    clockOutAsk: 'You’ve worked 8 hours 30 minutes today. Clock out?',
    clockOut: 'Clocked out at 4:31. 8 hours 30 minutes, 290 trees.',
  } as const;

  for (const [key, reply] of Object.entries(expected)) {
    it(`${key}: “${reply}”`, () => {
      expect(SIRI[key as keyof typeof expected].reply).toBe(reply);
    });
  }

  it('covers every full reply quoted in decisions.md', () => {
    const replies = new Set(SIRI_LINES.map((l) => l.reply));
    const quoted = decisionLines().filter((l) => /^[A-Z0-9].*[.?]$/.test(l) && !l.startsWith('Next is'));
    expect(quoted.length).toBeGreaterThanOrEqual(10);
    for (const line of quoted) expect(replies, line).toContain(line);
  });

  it('uses the curly apostrophe and never a straight one', () => {
    for (const l of SIRI_LINES) {
      for (const s of [l.said, l.reply, l.ask, l.answer]) {
        if (s) expect(s, `${l.key}`).not.toContain("'");
      }
    }
    expect(SIRI.clockIn.reply).toContain('’');
  });

  it('shows the conflict message verbatim (the server’s per-tree rejection, PushApplier.taken)', () => {
    expect(SIRI.conflict.reply).toBe('Row 12, tree 1 in Block 3 was shaped by Sam on Oct 16.');
    expect(SIRI.conflict.reply).toBe(CONFLICT_MESSAGE);
  });
});

describe('Siri lines reconcile with the ledger', () => {
  it('speaks ledger times and positions', () => {
    expect(SIRI.clockIn.reply).toContain(fmtSpokenTime(SHIFT.in));
    const p = positionAt(MOMENTS.status);
    expect(SIRI.howMany.reply).toContain(`block ${p.block}, row ${p.row}`);
    expect(SIRI.howMany.reply.startsWith(`${treesAt(MOMENTS.status)} trees`)).toBe(true);
    expect(SIRI.clockOut.reply).toContain(`${treesAt(SHIFT.out)} trees`);
  });

  it('has the app’s name in every phrase you say', () => {
    const commands = SIRI_LINES.filter((l) => l.said && !['Yes.', 'No.'].includes(l.said));
    for (const l of commands) expect(l.said, l.key).toMatch(/Time Card/);
    for (const p of MORE_TO_SAY) expect(p).toMatch(/Time Card$/);
  });

  it('keeps the lines in story order', () => {
    const times = SIRI_LINES.map((l) => l.at);
    expect([...times].sort((a, b) => a - b)).toEqual(times);
  });

  it('does not show the lunch reply', () => {
    expect(SIRI.takeLunch.reply).toBeNull();
  });

  it('lists the lines that still need confirming against the app', () => {
    const keys = unverifiedLines().map((l) => l.key);
    // Every reply above comes from FieldEngine (decisions.md #1). Only the break-reason
    // question is not in TreeFarmKit yet.
    expect(keys).toEqual(['breakReason.ask']);
  });
});
