/**
 * MOTION CORE. Loaded on demand by main.ts only when html.motion is set, so visitors who
 * prefer reduced motion never download GSAP.
 *
 * - Registers ScrollTrigger and SplitText; one gsap.matchMedia with 'desk' and 'mob'.
 * - Per section: a chapter trigger (tint crossfade, DayClock chapter, stage claim) and a
 *   lazily built scene (imported and built when the section is within 1.5 viewports).
 * - DayClock ticker, scroll idle tick, Pause motion, focus-follows-beat, refresh on fonts and resize.
 */
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import { SplitText } from 'gsap/SplitText';
import { CHAPTERS, chapter, type ChapterId, type TintKey } from '../data/chapters.ts';
import { day, startDayClock, type DayTrack } from './dayclock.ts';
import { getScene, type SceneContext } from './scene.ts';
import { createStage, type Stage } from './stage.ts';
import { createUtil } from './util.ts';

gsap.registerPlugin(ScrollTrigger, SplitText);
ScrollTrigger.config({ ignoreMobileResize: true });

const DESK = '(min-width: 900px) and (min-height: 560px) and (prefers-reduced-motion: no-preference)';
const MOB = '(max-width: 899.98px) and (prefers-reduced-motion: no-preference)';
const IDLE_LOOPS_MS = 5000;
/**
 * The Pause motion toggle's event (header.ts dispatches it). Written here rather than imported:
 * importing header.ts made the dynamic import of this core preload the header's chunk again,
 * which Safari fetched twice. motion.test.ts keeps the two strings equal.
 */
const PAUSE_EVENT = 'tf:pause';

// Scene modules, one chunk each, loaded when their section comes near.
const sceneLoaders = import.meta.glob<unknown>('./scenes/*.ts');

declare global {
  interface Window {
    __tfGate?: number;
    __tf?: { day: typeof day; gsap: typeof gsap; ScrollTrigger: typeof ScrollTrigger; ready: Promise<void> };
  }
}

let booted = false;
/** True until the first scene batch of the page view has been scheduled. */
let firstLoad = true;

export function boot(): void {
  const root = document.documentElement;
  // The 4 s safety gate already fell back to the static page: stay static, never half-animated.
  if (booted || !root.classList.contains('motion')) return;
  booted = true;
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
  // While the reader scrolls, odometers jump instead of easing. The class goes on the chapter
  // in charge and the stage only (not on <html>): toggling it there restyled every
  // odometer on the page twice per scroll.
  let scrolling = false;
  ScrollTrigger.addEventListener('scrollStart', () => {
    scrolling = true;
    for (const el of [active, stage?.el]) el?.classList.add('scrubbing');
    clock.wake();
    clearTimeout(idleTimer);
    runAmbients(true);
  });
  ScrollTrigger.addEventListener('scrollEnd', () => {
    scrolling = false;
    document.querySelectorAll('.scrubbing').forEach((el) => el.classList.remove('scrubbing'));
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

  // The scenes start in their own task: the boot above (plugins, clock, chapter triggers) and
  // the stage plus the hero's build never share one long task on a slow phone.
  const startScenes = () => {
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
        // The section's non-final screen layers ship as <template data-layer> (Screen.astro):
        // put them in place now, wherever its screens are (the stage may hold them).
        const own = section.querySelector<HTMLElement>('[data-screens]') ?? document.querySelector<HTMLElement>(`[data-screens][data-section="${id}"]`);
        let placed = 0;
        for (const root of [section, own]) {
          for (const t of Array.from(root?.querySelectorAll<HTMLTemplateElement>('template[data-layer]') ?? [])) {
            t.replaceWith(t.content);
            placed += 1;
          }
        }
        // The clocks and timers in those layers join the DayClock if this chapter is in charge.
        if (placed && active === section) {
          clock.scope(stage && isDesk ? [stage.el, section] : [section]);
          clock.render(true);
        }
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
          stage: desk ? stage : null,
          trigger: (vars) => ScrollTrigger.create(vars),
          tint: setTint,
        };
        let cleanup: void | (() => void) = undefined;
        const t0 = performance.now();
        try {
          cleanup = sceneBuild(ctx);
        } catch (err) {
          console.warn(`[motion] scene ${id} failed to build`, err);
        }
        // In the performance timeline (DevTools, and the perf spec): how long each build took.
        performance.measure(`tf:scene:${id}`, { start: t0, end: performance.now() });
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

      // On the first load, a scene that is near but not yet on screen (the voice chapter under the
      // hero) waits until the hero's load sequence has played, the reader scrolls, or 4 s pass, and
      // then builds in its own idle task: the intro never shares a frame with a scene's build.
      let alive = true;
      const later: HTMLElement[] = [];
      let flushed = false;
      const idle = () =>
        new Promise<void>((r) => ('requestIdleCallback' in window ? requestIdleCallback(() => r(), { timeout: 250 }) : setTimeout(r, 16)));
      let resolveLater: () => void = () => {};
      const laterDone = new Promise<void>((r) => (resolveLater = r));
      const flush = () => {
        if (flushed) return;
        flushed = true;
        ScrollTrigger.removeEventListener('scrollStart', flush);
        removeEventListener('tf:hero-intro', onIntro);
        clearTimeout(laterTimer);
        void (async () => {
          for (const s of later) {
            await idle();
            if (!alive) return;
            await build(s);
          }
        })().finally(resolveLater);
      };
      const onIntro = (e: Event) => {
        if ((e as CustomEvent<{ state: string }>).detail?.state !== 'playing') flush();
      };
      let laterTimer = 0;

      const io = new IntersectionObserver(
        (entries) => {
          const jobs: Promise<void>[] = [];
          for (const e of entries) {
            if (!e.isIntersecting) continue;
            io.unobserve(e.target);
            const s = e.target as HTMLElement;
            const offscreen = s.id !== 'hero' && e.boundingClientRect.top >= innerHeight;
            if (firstBatch && firstLoad && offscreen) later.push(s);
            else jobs.push(build(s));
          }
          // `ready` resolves once the scenes near the first view are built (tests and screenshots wait on it).
          if (firstBatch) {
            firstBatch = false;
            if (later.length && !paused) {
              ScrollTrigger.addEventListener('scrollStart', flush);
              addEventListener('tf:hero-intro', onIntro);
              laterTimer = window.setTimeout(flush, 4000);
            } else flush();
            firstLoad = false;
            void Promise.all(jobs)
              .then(() => {
                // The hero's sequence may already be over (opened scrolled down, or paused).
                if (root.dataset.heroIntro !== 'playing') flush();
                return laterDone;
              })
              .then(() => resolveReady());
          }
        },
        { rootMargin: '150% 0px 150% 0px' },
      );
      sections.forEach((s) => io.observe(s));

      // ---- Pre-build: the rest of the page's scenes, one per idle period ----
      // Building a scene measures and styles a large subtree, which costs a long frame. Done
      // while the reader scrolls (the observer above) that frame is a visible stutter, so once
      // the first view is ready and the load is well over (or the reader first stops
      // scrolling), every remaining scene builds in its own idle callback, nearest first,
      // never during a scroll. The observer stays as the fallback for a reader who outruns it.
      const whenStill = () =>
        new Promise<void>((r) => {
          if (!scrolling) return r();
          const done = () => (ScrollTrigger.removeEventListener('scrollEnd', done), r());
          ScrollTrigger.addEventListener('scrollEnd', done);
        });
      const idleSlot = () =>
        new Promise<void>((r) => ('requestIdleCallback' in window ? requestIdleCallback(() => r(), { timeout: 2000 }) : setTimeout(r, 50)));
      const loaded = new Promise<void>((r) => (document.readyState === 'complete' ? r() : addEventListener('load', () => r(), { once: true })));
      void ready
        .then(() =>
          Promise.race([
            loaded.then(() => new Promise<void>((r) => setTimeout(r, 4000))),
            new Promise<void>((r) => {
              const go = () => (ScrollTrigger.removeEventListener('scrollEnd', go), r());
              ScrollTrigger.addEventListener('scrollEnd', go);
            }),
          ]),
        )
        .then(async () => {
          const mid = innerHeight / 2;
          const queue = sections
            .filter((s) => !built.has(s))
            .sort((a, b) => {
              const d = (el: HTMLElement) => {
                const r = el.getBoundingClientRect();
                return r.top > mid ? r.top - mid : r.bottom < mid ? mid - r.bottom : 0;
              };
              return d(a) - d(b);
            });
          for (const s of queue) {
            if (!alive) return;
            if (built.has(s)) continue;
            const loader = sceneLoaders[`./scenes/${s.id}.ts`];
            try {
              if (loader) await loader();
            } catch {
              /* build() reports it */
            }
            // An idle moment while the page is still (never mid-scroll).
            do {
              await whenStill();
              await idleSlot();
            } while (scrolling);
            if (!alive || built.has(s)) continue;
            io.unobserve(s);
            await build(s);
          }
        });

      // Re-claim the stage for whatever is active now.
      const now = sections.find((s) => {
        const r = s.getBoundingClientRect();
        return r.top <= innerHeight * 0.55 && r.bottom > innerHeight * 0.55;
      });
      if (now) activate(now);

      return () => {
        alive = false;
        flush();
        io.disconnect();
        stage?.destroy();
        stage = null;
      };
    });
  };
  if ('requestIdleCallback' in window) requestIdleCallback(startScenes, { timeout: 300 });
  else setTimeout(startScenes, 0);

  // ---- Reduced motion switched on mid-visit: become the static page ----
  // gsap.matchMedia reverts the scenes, but the DayClock has written its times into every
  // phone and the page's classes still say motion, so a half-moving page would be left. Reload
  // onto the chapter the reader was in: the inline gate then serves the static page there.
  const reduce = matchMedia('(prefers-reduced-motion: reduce)');
  reduce.addEventListener('change', () => {
    if (!reduce.matches) return;
    if (active?.id) history.replaceState(history.state, '', `#${active.id}`);
    location.reload();
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
