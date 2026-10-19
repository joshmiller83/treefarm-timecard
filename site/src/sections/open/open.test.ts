import { describe, expect, it } from 'vitest';
import {
  COMMAND,
  DOCS,
  REPO,
  STACK,
  STATUS,
  commandTokens,
  handDrop,
  readmeHasCommand,
  railFill,
  tickOrder,
  typeTimes,
} from './open.ts';

describe('links', () => {
  it('only ever points at the repo (decisions #5: Read the docs → docs/)', () => {
    expect(REPO).toBe('https://github.com/joshmiller83/treefarm-timecard');
    expect(DOCS).toBe(`${REPO}/tree/main/docs`);
  });
});

describe('the stack chips', () => {
  it('are the brief’s seven, in order', () => {
    expect(STACK).toEqual(['SwiftUI', 'App Intents', 'ActivityKit', 'Vapor', 'SQLite', 'Cloudflare Tunnel', 'MIT']);
  });
});

describe('readmeHasCommand (the terminal card renders only if the README has it)', () => {
  it('finds the command in a fenced block', () => {
    expect(readmeHasCommand('# Hi\n\n```bash\nswift test --package-path Packages/TreeFarmKit\n```\n')).toBe(true);
  });
  it('rejects a README without it, or with only a near miss', () => {
    expect(readmeHasCommand('')).toBe(false);
    expect(readmeHasCommand('swift test --package-path Packages/TreeFarm')).toBe(false);
    expect(readmeHasCommand('swift build --package-path Packages/TreeFarmKit')).toBe(false);
  });
  it('accepts it with extra spacing or a prompt in front', () => {
    expect(readmeHasCommand('$ swift  test --package-path   Packages/TreeFarmKit')).toBe(true);
  });
});

describe('commandTokens', () => {
  const tokens = commandTokens(COMMAND);
  it('keeps every character, in order', () => {
    expect(tokens.map((t) => t.text).join('')).toBe(COMMAND);
  });
  it('splits words from single spaces, so a line only breaks between words', () => {
    expect(tokens.map((t) => t.text)).toEqual(['swift', ' ', 'test', ' ', '--package-path', ' ', 'Packages/TreeFarmKit']);
    expect(tokens.filter((t) => t.space)).toHaveLength(3);
  });
  it('numbers characters across tokens for the typing', () => {
    const idx = tokens.flatMap((t) => t.chars.map((c) => c.i));
    expect(idx).toEqual(Array.from({ length: COMMAND.length }, (_, i) => i));
  });
  it('has no dollar sign (the prompt is drawn by CSS)', () => {
    expect(tokens.some((t) => t.text.includes('$'))).toBe(false);
  });
});

describe('typeTimes', () => {
  it('spreads n keystrokes evenly over the duration, first at 0, last before the end', () => {
    const t = typeTimes(4, 1.2);
    expect(t).toHaveLength(4);
    expect(t[0]).toBe(0);
    expect(t[3]).toBeCloseTo(0.9, 10);
    expect(t.every((v, i) => i === 0 || v > t[i - 1]!)).toBe(true);
  });
  it('types the whole command in 1.2 s', () => {
    const t = typeTimes(COMMAND.length, 1.2);
    expect(t.at(-1)!).toBeLessThan(1.2);
    expect(t.at(-1)! + 1.2 / COMMAND.length).toBeCloseTo(1.2, 10);
  });
  it('handles nothing to type', () => {
    expect(typeTimes(0, 1.2)).toEqual([]);
  });
});

describe('tickOrder', () => {
  it('pops the ticks clockwise from 1 o’clock', () => {
    expect(tickOrder([7, 1, 11, 3, 2, 9, 10, 4, 5, 8])).toEqual([1, 2, 3, 4, 5, 7, 8, 9, 10, 11]);
  });
});

describe('handDrop', () => {
  it('is 12 CSS px in the icon’s 1024-unit space, whatever its size', () => {
    expect(handDrop(192)).toBe(64);
    expect(handDrop(128)).toBe(96);
  });
  it('never divides by zero', () => {
    expect(handDrop(0)).toBe(0);
  });
});

describe('the status rail', () => {
  it('states the honest status: used, in development, beta coming, not on the App Store', () => {
    expect(STATUS.map((s) => [s.title, s.note, s.state])).toEqual([
      ['Web time card', 'Used on the farm', 'done'],
      ['iPhone app', 'In active development', 'now'],
      ['TestFlight beta', 'Coming', 'next'],
      ['App Store', 'Not yet', 'next'],
    ]);
  });
  it('has exactly one “now”', () => {
    expect(STATUS.filter((s) => s.state === 'now')).toHaveLength(1);
  });
  it('fills the line from the first step to “now”', () => {
    expect(railFill(STATUS)).toBeCloseTo(1 / 3, 10);
    expect(railFill([{ state: 'now' }])).toBe(0);
    expect(railFill([{ state: 'done' }, { state: 'done' }])).toBe(1);
  });
});
