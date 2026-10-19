import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { PAUSE_EVENT } from './header.ts';

describe('the motion core', () => {
  it('listens for the same Pause motion event the header sends (without importing header.ts)', () => {
    const src = readFileSync(new URL('./motion.ts', import.meta.url), 'utf8');
    expect(src).not.toMatch(/from '\.\/header\.ts'/);
    expect(src).toContain(`const PAUSE_EVENT = '${PAUSE_EVENT}';`);
  });

  it('does not ship the unused Flip plugin', () => {
    const src = readFileSync(new URL('./motion.ts', import.meta.url), 'utf8');
    expect(src).not.toMatch(/gsap\/Flip/);
  });
});
