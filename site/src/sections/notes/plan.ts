/**
 * NOTES · the scroll plan. Pure data: where every beat of the scene sits in the section's
 * scrubbed timeline (progress 0–1), for the desktop stage ('desk') and the mobile section
 * phone ('mob'). Notes.astro places the copy beats with AT; scenes/notes.ts places the phone
 * with plan(mode); plan.test.ts checks the order, the day and the one-card-at-a-time rule.
 *
 * Each copy beat sits at progress `at` (a little below the middle on desktop, at the card
 * anchor on mobile). Its phone sequence is written once, in desktop progress units relative
 * to `at`, then scaled per mode so it takes about the same scroll distance on both tracks.
 * On mobile it is led so that each Siri reply and Live Activity change lands as its card's
 * top reaches 70% of the viewport (the brief's 'top 70%'), and the steps between beats wait
 * for the card that tells them to fade: the phone never moves on while its card is read.
 *
 * Desktop copy fades out by position, not progress (scenes/notes.ts): each beat is gone by
 * the time its top reaches the header, whatever the viewport height.
 *
 *   0         2:16 → 2:30, the lock screen as the lock-screen chapter left it (Row 36 marked)
 *   break     "Take a break" → "What's the break for?" → "Sharpening shears." → 2:30, gold
 *   tree      "Note a tree" → four answers → "Noted on block 2, row 36, tree 7." → unlock
 *   crew      the flag drops on row 36 tree 7 → the map scrolls → tap → the sheet rises
 *   shift     the lock screen returns → "Add a note" → dictation → "Added to today's notes."
 *   back      2:44, tap Back to work → green again at 6:43:00, rows 37, 38, 39 and Break
 */
import { MOMENTS, type Minute } from '../../data/ledger.ts';

export type Mode = 'desk' | 'mob';
export type BeatKey = 'break' | 'tree' | 'crew' | 'shift' | 'back';
export const BEAT_KEYS: readonly BeatKey[] = ['break', 'tree', 'crew', 'shift', 'back'];

/** Track heights under motion (SectionShell's `track` prop). */
export const TRACK = { desk: '360vh', mob: '480vh' } as const;

/** Where each copy beat sits (progress 0–1): its --at. */
export const AT: Record<Mode, Record<BeatKey, number>> = {
  desk: { break: 0.19, tree: 0.39, crew: 0.585, shift: 0.775, back: 0.945 },
  mob: { break: 0.17, tree: 0.35, crew: 0.54, shift: 0.725, back: 0.89 },
};

/**
 * How much the phone leads its copy. On mobile the cards rise over the lower phone: each
 * Siri reply lands as its card's top reaches 70% of the viewport (about 0.045–0.07 before
 * `at` for a 360–460 px card on a 480vh track at 812 px), so the exchange plays above the
 * card while it enters, and the card's text simply reads (it does not animate there).
 * The crew sequence instead starts right after the unlock (see the ties in plan()).
 */
export const LEAD: Record<Mode, Record<BeatKey, number>> = {
  desk: { break: 0, tree: 0, crew: 0, shift: 0, back: 0 },
  mob: { break: 0.045, tree: 0.066, crew: 0.0768, shift: 0.0666, back: 0.02 },
};

/** Phone sequences are authored in desktop units; mobile compresses them (a taller track). */
export const SCALE: Record<Mode, number> = { desk: 1, mob: 0.64 };

/**
 * Mobile cards fade out over the phone, done when the card's top is about a third of the way
 * down the phone (before its text covers the lock screen's clock): `end` past `at`.
 * The break card is shorter, so it gets further before it reaches that line.
 */
export const MOB_OUT: Record<Exclude<BeatKey, 'back'>, number> = { break: 0.056, tree: 0.044, crew: 0.044, shift: 0.044 };
const MOB_FADE = 0.01;

/** A span [start, end] in progress units. */
export type Span = readonly [number, number];

export interface DayStep {
  min: Minute;
  start: number;
  end: number;
}

export interface Plan {
  mode: Mode;
  at: Record<BeatKey, number>;
  /** DayClock tweens, in order (each starts where the last one ended). */
  day: DayStep[];
  /** Copy beats: fade in and out around `at` (head: out only; back: in only). */
  copy: Record<'head' | BeatKey, { in: Span | null; out: Span | null }>;
  break: {
    glow: Span; // glow on
    said: Span; // karaoke on the page
    ask: Span; // the "What's the break for?" card drops in
    askType: Span; // and types
    askLine: Span; // the page's Siri line
    wave: Span; // the dictation card replaces the ask, scrubbed noise
    answer: Span; // "Sharpening shears." types in the phone and on the page
    reply: Span; // the reply card replaces the wave
    replyType: Span;
    /** The break starts: day reaches 2:30 here and the card turns gold. */
    start: number;
    la: Span; // the Live Activity's break transition
    glowOff: Span;
    cardOut: Span; // the reply leaves, the lock screen's clock returns
    /** Swap to the next lock layer (identical pixels: no visible change). */
    swap: number;
  };
  tree: {
    glow: Span;
    said: Span;
    wave: Span;
    chips: [number, number, number, number];
    chipDur: number;
    note: Span; // the note text types in the phone (with the quote chip)
    reply: Span;
    replyType: Span;
    glowOff: Span;
    unlock: Span;
  };
  crew: {
    drop: Span; // the rust flag drops onto row 36, tree 7
    ripple: Span;
    scroll: Span; // the map scrolls so the tree will sit above the sheet
    tap: number; // a tap on the flag
    swap: number; // to the sheet layer (same map, the tree selected)
    sheetUp: Span;
    sheetDown: Span;
    lockIn: Span; // the lock screen slides back down from the top
  };
  shift: {
    glow: Span;
    said: Span;
    wave: Span;
    type: Span; // the transcript types in the phone and in the copy
    reply: Span;
    replyType: Span;
    strip: Span; // the paper time-card strip prints
    glowOff: Span;
    cardOut: Span;
    swap: number;
  };
  back: {
    tap: number;
    /** The break ends: day reaches 2:44 and the card turns green. */
    end: number;
    la: Span;
  };
}

/** A minute just before a boundary, so a timer reads the old state until the event. */
const JUST_BEFORE = 0.5;

/**
 * Where, through each Live Activity transition, the day crosses its boundary (2:30, 2:44) and
 * the card's data-state switches: after the pill faces and Undo have crossed (break), after
 * the gold face has gone (back), so the timer never shows one state under the other's pill.
 */
export const LA_SWITCH = { break: 0.2, back: 0.28 } as const;

export function plan(mode: Mode): Plan {
  const at = AT[mode];
  const k = SCALE[mode];
  const lead = LEAD[mode];
  // Position helper: offset `o` (desktop units) from beat `b`'s phone anchor.
  const p = (b: BeatKey, o: number) => round(at[b] - lead[b] + o * k);
  const s = (b: BeatKey, a: number, z: number): Span => [p(b, a), p(b, z)];

  const brk = {
    glow: s('break', -0.09, -0.072),
    said: s('break', -0.088, -0.06),
    ask: s('break', -0.058, -0.05),
    askType: s('break', -0.054, -0.044),
    askLine: s('break', -0.05, -0.04),
    wave: s('break', -0.036, 0.004),
    answer: s('break', -0.03, -0.012),
    reply: s('break', 0.004, 0.012),
    replyType: s('break', 0.008, 0.022),
    start: 0,
    la: s('break', 0.004, 0.045),
    glowOff: s('break', 0.03, 0.05),
    cardOut: s('break', 0.072, 0.082),
    swap: p('break', 0.09),
  };
  // The pill and Undo cross over first; the timer and the gold state switch under them.
  brk.start = round(brk.la[0] + (brk.la[1] - brk.la[0]) * LA_SWITCH.break);
  const tree = {
    glow: s('tree', -0.1, -0.082),
    said: s('tree', -0.097, -0.068),
    wave: s('tree', -0.074, 0.004),
    chips: [p('tree', -0.058), p('tree', -0.044), p('tree', -0.03), p('tree', -0.016)] as [number, number, number, number],
    chipDur: round(0.012 * k),
    note: s('tree', -0.03, -0.012),
    reply: s('tree', 0.004, 0.012),
    replyType: s('tree', 0.008, 0.022),
    glowOff: s('tree', 0.028, 0.045),
    unlock: s('tree', 0.052, 0.078),
  };
  const crew = {
    drop: s('crew', -0.08, -0.064),
    ripple: s('crew', -0.068, -0.046),
    scroll: s('crew', -0.048, -0.026),
    tap: p('crew', -0.026),
    swap: p('crew', -0.018),
    sheetUp: s('crew', -0.012, 0.022),
    sheetDown: s('crew', 0.058, 0.078),
    lockIn: s('crew', 0.082, 0.106),
  };
  const shift = {
    glow: s('shift', -0.082, -0.064),
    said: s('shift', -0.079, -0.052),
    wave: s('shift', -0.056, 0.004),
    type: s('shift', -0.044, -0.006),
    reply: s('shift', 0.004, 0.012),
    replyType: s('shift', 0.008, 0.022),
    strip: s('shift', 0.012, 0.03),
    glowOff: s('shift', 0.028, 0.045),
    cardOut: s('shift', 0.062, 0.072),
    swap: p('shift', 0.078),
  };
  const backLa = s('back', -0.022, 0.022);
  const back = {
    tap: p('back', -0.03),
    // The gold face has gone before the timer resumes and the card turns green.
    end: round(backLa[0] + (backLa[1] - backLa[0]) * LA_SWITCH.back),
    la: backLa,
  };

  // Copy fades. Desktop: in by progress as the beat rises, out by position (the scene's
  // ScrollTriggers). Mobile: out over the phone; nothing fades in (the cards slide up).
  const out = (b: Exclude<BeatKey, 'back'>): Span => [round(at[b] + MOB_OUT[b] - MOB_FADE), round(at[b] + MOB_OUT[b])];
  const fade = (b: BeatKey): { in: Span | null; out: Span | null } =>
    mode === 'desk' ? { in: [round(at[b] - 0.12), round(at[b] - 0.05)], out: null } : { in: null, out: b === 'back' ? null : out(b) };
  const copy = {
    head: { in: null, out: null },
    break: fade('break'),
    tree: fade('tree'),
    crew: fade('crew'),
    shift: fade('shift'),
    back: fade('back'),
  };

  if (mode === 'mob') {
    // The phone holds "Noted on block 2, row 36, tree 7." while the tree card is read, and
    // unlocks only as that card fades; the flag drops right after (crew's lead is set so).
    const t = copy.tree.out![1];
    tree.unlock = [t, round(t + 0.016)];
    // The sheet stays up while the crew card is read, then lowers and the lock screen returns.
    const c = copy.crew.out![1];
    crew.sheetDown = [c, round(c + 0.008)];
    crew.lockIn = [round(c + 0.009), round(c + 0.02)];
  }

  const day: DayStep[] = [
    // 2:16 → just before 2:30 while the heading reads, then 2:30 exactly as Siri starts the break.
    { min: MOMENTS.break - JUST_BEFORE / 60, start: 0, end: round(brk.start - 0.012 * k) },
    { min: MOMENTS.break, start: round(brk.start - 0.012 * k), end: brk.start },
    // The break timer spins to 0:03:00 by "Noted on block 2, row 36, tree 7."
    { min: MOMENTS.treeNote, start: brk.la[1], end: tree.reply[0] },
    // 0:06:00 by "Added to today's notes."
    { min: MOMENTS.shiftNote, start: crew.sheetDown[0], end: shift.reply[0] },
    // 2:36 → 2:44: the rest of the break, ending as Back to work is tapped.
    { min: MOMENTS.backFromBreak - JUST_BEFORE / 60, start: shift.strip[1], end: round(back.end - 0.008 * k) },
    { min: MOMENTS.backFromBreak, start: round(back.end - 0.008 * k), end: back.end },
  ];

  return {
    mode,
    at,
    day,
    copy,
    break: brk,
    tree,
    crew,
    shift,
    back,
  };
}

function round(v: number) {
  return Math.round(v * 10000) / 10000;
}
