import { describe, expect, it } from 'vitest';
import { FLAGS, MOMENTS, OLD_NOTE, TREE_NOTE, t } from '../../../data/ledger';
import { flagTone, noteSheet, treeShaped } from './notes';

describe('noteSheet', () => {
  it('reads like the brief for Alex’s 2:33 PM note', () => {
    const m = noteSheet([TREE_NOTE]);
    expect(m.title).toBe('Block 2 · Row 36 · Tree 7');
    expect(m.subtitle).toBe('North field');
    expect(m.count).toBe('1 note');
    expect(m.shaped).toEqual({ state: 'today', text: 'Shaped today at 2:14 PM by Alex' });
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
    expect(m.count).toBe('2 notes');
    expect(m.notes.map((n) => n.text)).toEqual(['Second', OLD_NOTE.text]);
  });

  it('has a tone for exactly the three flags', () => {
    expect(FLAGS.map(flagTone)).toEqual(['attention', 'dead', 'replant']);
  });

  it('says whether the tree is shaped, the way the map colors it', () => {
    // Row 36 was tapped on the lock screen at 2:14 PM.
    expect(treeShaped(2, 36, MOMENTS.lockScreen - 1)).toEqual({ state: 'not-yet', text: 'Not shaped yet this season' });
    expect(treeShaped(2, 36, MOMENTS.treeNote).text).toBe('Shaped today at 2:14 PM by Alex');
    // Block 2 rows 1–13 were shaped earlier this season.
    expect(treeShaped(2, 5, MOMENTS.treeNote)).toEqual({ state: 'earlier', text: 'Shaped earlier this season' });
    // Sam's row 12 in block 3 at 2:49 PM wins over Alex's later mark.
    expect(treeShaped(3, 12, t(15, 0)).text).toBe('Shaped today at 2:49 PM by Sam');
    // A sheet before the note's own row was marked says so.
    expect(noteSheet([TREE_NOTE], t(14, 0)).shaped.state).toBe('not-yet');
  });

  it('needs at least one note', () => {
    expect(() => noteSheet([])).toThrow();
  });
});
