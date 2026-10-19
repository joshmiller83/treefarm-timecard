/**
 * SCENE REGISTRY. Each chapter's scene lives in src/scripts/scenes/<id>.ts and calls
 * registerScene(id, build, options). The motion core imports the file lazily when the
 * section comes within 1.5 viewports, then calls build(ctx) inside the active
 * gsap.matchMedia context ('desk' or 'mob'), so everything a scene makes is reverted
 * automatically when the breakpoint changes.
 *
 * This module is type-only plus a Map: importing it never pulls in GSAP.
 */
import type { gsap as GSAPObject } from 'gsap';
import type { ScrollTrigger as ST } from 'gsap/ScrollTrigger';
import type { SplitText as Split } from 'gsap/SplitText';
import type { ChapterId, TintKey } from '../data/chapters.ts';
import type { Minute } from '../data/ledger.ts';
import type { Day, DayClockRuntime } from './dayclock.ts';
import type { Stage } from './stage.ts';
import type { Util } from './util.ts';

export interface SceneContext {
  id: ChapterId;
  section: HTMLElement;
  /** Scrubbed timeline (start 'top top', end 'bottom bottom', scrub .6), normalized to duration 1. */
  tl: GSAPTimeline;
  /** The phone to move: the stage phone's [data-phone] on desktop, the section's own on mobile. */
  phone: HTMLElement | null;
  /** The section's [data-screens] container (the same nodes on desktop and mobile). */
  screens: HTMLElement | null;
  /** The section's .extras layer (aligned to --stage-* on desktop). */
  extras: HTMLElement | null;
  /** The sticky .frame. */
  frame: HTMLElement | null;
  /** The section's .beat elements, in order (beat 0 is the heading). */
  beats: HTMLElement[];
  /** Query inside the section and its (possibly moved) screens. */
  q: <T extends Element = HTMLElement>(selector: string) => T[];
  q1: <T extends Element = HTMLElement>(selector: string) => T | null;
  /** The shared DayClock: day.to(tl, minute, start, end, fromMinute?). */
  day: Day;
  /**
   * The DayClock runtime's real-time tick: wake() stops it and drops its seconds, idle()
   * starts the up-to-5-second tick (the hero starts the Live Activity's timer as it lands).
   */
  clock: Pick<DayClockRuntime, 'wake' | 'idle'>;
  /** True in the 'desk' context (stage phone in use). */
  isDesk: boolean;
  util: Util;
  gsap: typeof GSAPObject;
  ScrollTrigger: typeof ST;
  SplitText: typeof Split;
  /** The stage (desktop only). */
  stage: Stage | null;
  /** Make another ScrollTrigger owned by this scene (reverted with it). */
  trigger: (vars: ScrollTrigger.StaticVars) => ScrollTrigger;
  /** Switch the stage tint now (normally automatic per section). */
  tint: (key: TintKey) => void;
}

export interface SceneOptions {
  /** ScrollTrigger start for tl. Default 'top top' ('top 80%' for natural-height tracks). */
  start?: string;
  /** ScrollTrigger end for tl. Default 'bottom bottom' ('bottom 20%' for natural-height tracks). */
  end?: string;
  /** Default 0.6. */
  scrub?: number | boolean;
  /** Build in the desktop context. Default true. */
  desk?: boolean;
  /** Build in the mobile context. Default true. */
  mob?: boolean;
  /** The DayClock minute at progress 0 (day.to chains from here). Default: the chapter's minute. */
  dayStart?: Minute;
}

export type SceneBuild = (ctx: SceneContext) => void | (() => void);

interface Entry {
  build: SceneBuild;
  options: SceneOptions;
}

const registry = new Map<ChapterId, Entry>();

export function registerScene(id: ChapterId, build: SceneBuild, options: SceneOptions = {}): void {
  registry.set(id, { build, options });
}

export function getScene(id: ChapterId): Entry | undefined {
  return registry.get(id);
}
