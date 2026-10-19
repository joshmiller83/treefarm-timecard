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
import { getScene, type SceneCleanup, type SceneContext, type SceneEntry } from './scene.ts';
import { createStage, type Stage } from './stage.ts';
import { createUtil } from './util.ts';
import { setOdometerInstant } from './odometer.ts';

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
  // While the reader scrolls, odometers jump instead of easing: a flag the columns read as
  // they move (odometer.ts). A class on a chapter restyled its whole subtree twice a scroll.
  let scrolling = false;
  ScrollTrigger.addEventListener('scrollStart', () => {
    scrolling = true;
    setOdometerInstant(true);
    clock.wake();
    clearTimeout(idleTimer);
    runAmbients(true);
  });
  ScrollTrigger.addEventListener('scrollEnd', () => {
    scrolling = false;
    setOdometerInstant(false);
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

  // ---- Off-stage screen layers skip style, layout and paint ----
  // A built chapter stacks every state of its phone as layers and its scene fades between
  // them. A layer nobody can see (opacity 0, or slid a whole screen away) gets
  // content-visibility: hidden, so the clocks and odometers written into it each frame cost
  // nothing, and it comes back (as it was) the frame it is needed. Checked every tick: a
  // few inline-style reads per layer, never a style or layout read.
  interface Watched {
    el: HTMLElement;
    off: boolean;
  }
  const layerSets = new Map<HTMLElement, Watched[]>();
  const layerShown = (el: HTMLElement) => {
    const o = el.style.opacity;
    const op = o === '' ? (el.hasAttribute('data-final') ? 1 : 0) : Number(o);
    if (!(op > 0.001)) return false;
    const c = (el as HTMLElement & { _gsap?: { xPercent?: number; yPercent?: number } })._gsap;
    return !c || (Math.abs(c.yPercent ?? 0) < 99.9 && Math.abs(c.xPercent ?? 0) < 99.9);
  };
  const syncLayers = () => {
    for (const list of layerSets.values()) {
      for (const w of list) {
        const off = !layerShown(w.el);
        if (off === w.off) continue;
        w.off = off;
        w.el.style.contentVisibility = off ? 'hidden' : '';
      }
    }
  };
  const watchLayers = (section: HTMLElement) => {
    const own = document.querySelector<HTMLElement>(`[data-screens][data-section="${section.id}"]`);
    const els = new Set<HTMLElement>();
    for (const r of [section, own]) r?.querySelectorAll<HTMLElement>('.screens > .layer').forEach((l) => els.add(l));
    layerSets.set(
      section,
      Array.from(els, (el) => ({ el, off: false })),
    );
    syncLayers();
  };
  const unwatchLayers = (section: HTMLElement) => {
    for (const w of layerSets.get(section) ?? []) w.el.style.removeProperty('content-visibility');
    layerSets.delete(section);
  };
  gsap.ticker.add(syncLayers);

  /** An idle moment for a scene's next part, cut short when `urgent()` turns true. */
  const idlePart = (urgent: () => boolean) =>
    new Promise<void>((resolve) => {
      let done = false;
      const go = () => {
        if (done) return;
        done = true;
        resolve();
      };
      if ('requestIdleCallback' in window) requestIdleCallback(go, { timeout: 400 });
      else setTimeout(go, 40);
      const poll = () => {
        if (done) return;
        if (urgent()) go();
        else requestAnimationFrame(poll);
      };
      requestAnimationFrame(poll);
    });

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

  // ---- The reader's place, kept across a breakpoint change ----
  // Crossing a breakpoint (an iPad turned to landscape) changes every track's height, while the
  // browser keeps the scroll offset in px: the reader would land chapters away. The place is
  // the chapter in charge and its progress, noted while the page scrolls (never in the half
  // second after a resize, when the old triggers meet the new layout); after the breakpoint's
  // scenes are in and ScrollTrigger has refreshed, the page scrolls back to it.
  let place: { section: HTMLElement; p: number } | null = null;
  let resizedAt = -1e9;
  let restore: { section: HTMLElement; p: number; until: number } | null = null;
  addEventListener('resize', () => (resizedAt = performance.now()), { passive: true });
  const notePlace = () => {
    if (!active || restore || performance.now() - resizedAt < 600) return;
    const st = trackTriggers.get(active);
    if (st) place = { section: active, p: Math.min(1, Math.max(0, st.progress)) };
  };
  ScrollTrigger.addEventListener('scrollEnd', notePlace);
  ScrollTrigger.addEventListener('refresh', () => {
    if (!restore) return notePlace();
    const { section, p, until } = restore;
    const st = trackTriggers.get(section);
    if (st) window.scrollTo(0, Math.round(st.start + p * (st.end - st.start)));
    // Scenes built at the new place can still move things a little: land again on the next
    // refresh, for up to 2 s after the change.
    if (performance.now() > until) restore = null;
  });

  /** A section's own moving phone: the one holding its [data-screens] (a static figure's
   *  phone may come first in the DOM, as the crew's no-signal phone does). */
  const sectionPhone = (section: HTMLElement | null) =>
    section?.querySelector<HTMLElement>('[data-screens]')?.closest<HTMLElement>('[data-phone]') ??
    section?.querySelector<HTMLElement>('[data-phone]') ??
    null;

  // ---- Scenes, per breakpoint ----
  const util = createUtil({ gsap, SplitText, phone: () => currentPhone(active), ambients });
  const currentPhone = (section: HTMLElement | null) =>
    stage && isDesk ? stage.phone : sectionPhone(section);

  let resolveReady: () => void = () => {};
  const ready = new Promise<void>((r) => (resolveReady = r));
  window.__tf = { day, gsap, ScrollTrigger, ready };

  // The scenes start in their own task: the boot above (plugins, clock, chapter triggers) and
  // the stage plus the hero's build never share one long task on a slow phone.
  const startScenes = () => {
    const mm = gsap.matchMedia();
    let runs = 0;
    mm.add({ desk: DESK, mob: MOB }, (context) => {
      const { desk } = context.conditions as { desk: boolean; mob: boolean };
      isDesk = desk;
      // A breakpoint change: go back to the reader's place once the new triggers are measured.
      if (runs++ && place) {
        restore = { ...place, until: performance.now() + 2000 };
        gsap.delayedCall(0.05, () => ScrollTrigger.refresh());
        gsap.delayedCall(2.1, () => (restore = null));
      }
      stage = desk ? createStage(gsap) : null;
      const built = new Set<HTMLElement>();
      let firstBatch = true;

      let alive = true;
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
        if (entry && alive && (desk ? entry.options.desk !== false : entry.options.mob !== false)) {
          await buildScene(section, entry.build, entry.options);
        }
        if (id === 'hero') root.classList.remove('intro-wait');
      };

      /**
       * Builds a section's scene inside this breakpoint's context, in parts: each of its
       * template layers is placed (and gets its first style and layout) on its own, then the
       * scene's build runs; a scene written as a generator yields between its beats, and each
       * beat is a part too. The first part runs now and each later one in its own idle callback,
       * so no build is one long task; all the rest run at once when the section comes within a
       * quarter of a viewport (it must be whole before it shows).
       */
      const buildScene = (section: HTMLElement, sceneBuild: SceneEntry['build'], options: SceneEntry['options']) =>
        new Promise<void>((resolve) => {
          const id = section.id as ChapterId;
          let tl: GSAPTimeline | null = null;
          let steps: Iterator<unknown, SceneCleanup> | null = null;
          let cleanup: SceneCleanup = undefined;
          let started = false;
          let finished = false;
          let part = 0;
          let busy = 0;
          let first = 0;
          const time = (fn: () => void) => {
            const t0 = performance.now();
            if (!first) first = t0;
            try {
              fn();
            } catch (err) {
              console.warn(`[motion] scene ${id} failed to build`, err);
              steps = null;
            }
            const t1 = performance.now();
            busy += t1 - t0;
            // In the performance timeline (DevTools, and the perf spec): each part's cost.
            performance.measure(`tf:chunk:${id}:${part++}`, { start: t0, end: t1 });
          };
          const finish = (watch = true) => {
            if (finished) return;
            finished = true;
            if (tl) {
              const tr = day.peek(tl);
              if (tr) {
                sectionTracks.set(section, tr);
                if (active === section) day.source = tr;
              }
              // Normalize to duration 1 so every spec reads in progress units.
              const d = tl.duration();
              if (d < 1) tl.to({}, { duration: 1 - d }, d);
              else if (d > 1.0001) console.warn(`[motion] scene ${id} runs past progress 1 (${d.toFixed(3)})`);
            }
            if (watch && started) watchLayers(section);
            performance.measure(`tf:scene:${id}`, { start: first || performance.now(), end: performance.now(), detail: { busy, parts: part } });
            resolve();
          };

          // The section's non-final screen layers ship as <template data-layer> (Screen.astro).
          const own = section.querySelector<HTMLElement>('[data-screens]') ?? document.querySelector<HTMLElement>(`[data-screens][data-section="${id}"]`);
          const templates = new Set<HTMLTemplateElement>();
          for (const r of [section, own]) r?.querySelectorAll<HTMLTemplateElement>('template[data-layer]').forEach((t) => templates.add(t));
          const queue: Array<() => void> = Array.from(templates, (t) => () => {
            if (!t.isConnected) return;
            const layer = t.content.firstElementChild as HTMLElement | null;
            t.replaceWith(t.content);
            // Its first style and layout happen here, in this part, not in the next frame.
            void layer?.offsetWidth;
          });

          /** The scene's first part: its timeline, its context, its build up to the first yield. */
          const startScene = () => {
            started = true;
            context.add(() => {
              time(() => {
                // The clocks and timers in the placed layers join the DayClock if this chapter is in charge.
                if (templates.size && active === section) {
                  clock.scope(stage && isDesk ? [stage.el, section] : [section]);
                  clock.render(true);
                }
                const track = section.querySelector<HTMLElement>('.track') ?? section;
                const natural = (desk ? section.dataset.desk : section.dataset.mob) === 'auto';
                tl = gsap.timeline({
                  defaults: { ease: 'none' },
                  scrollTrigger: {
                    trigger: track,
                    start: options.start ?? (natural ? 'top 80%' : 'top top'),
                    end: options.end ?? (natural ? 'bottom 20%' : 'bottom bottom'),
                    scrub: options.scrub ?? 0.6,
                    invalidateOnRefresh: options.invalidate !== false,
                  },
                });
                (tl as GSAPTimeline & { dayStart?: number }).dayStart = options.dayStart ?? chapter(id).minute;
                const screens = section.querySelector<HTMLElement>('[data-screens]') ?? (stage?.owner() === section ? stage.slot.querySelector<HTMLElement>('[data-screens]') : null);
                const roots = () => [section, ...(screens && !section.contains(screens) ? [screens] : [])];
                const ctx: SceneContext = {
                  id,
                  section,
                  tl,
                  phone: desk && stage ? stage.phone : sectionPhone(section),
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
                const r = sceneBuild(ctx);
                if (r && typeof (r as Iterator<unknown>).next === 'function') {
                  const it = r as Iterator<unknown, SceneCleanup>;
                  const head = it.next();
                  if (head.done) cleanup = head.value;
                  else steps = it;
                } else cleanup = r as SceneCleanup;
              });
              // The context calls this on revert (a breakpoint change), whatever part the build reached.
              return () => {
                steps = null;
                finish(false);
                unwatchLayers(section);
                cleanup?.();
              };
            });
          };
          /** The scene's next beat, inside this breakpoint's context (so the revert undoes it too). */
          const stepScene = () => {
            const it = steps;
            if (!it) return;
            context.add(() =>
              time(() => {
                const r = it.next();
                if (r.done) {
                  cleanup = r.value;
                  steps = null;
                }
              }),
            );
          };
          const more = () => queue.length > 0 || !started || !!steps;
          const next = () => {
            const job = queue.shift();
            if (job) time(job);
            else if (!started) startScene();
            else stepScene();
          };

          // On screen already (a jump, a deep link): the whole build now. Within a quarter of a
          // viewport: a part per frame. Further away: a part per idle callback.
          const box = section.getBoundingClientRect();
          const margin = innerHeight * 0.25;
          let seen = box.top < innerHeight && box.bottom > 0;
          let near = box.top < innerHeight + margin && box.bottom > -margin;
          if (seen) {
            while (more() && alive) next();
            return finish();
          }
          next();
          const nearIO = new IntersectionObserver((e) => (near = e.some((x) => x.isIntersecting)), { rootMargin: '25% 0px 25% 0px' });
          const seenIO = new IntersectionObserver((e) => (seen = e.some((x) => x.isIntersecting)));
          nearIO.observe(section);
          seenIO.observe(section);
          void (async () => {
            while (more() && alive) {
              if (near) await new Promise<void>((r) => requestAnimationFrame(() => r()));
              else await idlePart(() => near);
              if (!alive) break;
              if (seen) while (more() && alive) next();
              else next();
            }
            nearIO.disconnect();
            seenIO.disconnect();
            finish();
          })();
        });

      // On the first load, a scene that is near but not yet on screen (the voice chapter under the
      // hero) waits until the hero's load sequence has played, the reader scrolls, or 4 s pass, and
      // then builds in its own idle task: the intro never shares a frame with a scene's build.
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
  const toStatic = () => {
    if (active?.id) history.replaceState(history.state, '', `#${active.id}`);
    location.reload();
  };
  reduce.addEventListener('change', () => reduce.matches && toStatic());
  // A wide window made shorter than 560px matches neither breakpoint: its scenes revert, but the
  // page would keep its motion layout (beats placed for scenes that no longer run, drawn over
  // each other). The head gate serves the static page below 560px, so do as the reduced-motion
  // change does: reload onto the reader's chapter.
  const tooShort = matchMedia('(min-width: 900px) and (max-height: 559.98px)');
  tooShort.addEventListener('change', () => tooShort.matches && toStatic());

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
  // A refresh re-measures every trigger and re-renders the built scenes (a long task on a slow
  // phone), so it waits for the page to be still and the main thread idle: never mid-scroll,
  // and never more than 2 s late.
  let refreshTimer = 0;
  const refresh = () => {
    clearTimeout(refreshTimer);
    const deadline = performance.now() + 2000;
    const go = () => {
      if (scrolling && performance.now() < deadline) {
        refreshTimer = window.setTimeout(go, 200);
        return;
      }
      if ('requestIdleCallback' in window) requestIdleCallback(() => ScrollTrigger.refresh(), { timeout: 500 });
      else ScrollTrigger.refresh();
    };
    refreshTimer = window.setTimeout(go, 150);
  };
  void document.fonts?.ready.then(refresh);
  const main = document.querySelector('main');
  if (main) new ResizeObserver(refresh).observe(main);

  clock.render(true);
  // The hero's timer ticks for a few seconds after load, then rests.
  clock.idle();
}
