/**
 * BUILT IN THE OPEN: the section's copy data and the small pure helpers its markup and
 * scene share (unit-tested in open.test.ts). Importing this never pulls in GSAP.
 */

export const REPO = 'https://github.com/joshmiller83/treefarm-timecard';
/** decisions.md #5: "Read the docs" goes to the repo's docs folder. */
export const DOCS = `${REPO}/tree/main/docs`;

/** The command the terminal card types; shown only if the repo README has it (brief: open). */
export const COMMAND = 'swift test --package-path Packages/TreeFarmKit';

export const STACK = ['SwiftUI', 'App Intents', 'ActivityKit', 'Vapor', 'SQLite', 'Cloudflare Tunnel', 'MIT'] as const;

export type StepState = 'done' | 'now' | 'next';
export interface Step {
  title: string;
  note: string;
  state: StepState;
}

/**
 * Where the project stands, in the page map's own language: green = done, gold = now,
 * ring = not yet. Every line restates the body copy; nothing here is a date or a promise.
 * Only the "now" note is shown (see showsNote); screen readers hear every note.
 */
export const STATUS: readonly Step[] = [
  { title: 'Web time card', note: 'Used on the farm', state: 'done' },
  { title: 'iPhone app', note: 'In active development', state: 'now' },
  { title: 'TestFlight beta', note: 'Coming', state: 'next' },
  { title: 'App Store', note: 'Not yet', state: 'next' },
];

/**
 * The sentence above the rail already states all three facts, so on screen the rail stays a
 * quiet picture: the dots say done and not yet, and only "now" carries its words.
 */
export function showsNote(step: { state: StepState }): boolean {
  return step.state === 'now';
}

/** How much of the rail's line is filled: from the first step to the 'now' step (0–1). */
export function railFill(steps: ReadonlyArray<{ state: StepState }>): number {
  if (steps.length < 2) return 0;
  const now = steps.findIndex((s) => s.state === 'now');
  const last = now >= 0 ? now : steps.map((s) => s.state).lastIndexOf('done');
  return Math.max(0, last) / (steps.length - 1);
}

/** True when the README really shows the command (whitespace-insensitive, as a grep would). */
export function readmeHasCommand(readme: string, command: string = COMMAND): boolean {
  const norm = (s: string) => s.replace(/[ \t]+/g, ' ');
  return norm(readme).includes(norm(command));
}

export interface Token {
  text: string;
  space: boolean;
  chars: Array<{ ch: string; i: number }>;
}

/** Words and single spaces, each character numbered in typing order. Lines break only at spaces. */
export function commandTokens(command: string = COMMAND): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  for (const part of command.split(/( )/)) {
    if (!part) continue;
    tokens.push({ text: part, space: part === ' ', chars: Array.from(part, (ch) => ({ ch, i: i++ })) });
  }
  return tokens;
}

/** When each of n keystrokes lands (seconds) when typing evenly over `duration`. */
export function typeTimes(n: number, duration: number): number[] {
  if (n <= 0) return [];
  const step = duration / n;
  return Array.from({ length: n }, (_, k) => k * step);
}

/** The icon's tick hours in clockwise order from 1 o'clock (12 and 6 are not drawn). */
export function tickOrder(hours: readonly number[]): number[] {
  return [...hours].sort((a, b) => a - b);
}

/** The fir hand rises from 12 CSS px below: that distance in the icon's 1024-unit viewBox. */
export function handDrop(iconPx: number, cssPx = 12): number {
  if (!(iconPx > 0)) return 0;
  return Math.round((cssPx * 1024) / iconPx);
}
