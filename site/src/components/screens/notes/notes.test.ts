import { describe, expect, it } from 'vitest';
import { FLAGS, OLD_NOTE, TREE_NOTE } from '../../../data/ledger';
import { flagTone, noteSheet } from './notes';

describe('noteSheet', () => {
  it('reads like the brief for Alex’s 2:33 PM note', () => {
    const m = noteSheet([TREE_NOTE]);
    expect(m.title).toBe('Block 2 · Row 36 · Tree 7');
    expect(m.subtitle).toBe('North field · 1 note');
    expect(m.notes).toHaveLength(1);
    const n = m.notes[0]!;
    expect(n.flag).toBe('Needs attention');
    expect(n.tone).toBe('attention');
    expect(n.text).toBe('Leader’s broken. Needs a stake.');
    expect(n.byline).toBe('Alex · Today 2:33 PM');
    expect(n.author).toBe('Alex');
    expect(n.initial).toBe('A');
  });

  it('counts notes and keeps them newest first', () => {
    const m = noteSheet([OLD_NOTE, { ...OLD_NOTE, text: 'Second', byline: 'Sam · Today 3:10 PM' }]);
    expect(m.subtitle).toBe('North field · 2 notes');
    expect(m.notes.map((n) => n.text)).toEqual(['Second', OLD_NOTE.text]);
  });

  it('has a tone for exactly the three flags', () => {
    expect(FLAGS.map(flagTone)).toEqual(['attention', 'dead', 'replant']);
  });

  it('needs at least one note', () => {
    expect(() => noteSheet([])).toThrow();
  });
});
