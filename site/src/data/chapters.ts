/**
 * The nine chapters of the page, in order. The header ribbon, the chapter links,
 * the DayClock and SectionShell all read from here.
 */
import { MOMENTS, type Minute } from './ledger.ts';

export type ChapterId = 'hero' | 'voice' | 'lock-screen' | 'field' | 'notes' | 'crew' | 'pace' | 'clock-out' | 'open';

export type TintKey = 'dawn' | 'morning' | 'focus' | 'field' | 'afternoon' | 'pace' | 'dusk' | 'lights-up';

export interface Track {
  /** Track height at ≥900px under motion, e.g. '260vh'. 'auto' means natural height (no sticky frame). */
  desk: string;
  /** Track height below 900px under motion. */
  mob: string;
}

export interface Chapter {
  id: ChapterId;
  /** Short link text in the ribbon's chapter list. */
  navLabel: string;
  /** The ribbon tag at rest when the chapter starts. */
  ribbonTag: string;
  /** The words after the time in the ribbon tag. */
  tagLabel: string;
  /** DayClock minute where the chapter's tick sits. */
  minute: Minute;
  eyebrow: string;
  headline: string;
  tint: TintKey;
  track: Track;
  theme: 'dark' | 'light';
  /** 'off' hides the desktop stage phone while this chapter is active. Default 'on'. */
  stage?: 'on' | 'off';
}

export const CHAPTERS: readonly Chapter[] = [
  {
    id: 'hero',
    navLabel: '7:02 Clock in',
    ribbonTag: '7:02 AM · Clock in',
    tagLabel: 'Clock in',
    minute: MOMENTS.clockIn,
    eyebrow: 'Time Card · For Christmas tree trimmers',
    headline: 'Keep your gloves on.',
    tint: 'dawn',
    track: { desk: '160vh', mob: 'auto' },
    theme: 'dark',
  },
  {
    id: 'voice',
    navLabel: 'Say it',
    ribbonTag: '7:18 AM · Say it',
    tagLabel: 'Say it',
    minute: MOMENTS.misheard,
    eyebrow: '7:18 AM · Voice first',
    headline: 'Say it. Keep cutting.',
    tint: 'morning',
    track: { desk: '340vh', mob: '520vh' },
    theme: 'dark',
  },
  {
    id: 'lock-screen',
    navLabel: 'Lock screen',
    ribbonTag: '2:14 PM · Lock screen',
    tagLabel: 'Lock screen',
    minute: MOMENTS.lockScreen,
    eyebrow: '2:14 PM · Lock screen',
    headline: 'Your time card, right on the lock screen.',
    tint: 'focus',
    track: { desk: '260vh', mob: '320vh' },
    theme: 'dark',
  },
  {
    id: 'field',
    navLabel: 'The field',
    ribbonTag: '2:15 PM · The field',
    tagLabel: 'The field',
    minute: MOMENTS.field,
    eyebrow: '2:15 PM · The trees map',
    headline: 'Every tree is a dot.',
    tint: 'field',
    track: { desk: '300vh', mob: '240vh' },
    theme: 'dark',
  },
  {
    id: 'notes',
    navLabel: 'Notes',
    ribbonTag: '2:30 PM · Break',
    tagLabel: 'Break',
    minute: MOMENTS.break,
    eyebrow: '2:30 PM · On a break',
    headline: 'Say what you see.',
    tint: 'afternoon',
    track: { desk: '240vh', mob: '300vh' },
    theme: 'dark',
  },
  {
    id: 'crew',
    navLabel: 'The crew',
    ribbonTag: '2:47 PM · The crew',
    tagLabel: 'The crew',
    minute: MOMENTS.crew,
    eyebrow: '2:47 PM · Block 3',
    headline: 'One map for the whole crew.',
    tint: 'afternoon',
    track: { desk: '280vh', mob: '340vh' },
    theme: 'dark',
  },
  {
    id: 'pace',
    navLabel: 'Pace',
    ribbonTag: '3:40 PM · Pace',
    tagLabel: 'Pace',
    minute: MOMENTS.pace,
    eyebrow: '3:40 PM · The Clock tab',
    headline: 'Know your pace.',
    tint: 'pace',
    track: { desk: '220vh', mob: '260vh' },
    theme: 'dark',
  },
  {
    id: 'clock-out',
    navLabel: '4:31 Clock out',
    ribbonTag: '4:31 PM · Clock out',
    tagLabel: 'Clock out',
    minute: MOMENTS.clockOut,
    eyebrow: '4:31 PM · Clock out',
    headline: 'Clocking out takes a yes.',
    tint: 'dusk',
    track: { desk: '320vh', mob: '360vh' },
    theme: 'dark',
  },
  {
    id: 'open',
    navLabel: 'Built in the open',
    ribbonTag: 'End of shift',
    tagLabel: 'End of shift',
    minute: MOMENTS.clockOut,
    eyebrow: 'The story so far',
    headline: 'Built on a working tree farm. Out in the open.',
    tint: 'lights-up',
    track: { desk: 'auto', mob: 'auto' },
    theme: 'light',
    stage: 'off',
  },
];

export const CHAPTER_IDS = CHAPTERS.map((c) => c.id);

export function chapter(id: ChapterId): Chapter {
  const c = CHAPTERS.find((x) => x.id === id);
  if (!c) throw new Error(`Unknown chapter ${id}`);
  return c;
}

/** Converts a chapter id to its section file name: 'clock-out' → 'ClockOut'. */
export const pascal = (id: string) => id.replace(/(^|-)(\w)/g, (_, __, ch: string) => ch.toUpperCase());
