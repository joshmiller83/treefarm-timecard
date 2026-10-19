import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, describe, expect, it } from 'vitest';
import { CAPTURE_SIZE, findCapture, isStateId } from './capture.ts';

const dir = mkdtempSync(join(tmpdir(), 'screens-'));
afterAll(() => rmSync(dir, { recursive: true, force: true }));

describe('findCapture', () => {
  it('returns null when no capture exists (the HTML recreation renders)', () => {
    expect(findCapture('lock-1414-activity', dir)).toBeNull();
  });

  it('finds a PNG capture by state id', () => {
    writeFileSync(join(dir, 'trees-1415-block2.png'), '');
    expect(findCapture('trees-1415-block2', dir)).toBe('/screens/trees-1415-block2.png');
  });

  it('prefers AVIF, then WebP, then PNG', () => {
    writeFileSync(join(dir, 'report-week.png'), '');
    writeFileSync(join(dir, 'report-week.webp'), '');
    expect(findCapture('report-week', dir)).toBe('/screens/report-week.webp');
    writeFileSync(join(dir, 'report-week.avif'), '');
    expect(findCapture('report-week', dir)).toBe('/screens/report-week.avif');
  });

  it('ignores ids that are not plain kebab-case (no path tricks)', () => {
    writeFileSync(join(dir, 'x.png'), '');
    expect(isStateId('lock-1414-tapped')).toBe(true);
    expect(isStateId('../x')).toBe(false);
    expect(isStateId('Lock 1414')).toBe(false);
    expect(findCapture('../screens/x', dir)).toBeNull();
  });

  it('expects 1179 × 2556 captures (393 × 852 pt at 3x)', () => {
    expect(CAPTURE_SIZE.width / 3).toBe(393);
    expect(CAPTURE_SIZE.height / 3).toBe(852);
  });
});
