/**
 * DAYCLOCK: one shared minute drives every clock on the page.
 *
 * `day.min` (minutes after midnight, 422 = 7:02 AM) is tweened by each section's
 * scrubbed timeline. A ticker renders it only when it changes, into:
 *   (a) status-bar clocks          [data-clock]          "2:14"
 *   (b) Live Activity timers       [data-timer]          "6:27:00" (odometer if it has [data-odo])
 *   (c) the shift ribbon and tag   nav.shift             --p, .shift-tag text
 *   (d) the header DayMark         [data-daymark]        hand rotation, ring arc
 * Scrolling back rewinds the day. After scrolling stops, timers tick in real time for
 * up to 5 seconds, then rest. Pause motion stops that ticking at once.
 *
 * The math at the top is pure and unit-tested. The runtime at the bottom takes gsap as
 * an argument, so importing this module never pulls GSAP into the first-load bundle.
 */
import { CHAPTERS, type ChapterId } from '../data/chapters.ts';
import { breakAt, fmtClock, fmtHMS, fmtTime, SHIFT, workedAt, type Minute } from '../data/ledger.ts';
import { setOdometer } from './odometer.ts';
import { setText } from './text.ts';

export const DAY_START = SHIFT.in; // 7:02 AM
export const DAY_END = SHIFT.out; // 4:31 PM

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));

// ---------------------------------------------------------------------------
// Pure math

/** Hand angle on a 12-hour dial, in degrees clockwise from 12. Continuous: 7:02 = 211, noon = 360, 4:31 = 495.5. */
export const dialAngle = (min: Minute): number => min / 2;

/** How much of the DayMark's gold ring is filled: from 7:00 AM (0) around the 12-hour dial. */
export const ringFraction = (min: Minute): number => clamp((min - 420) / 720, 0, 1);

/** Ribbon position of chapter tick `i` (0–1). The nine ticks are evenly spaced. */
export const tickPct = (i: number): number => i / (CHAPTERS.length - 1);

const STOPS = CHAPTERS.filter((c) => c.id !== 'open').map((c) => c.minute);

/**
 * Ribbon fill (0–1). Piecewise linear: each timed chapter's minute lands exactly on its
 * tick, so the fill reaches a tick when that chapter's moment arrives. The last segment
 * (clock-out → end of shift) is filled by `done` (0–1), which the clock-out scene tweens.
 */
export function ribbonPct(min: Minute, done = 0): number {
  const n = CHAPTERS.length - 1;
  let p = 0;
  if (min >= STOPS[STOPS.length - 1]!) p = (STOPS.length - 1) / n;
  else {
    for (let i = 0; i < STOPS.length - 1; i += 1) {
      const a = STOPS[i]!;
      const b = STOPS[i + 1]!;
      if (min < b) {
        p = (i + clamp((min - a) / Math.max(b - a, 1e-9), 0, 1)) / n;
        break;
      }
    }
  }
  return clamp(p + clamp(done, 0, 1) / n, 0, 1);
}

/** "2:14 PM · Lock screen" — the time from the DayClock, the words from the active chapter. */
export function ribbonTag(min: Minute, chapter: ChapterId, done = 0): string {
  const c = CHAPTERS.find((x) => x.id === chapter) ?? CHAPTERS[0]!;
  if (c.id === 'open' || done >= 1) return 'End of shift';
  return `${fmtTime(min)} · ${c.tagLabel}`;
}

export type TimerMode = 'auto' | 'worked' | 'break';
export interface TimerReading {
  kind: 'worked' | 'lunch' | 'break';
  seconds: number;
  text: string;
}

/**
 * What a Live Activity timer reads at `min`. 'auto' shows the break timer on a break or
 * lunch and worked time otherwise. `idle` adds real-time seconds after scrolling stops.
 */
export function timerAt(min: Minute, mode: TimerMode = 'auto', idle = 0): TimerReading {
  const brk = breakAt(min);
  if (mode === 'break' || (mode === 'auto' && brk)) {
    const seconds = (brk?.seconds ?? 0) + idle;
    return { kind: brk?.kind ?? 'break', seconds, text: fmtHMS(seconds) };
  }
  const seconds = workedAt(min) + (brk ? 0 : idle);
  return { kind: 'worked', seconds, text: fmtHMS(seconds) };
}

export interface DayState {
  min: Minute;
  /** 0–1: the ribbon's last segment after clock-out. */
  done: number;
  chapter: ChapterId;
  /** Real-time seconds added after scrolling stops (0–5). */
  idle: number;
}

/** Everything the page shows for one DayClock state. */
export function readout(s: DayState) {
  const now = s.min + s.idle / 60;
  return {
    clock: fmtClock(now),
    tag: ribbonTag(s.min, s.chapter, s.done),
    ribbon: ribbonPct(s.min, s.done),
    angle: dialAngle(now),
    ring: ringFraction(now),
    timer: timerAt(s.min, 'auto', s.idle),
  };
}

// ---------------------------------------------------------------------------
// The shared day object

/** The parts of a GSAP timeline the day object uses (kept minimal for tests). */
export interface TimelineLike {
  fromTo(target: object, from: object, to: object, position?: number): unknown;
}

/** One section's own copy of the day. Only the active section's track drives the page. */
export interface DayTrack {
  min: Minute;
  done: number;
}

export interface Day extends DayState {
  /**
   * The track that drives the page now (the active section's). Each scene tweens its own
   * track, so a scene that is built or rewound off-screen never moves the visible clock.
   */
  source: DayTrack | null;
  /**
   * Tween the day to `minute` between progress `start` and `end` of a section timeline
   * (ease 'none'). `fromMinute` defaults to where the previous day tween on the same
   * timeline ended, or the section's start minute set by the motion core.
   */
  to(tl: TimelineLike, minute: Minute, start: number, end: number, fromMinute?: Minute): void;
  /** Tween the ribbon's last segment (clock-out to end of shift) between `start` and `end`. */
  complete(tl: TimelineLike, start: number, end: number): void;
  /** The track a timeline's day tweens write to (created on first use). */
  track(tl: TimelineLike): DayTrack;
  /** The track for a timeline if it has day tweens. */
  peek(tl: TimelineLike): DayTrack | undefined;
  /** The minute, done fraction the page shows now. */
  now(): DayTrack;
}

export function createDay(initial: Partial<DayState> = {}): Day {
  const tracks = new WeakMap<object, DayTrack>();
  const last = new WeakMap<object, Minute>();
  const day: Day = {
    min: DAY_START,
    done: 0,
    chapter: 'hero',
    idle: 0,
    ...initial,
    source: null,
    track(tl) {
      let tr = tracks.get(tl);
      if (!tr) {
        const start = (tl as { dayStart?: number }).dayStart ?? day.min;
        tr = { min: start, done: 0 };
        tracks.set(tl, tr);
      }
      return tr;
    },
    peek: (tl) => tracks.get(tl),
    to(tl, minute, start, end, fromMinute) {
      const fresh = !tracks.has(tl);
      const tr = day.track(tl);
      const from = fromMinute ?? last.get(tl) ?? tr.min;
      if (fresh) tr.min = from;
      tl.fromTo(tr, { min: from }, { min: minute, duration: Math.max(end - start, 1e-4), ease: 'none', immediateRender: false }, start);
      last.set(tl, minute);
    },
    complete(tl, start, end) {
      const tr = day.track(tl);
      tl.fromTo(tr, { done: 0 }, { done: 1, duration: Math.max(end - start, 1e-4), ease: 'none', immediateRender: false }, start);
    },
    now: () => day.source ?? day,
  };
  return day;
}

/** The one day every scene shares. */
export const day = createDay();

// ---------------------------------------------------------------------------
// Runtime (browser only; motion.ts passes gsap in)

interface Ticker {
  add(fn: () => void): void;
  remove(fn: () => void): void;
}

export interface DayClockRuntime {
  /** Render now if anything changed (or always with force). */
  render(force?: boolean): void;
  /** Restrict live [data-clock]/[data-timer] updates to these roots (the stage and the active section). */
  scope(roots: Element[]): void;
  /** Start the up-to-5-second real-time tick (call when scrolling stops, or after the hero's load sequence). */
  idle(): void;
  /** Stop the real-time tick and drop its seconds (call on scroll). */
  wake(): void;
  pause(paused: boolean): void;
  destroy(): void;
}

const IDLE_LIMIT = 5;

export function startDayClock(ticker: Ticker, doc: Document = document): DayClockRuntime {
  const root = doc.documentElement;
  const nav = doc.querySelector<HTMLElement>('nav.shift');
  const tagEls = Array.from(doc.querySelectorAll<HTMLElement>('[data-shift-tag]'));
  const marks = Array.from(doc.querySelectorAll<SVGElement>('[data-daymark]'));
  let clocks: HTMLElement[] = [];
  let timers: HTMLElement[] = [];
  let prev = '';
  let paused = root.classList.contains('paused');
  let idleStart = 0;
  let idling = false;

  const scope = (roots: Element[]) => {
    const pick = (sel: string) => roots.flatMap((r) => Array.from(r.querySelectorAll<HTMLElement>(sel)));
    clocks = pick('[data-clock]:not([data-clock="fixed"])');
    timers = pick('[data-timer]:not([data-timer="fixed"])');
    prev = '';
  };

  const render = (force = false) => {
    if (idling && !paused) {
      day.idle = Math.min(IDLE_LIMIT, (performance.now() - idleStart) / 1000);
      if (day.idle >= IDLE_LIMIT) idling = false;
    }
    const src = day.now();
    const key = `${src.min.toFixed(4)}|${src.done.toFixed(4)}|${day.chapter}|${Math.floor(day.idle)}`;
    if (!force && key === prev) return;
    prev = key;
    const state = { min: src.min, done: src.done, chapter: day.chapter, idle: day.idle };
    const r = readout(state);
    for (const el of clocks) setText(el, r.clock);
    for (const el of timers) {
      const mode = (el.dataset.timer || 'auto') as TimerMode;
      const text = timerAt(state.min, mode, state.idle).text;
      if (el.hasAttribute('data-odo')) setOdometer(el, text);
      else setText(el, text);
    }
    if (nav) nav.style.setProperty('--p', r.ribbon.toFixed(5));
    for (const el of tagEls) setText(el, r.tag);
    for (const m of marks) {
      m.style.setProperty('--angle', `${r.angle}deg`);
      m.style.setProperty('--ring', r.ring.toFixed(4));
    }
  };

  const tick = () => render();
  ticker.add(tick);
  scope([doc.body]);

  return {
    render,
    scope,
    idle() {
      if (paused) return;
      idleStart = performance.now() - day.idle * 1000;
      idling = true;
    },
    wake() {
      idling = false;
      if (day.idle !== 0) {
        day.idle = 0;
        render(true);
      }
    },
    pause(p) {
      paused = p;
      if (p) idling = false;
    },
    destroy() {
      ticker.remove(tick);
    },
  };
}
