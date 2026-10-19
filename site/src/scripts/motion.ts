/**
 * MOTION CORE. Loaded on demand by main.ts only when html.motion is set, so visitors who
 * prefer reduced motion never download GSAP.
 *
 * - Registers ScrollTrigger, SplitText and Flip; one gsap.matchMedia with 'desk' and 'mob'.
 * - Per section: a chapter trigger (tint crossfade, DayClock chapter, stage claim) and a
 *   lazily built scene (imported and built when the section is within 1.5 viewports).
 * - DayClock ticker, scroll idle tick, Pause motion, focus-follows-beat, refresh on fonts and resize.
 */
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { SplitText } from 'gsap/SplitText';
import { Flip } from 'gsap/Flip';
import { CHAPTERS, chapter, type ChapterId, type TintKey } from '../data/chapters.ts';
import { day, startDayClock, type DayTrack } from './dayclock.ts';
import { PAUSE_EVENT } from './header.ts';
import { getScene, type SceneContext } from './scene.ts';
import { createStage, type Stage } from './stage.ts';
import { createUtil } from './util.ts';

gsap.registerPlugin(ScrollTrigger, SplitText, Flip);
ScrollTrigger.config({ ignoreMobileResize: true });

const DESK = '(min-width: 900px) and (min-height: 560px) and (prefers-reduced-motion: no-preference)';
const MOB = '(max-width: 899.98px) and (prefers-reduced-motion: no-preference)';
const IDLE_LOOPS_MS = 5000;

// Scene modules, one chunk each, loaded when their section comes near.
const sceneLoaders = import.meta.glob<unknown>('./scenes/*.ts');

declare global {
  interface Window {
    __tfGate?: number;
    __tf?: { day: typeof day; gsap: typeof gsap; ScrollTrigger: typeof ScrollTrigger; ready: Promise<void> };
  }
}

let booted = false;

export function boot(): void {
  if (booted) return;
  booted = true;
  const root = document.documentElement;
  root.classList.add('motion-ready');
  if (window.__tfGate) clearTimeout(window.__tfGate);

  const sections = CHAPTERS.map((c) => document.getElementById(c.id)).filter((s): s is HTMLElement => !!s);
  const clock = startDayClock(gsap.ticker);
  const ambients = new Set<GSAPTween | GSAPTimeline>();
  let paused = root.classList.contains('paused');
  let stage: Stage | null = null;
  let isDesk = false;
  let active: HTMLElement | null = null;
  const sectionTracks = new Map<HTMLElement, DayTrack>();

  // ---- Tints: two fixed layers, crossfaded by opacity ----
  const tints = Array.from(document.querySelectorAll<HTMLElement>('.tints .tint'));
  let tintOn = 0;
  const setTint = (key: TintKey) => {
    const cur = tints[tintOn];
    if (!cur || cur.dataset.tint === key && cur.classList.contains('is-on')) return;
    const nextIdx = (tintOn + 1) % tints.length;
    const next = tints[nextIdx]!;
    next.dataset.tint = key;
    next.classList.add('is-on');
    cur.classList.remove('is-on');
    tintOn = nextIdx;
  };

  // ---- Ambient loops: only while scrolling + 5 s, never while paused ----
  let idleTimer = 0;
  const runAmbients = (run: boolean) => ambients.forEach((a) => (run && !paused ? a.resume() : a.pause()));
  ScrollTrigger.addEventListener('scrollStart', () => {
    root.classList.add('scrubbing');
    clock.wake();
    clearTimeout(idleTimer);
    runAmbients(true);
  });
  ScrollTrigger.addEventListener('scrollEnd', () => {
    root.classList.remove('scrubbing');
    clock.idle();
    clearTimeout(idleTimer);
    idleTimer = window.setTimeout(() => runAmbients(false), IDLE_LOOPS_MS);
  });
  addEventListener(PAUSE_EVENT, ((e: CustomEvent<{ paused: boolean }>) => {
    paused = e.detail.paused;
    clock.pause(paused);
    if (paused) clock.wake();
    runAmbients(!paused);
  }) as EventListener);

  // ---- Chapters: which section is in charge of the day ----
  const activate = (section: HTMLElement) => {
    active = section;
    const id = section.id as ChapterId;
    day.chapter = id;
    const tr = sectionTracks.get(section);
    if (tr) day.source = tr;
    setTint((section.dataset.tint as TintKey) ?? chapter(id).tint);
    if (stage && isDesk) {
      stage.claim(section);
      const off = section.dataset.stageMode === 'off';
      gsap.to(stage.el, { autoAlpha: off ? 0 : 1, duration: 0.4, ease: 'power1.out', overwrite: 'auto' });
    }
    clock.scope(stage && isDesk ? [stage.el, section] : [section]);
    clock.render(true);
  };
  const trackTriggers = new Map<HTMLElement, ScrollTrigger>();
  for (const section of sections) {
    ScrollTrigger.create({
      trigger: section,
      start: 'top 55%',
      end: 'bottom 55%',
      onToggle: (self) => self.isActive && activate(section),
    });
    const track = section.querySelector<HTMLElement>('.track') ?? section;
    trackTriggers.set(section, ScrollTrigger.create({ trigger: track, start: 'top top', end: 'bottom bottom' }));
  }

  // ---- Scenes, per breakpoint ----
  const util = createUtil({ gsap, SplitText, phone: () => currentPhone(active), ambients });
  const currentPhone = (section: HTMLElement | null) =>
    stage && isDesk ? stage.phone : (section?.querySelector<HTMLElement>('[data-phone]') ?? null);

  let resolveReady: () => void = () => {};
  const ready = new Promise<void>((r) => (resolveReady = r));
  window.__tf = { day, gsap, ScrollTrigger, ready };

  const mm = gsap.matchMedia();
  mm.add({ desk: DESK, mob: MOB }, (context) => {
    const { desk } = context.conditions as { desk: boolean; mob: boolean };
    isDesk = desk;
    stage = desk ? createStage(gsap) : null;
    const built = new Set<HTMLElement>();
    let firstBatch = true;

    const build = async (section: HTMLElement) => {
      if (built.has(section)) return;
      built.add(section);
      const id = section.id as ChapterId;
      const loader = sceneLoaders[`./scenes/${id}.ts`];
      try {
        if (loader) await loader();
      } catch (err) {
        console.warn(`[motion] scene ${id} failed to load`, err);
      }
      const entry = getScene(id);
      if (entry && (desk ? entry.options.desk !== false : entry.options.mob !== false)) {
        context.add(() => buildScene(section, entry.build, entry.options));
      }
      if (id === 'hero') root.classList.remove('intro-wait');
    };

    const buildScene = (section: HTMLElement, sceneBuild: NonNullable<ReturnType<typeof getScene>>['build'], options: NonNullable<ReturnType<typeof getScene>>['options']) => {
      const id = section.id as ChapterId;
      const track = section.querySelector<HTMLElement>('.track') ?? section;
      const natural = (desk ? section.dataset.desk : section.dataset.mob) === 'auto';
      const tl = gsap.timeline({
        defaults: { ease: 'none' },
        scrollTrigger: {
          trigger: track,
          start: options.start ?? (natural ? 'top 80%' : 'top top'),
          end: options.end ?? (natural ? 'bottom 20%' : 'bottom bottom'),
          scrub: options.scrub ?? 0.6,
          invalidateOnRefresh: true,
        },
      });
      (tl as GSAPTimeline & { dayStart?: number }).dayStart = options.dayStart ?? chapter(id).minute;
      const screens = section.querySelector<HTMLElement>('[data-screens]') ?? (stage?.owner() === section ? stage.slot.querySelector<HTMLElement>('[data-screens]') : null);
      const roots = () => [section, ...(screens && !section.contains(screens) ? [screens] : [])];
      const ctx: SceneContext = {
        id,
        section,
        tl,
        phone: desk && stage ? stage.phone : section.querySelector<HTMLElement>('[data-phone]'),
        screens,
        extras: section.querySelector<HTMLElement>('.extras'),
        frame: section.querySelector<HTMLElement>('.frame'),
        beats: Array.from(section.querySelectorAll<HTMLElement>('.beat')),
        q: <T extends Element = HTMLElement>(sel: string) => roots().flatMap((r) => Array.from(r.querySelectorAll<T>(sel))),
        q1: <T extends Element = HTMLElement>(sel: string) => {
          for (const r of roots()) {
            const hit = r.querySelector<T>(sel);
            if (hit) return hit;
          }
          return null;
        },
        day,
        clock,
        isDesk: desk,
        util,
        gsap,
        ScrollTrigger,
        SplitText,
        Flip,
        stage: desk ? stage : null,
        trigger: (vars) => ScrollTrigger.create(vars),
        tint: setTint,
      };
      let cleanup: void | (() => void) = undefined;
      try {
        cleanup = sceneBuild(ctx);
      } catch (err) {
        console.warn(`[motion] scene ${id} failed to build`, err);
      }
      const tr = day.peek(tl);
      if (tr) {
        sectionTracks.set(section, tr);
        if (active === section) day.source = tr;
      }
      // Normalize to duration 1 so every spec reads in progress units.
      const d = tl.duration();
      if (d < 1) tl.to({}, { duration: 1 - d }, d);
      else if (d > 1.0001) console.warn(`[motion] scene ${id} runs past progress 1 (${d.toFixed(3)})`);
      return cleanup || undefined;
    };

    const io = new IntersectionObserver(
      (entries) => {
        const jobs: Promise<void>[] = [];
        for (const e of entries) {
          if (!e.isIntersecting) continue;
          io.unobserve(e.target);
          jobs.push(build(e.target as HTMLElement));
        }
        // `ready` resolves once the scenes near the first view are built (tests and screenshots wait on it).
        if (firstBatch) {
          firstBatch = false;
          void Promise.all(jobs).then(() => resolveReady());
        }
      },
      { rootMargin: '150% 0px 150% 0px' },
    );
    sections.forEach((s) => io.observe(s));

    // Re-claim the stage for whatever is active now.
    const now = sections.find((s) => {
      const r = s.getBoundingClientRect();
      return r.top <= innerHeight * 0.55 && r.bottom > innerHeight * 0.55;
    });
    if (now) activate(now);

    return () => {
      io.disconnect();
      stage?.destroy();
      stage = null;
    };
  });

  // Hero's intro hold never outlives a failed or slow scene.
  window.setTimeout(() => root.classList.remove('intro-wait'), 1500);

  // ---- Keyboard: a focused element's beat scrolls into view ----
  document.addEventListener('focusin', (e) => {
    const target = e.target as HTMLElement;
    const beat = target.closest<HTMLElement>('.beat');
    const section = target.closest<HTMLElement>('section.sec');
    if (!beat || !section) return;
    const r = beat.getBoundingClientRect();
    const top = parseFloat(getComputedStyle(root).getPropertyValue('--chrome-h')) || 59;
    if (r.top >= top && r.bottom <= innerHeight) return;
    const st = trackTriggers.get(section);
    const at = parseFloat(beat.style.getPropertyValue('--at'));
    if (st && Number.isFinite(at) && st.end > st.start && getComputedStyle(beat).position === 'absolute') {
      window.scrollTo({ top: st.start + at * (st.end - st.start), behavior: 'auto' });
    } else {
      beat.scrollIntoView({ block: 'center', behavior: 'auto' });
    }
  });

  // ---- Refresh after fonts and on layout changes ----
  let refreshTimer = 0;
  const refresh = () => {
    clearTimeout(refreshTimer);
    refreshTimer = window.setTimeout(() => ScrollTrigger.refresh(), 150);
  };
  void document.fonts?.ready.then(refresh);
  const main = document.querySelector('main');
  if (main) new ResizeObserver(refresh).observe(main);

  clock.render(true);
  // The hero's timer ticks for a few seconds after load, then rests.
  clock.idle();
}
