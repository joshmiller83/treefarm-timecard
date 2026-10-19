/**
 * HERO SCENE · 7:02 AM · Clock in.
 *   jq '.sections[] | select(.id=="hero") | .animation, .mobile, .reducedMotion' docs/landing/brief.json
 *
 * 1) THE LOAD SEQUENCE (not scroll-linked, about 3 s, once per visit; never touches the H1).
 *    The dawn comes up from #050B08, the fir rows rise, the copy fades in, the phone rises
 *    with its screen dark, “Clock in with Time Card.” appears word by word, Siri's glow
 *    breathes, the screen wakes, Siri's card answers, then the Live Activity rises and its
 *    timer starts. Cues: INTRO in src/sections/hero/hero.ts (unit-tested). Mobile plays it at
 *    70%, and the phone's half waits until the phone is on screen, so it is seen, not missed.
 *    It is skipped (final state at once) when the page opens scrolled away, when Pause motion
 *    is on, or when the scene is rebuilt; Pause during the sequence ends it at once.
 *
 * 2) THE SCROLL SCENE (scrub .6, progress 0–1 of the 160vh desktop track; SCROLL in hero.ts):
 *    the spoken line lifts away, the copy lifts and fades, the fir rows sink (the near rows
 *    most: depth), the far rows thin into the haze, the stars fade with the morning, and the
 *    header's shift ribbon and '7:02 AM · Clock in' tag fade in. The day holds at 7:02.
 *    Mobile: a gentle parallax of the phone and the rows only (no sticky track).
 *
 * Two timelines touch the same parts at different depths, so they never fight:
 *   copy items ([data-intro], eyebrow) ← load       .beat-head (--hero-lift, opacity) ← scroll
 *   spoken words                       ← load       the spoken line ← scroll
 *   [data-band-art]                    ← load       [data-band] (y), [data-band-fade] (opacity) ← scroll
 *   [data-dawn] opacity                ← load       [data-dawn] --dawn-y (the sun climbs) ← scroll
 *   [data-phone]                       ← load       [data-hero-float] ← mobile parallax
 *
 * The section ends at rest (lock screen, clock and Live Activity) for the voice section.
 * html.hero-intro is on while part of the sequence is playing, and html[data-hero-intro] is
 * 'playing', 'waiting' (the mobile phone's half) or 'done'; 'tf:hero-intro' fires on each change.
 */
import { registerScene } from '../scene.ts';
import { PAUSE_EVENT } from '../header.ts';
import { MOMENTS } from '../../data/ledger.ts';
import { BANDS, INTRO, MOBILE_SCALE, SCROLL, cue, type Cue } from '../../sections/hero/hero.ts';

/** The sequence plays once per page view: a rebuilt scene (breakpoint change) shows the end state. */
let played = false;

/** The DayClock runtime's idle tick, if the motion core passes it to scenes (ctx.clock). */
interface ClockLike {
  wake(): void;
  idle(): void;
}

registerScene(
  'hero',
  (ctx) => {
    const { tl, day, gsap, section, q, q1, isDesk } = ctx;
    const root = document.documentElement;
    const scale = isDesk ? 1 : MOBILE_SCALE;
    const k = (c: Cue) => cue(c, scale);
    const clock = (ctx as unknown as { clock?: ClockLike }).clock;

    // The day holds at 7:02 through the hero.
    day.to(tl, MOMENTS.clockIn, 0, 1, MOMENTS.clockIn);

    // ---- Page parts ----
    const head = section.querySelector<HTMLElement>('.beat-head');
    const copy = [section.querySelector<HTMLElement>('.beat-head .eyebrow'), ...section.querySelectorAll<HTMLElement>('[data-intro]')].filter(
      (el): el is HTMLElement => !!el,
    );
    const said = section.querySelector<HTMLElement>(`[data-said="${isDesk ? 'stage' : 'figure'}"]`);
    const saidWords = said ? Array.from(said.querySelectorAll<HTMLElement>('[data-said-word]')) : [];
    const dark = section.querySelector<HTMLElement>('[data-hero-dark]');
    const stars = q('[data-star]');
    const bands = BANDS.map((spec) => {
      const el = section.querySelector<HTMLElement>(`[data-band="${spec.id}"]`);
      return { spec, el, fade: el?.querySelector<HTMLElement>('[data-band-fade]') ?? null, art: el?.querySelector<HTMLElement>('[data-band-art]') ?? null };
    });
    const arts = bands.map((b) => b.art).filter((el): el is HTMLElement => !!el);
    const device = section.querySelector<HTMLElement>('[data-hero-device]');
    const float = section.querySelector<HTMLElement>('[data-hero-float]');
    const phone = ctx.phone;
    const rim = phone?.querySelector<HTMLElement>('[data-rim]') ?? null;

    // ---- Screen parts (in the stage phone on desktop). A real capture has none of them. ----
    const layer = q1('[data-screen="lock-0702-clockin"]');
    const all = (sel: string) => (layer ? Array.from(layer.querySelectorAll<HTMLElement>(sel)) : []);
    const one = (sel: string) => all(sel)[0] ?? null;
    const dim = one('[data-dim]');
    const glow = one('[data-glow]');
    const snippet = one('[data-snippet]');
    const snipWords = all('[data-snippet] [data-word]');
    const lockChrome = all('[data-lock] > :is([data-date], [data-clock], [data-padlock])');
    const la = one('[data-la]');
    const laButtons = all('[data-la] :is([data-row], [data-break-btn])');
    const fieldbar = one('[data-fieldbar]');
    const fieldScale = fieldbar ? Number(/scaleX\(([\d.]+)\)/.exec(fieldbar.style.transform)?.[1] ?? 1) : 1;

    // ---- 1) The load sequence ----
    // fromTo renders its from-state at once, so everything waits hidden from the moment the
    // scene is built (the motion core lifts html.intro-wait right after).
    const ease = 'power3.out';

    // The page half: the dawn, the rows and the copy (plays at load).
    const pageTl = gsap.timeline({ paused: true, defaults: { ease } });
    if (dark) {
      gsap.set(dark, { transition: 'none' });
      const c = k(INTRO.tint);
      pageTl.fromTo(dark, { opacity: 1 }, { opacity: 0, duration: c.dur, ease: 'power1.inOut' }, c.at);
    }
    const dawn = section.querySelector<HTMLElement>('[data-dawn]');
    if (dawn) {
      // The sun comes up behind the far rows with the light.
      const c = k(INTRO.bands);
      pageTl.fromTo(dawn, { opacity: 0 }, { opacity: 1, duration: c.dur * 1.2, ease: 'power1.inOut' }, c.at);
    }
    if (arts.length) {
      const c = k(INTRO.bands);
      pageTl.fromTo(arts, { y: 24, opacity: 0 }, { y: 0, opacity: 1, duration: c.dur, stagger: c.stagger }, c.at);
    }
    if (copy.length) {
      const c = k(INTRO.copy);
      pageTl.fromTo(copy, { y: 16, opacity: 0 }, { y: 0, opacity: 1, duration: c.dur, stagger: c.stagger, ease: 'power2.out' }, c.at);
    }

    // The phone half, on the same clock (it can start late on mobile: see below).
    const phoneTl = gsap.timeline({ paused: true, defaults: { ease } });
    if (phone) {
      const c = k(INTRO.phone);
      phoneTl.fromTo(phone, { y: 40, opacity: 0 }, { y: 0, opacity: 1, duration: c.dur }, c.at);
    }
    if (saidWords.length) {
      const c = k(INTRO.words);
      phoneTl.fromTo(saidWords, { opacity: 0 }, { opacity: 1, duration: c.dur, stagger: c.stagger, ease: 'power1.out' }, c.at);
    }
    if (glow) {
      const c = k(INTRO.glow);
      const b = k(INTRO.breathe);
      phoneTl.fromTo(glow, { opacity: 0, scale: 1 }, { opacity: 1, duration: c.dur, ease: 'power1.out' }, c.at);
      phoneTl.to(glow, { scale: 1.02, duration: b.dur, ease: 'sine.inOut', yoyo: true, repeat: INTRO.breathe.repeat }, b.at);
    }
    if (dim) {
      const c = k(INTRO.wake);
      phoneTl.fromTo(dim, { opacity: 1 }, { opacity: 0, duration: c.dur, ease: 'power1.inOut' }, c.at);
    }
    {
      const c = k(INTRO.snippet);
      // The lock screen's date, clock and padlock show when the screen wakes, then give way to
      // Siri: quickly, so the clock never ghosts through the card as it lands.
      if (lockChrome.length) phoneTl.fromTo(lockChrome, { opacity: 1 }, { opacity: 0, duration: c.dur * 0.4, ease: 'power2.out' }, c.at - 0.04 * scale);
      if (snippet) phoneTl.fromTo(snippet, { opacity: 0, y: -16 }, { opacity: 1, y: 0, duration: c.dur }, c.at);
      // Siri's words appear as the card lands, quickly, one after another.
      if (snipWords.length) {
        const span = 0.34 * scale;
        phoneTl.fromTo(snipWords, { opacity: 0 }, { opacity: 1, duration: 0.12 * scale, stagger: span / snipWords.length, ease: 'none' }, c.at + c.dur * 0.2);
      }
    }
    {
      const c = k(INTRO.siriOut);
      const leave = [snippet, glow].filter((el): el is HTMLElement => !!el);
      if (leave.length) phoneTl.to(leave, { opacity: 0, duration: c.dur, ease: 'power1.in' }, c.at);
      if (snippet) phoneTl.to(snippet, { y: -10, duration: c.dur, ease: 'power1.in' }, c.at);
      if (lockChrome.length) phoneTl.to(lockChrome, { opacity: 1, duration: c.dur, ease: 'power1.out' }, c.at + c.dur * 0.3);
    }
    if (la) {
      const c = k(INTRO.activity);
      phoneTl.fromTo(la, { opacity: 0, y: 48, scale: 0.96 }, { opacity: 1, y: 0, scale: 1, duration: c.dur, transformOrigin: '50% 100%' }, c.at);
      // As the card lands, the dawn catches the phone's titanium edge for a moment.
      if (rim) {
        phoneTl.fromTo(rim, { opacity: 0 }, { opacity: 0.42, duration: c.dur * 0.45, ease: 'power2.out', immediateRender: false }, c.at);
        phoneTl.to(rim, { opacity: 0, duration: c.dur * 0.55, ease: 'power1.in' }, c.at + c.dur * 0.45);
      }
      // The timer starts ticking as the card lands (0:00:00, 0:00:01, …).
      phoneTl.call(() => clock?.idle(), undefined, c.at);
    }
    if (laButtons.length) {
      const c = k(INTRO.buttons);
      phoneTl.fromTo(laButtons, { opacity: 0, y: 8, scale: 0.92 }, { opacity: 1, y: 0, scale: 1, duration: c.dur, stagger: c.stagger, ease: 'back.out(1.6)' }, c.at);
    }
    if (fieldbar) {
      const c = k(INTRO.fieldbar);
      phoneTl.fromTo(fieldbar, { scaleX: 0 }, { scaleX: fieldScale, duration: c.dur, ease: 'power2.out' }, c.at);
    }

    // ---- When it plays ----
    // html.hero-intro is on while a half is actually playing (tests and screenshots wait for
    // it to go); data-hero-intro says where the sequence is: 'playing', 'waiting' (mobile:
    // the phone's half waits for the phone) or 'done'. 'tf:hero-intro' fires at each change.
    const halves = new Set<GSAPTimeline>();
    const state = (s: 'playing' | 'waiting' | 'done') => {
      root.dataset.heroIntro = s;
      root.classList.toggle('hero-intro', s === 'playing');
      window.dispatchEvent(new CustomEvent('tf:hero-intro', { detail: { state: s } }));
    };
    let waiting = false;
    const start = (half: GSAPTimeline, from = 0) => {
      halves.add(half);
      if (half === phoneTl) waiting = false;
      state('playing');
      half.play(from);
    };
    const ended = (half: GSAPTimeline) => {
      halves.delete(half);
      if (halves.size === 0) state(waiting ? 'waiting' : 'done');
    };
    pageTl.eventCallback('onComplete', () => ended(pageTl));
    phoneTl.eventCallback('onComplete', () => ended(phoneTl));
    let pendingPhone: ScrollTrigger | null = null;
    const finish = () => {
      waiting = false;
      pendingPhone?.kill();
      pendingPhone = null;
      if (pageTl.progress() < 1) pageTl.progress(1);
      if (phoneTl.progress() < 1) phoneTl.progress(1);
      halves.clear();
      state('done');
    };

    const vh = innerHeight;
    if (played || scrollY > vh * 0.5 || root.classList.contains('paused')) {
      finish();
    } else {
      played = true;
      clock?.wake();
      // On mobile the phone sits under the copy: its half plays when it comes into view.
      const r = device?.getBoundingClientRect();
      const later = !isDesk && !!r && r.top >= vh * 0.85;
      waiting = later;
      start(pageTl);
      if (!later) start(phoneTl);
      else
        pendingPhone = ctx.trigger({
          trigger: device!,
          start: 'top 85%',
          once: true,
          onEnter: () => {
            pendingPhone = null;
            if (phoneTl.progress() < 1) start(phoneTl, k(INTRO.phone).at);
          },
        });
    }

    // Pause motion ends the sequence at once.
    const onPause = (e: Event) => {
      if ((e as CustomEvent<{ paused: boolean }>).detail?.paused) finish();
    };
    addEventListener(PAUSE_EVENT, onPause);

    // ---- 2) The scroll scene ----
    if (isDesk) {
      if (said) {
        const [a, b] = SCROLL.said;
        tl.fromTo(said, { opacity: 1, y: 0 }, { opacity: 0, y: -20, duration: b - a, ease: 'power1.in' }, a);
      }
      if (head) {
        const [a, b] = SCROLL.copy;
        // Through a custom property: the shell centres beats with the CSS translate property,
        // which GSAP would fold into its own transform (and lose the -50%) if it tweened y here.
        tl.fromTo(head, { '--hero-lift': '0px', opacity: 1 }, { '--hero-lift': '-60px', opacity: 0, duration: b - a, ease: 'power1.in' }, a);
      }
      const [a, b] = SCROLL.bands;
      for (const band of bands) {
        if (band.el) tl.fromTo(band.el, { y: 0 }, { y: () => (innerHeight * band.spec.sink) / 100, duration: b - a }, a);
      }
      const far = bands.find((x) => x.spec.id === 'far')?.fade;
      if (far) tl.fromTo(far, { opacity: 0.6 }, { opacity: 0.3, duration: b - a }, a);
      if (stars.length) tl.fromTo(stars, { opacity: 0.35 }, { opacity: 0.1, duration: 0.8 }, 0);
      // The sun climbs behind the far rows as the stars go (a custom property: the glow is
      // centred with the CSS translate property, which a GSAP y tween would fold away).
      if (dawn) tl.fromTo(dawn, { '--dawn-y': '0px' }, { '--dawn-y': () => `${Math.round(-innerHeight * 0.06)}px`, duration: b - a }, a);
      // The shift ribbon starts with the shift: its fill and riding tag fade in.
      const [ra, rb] = SCROLL.ribbon;
      const ribbon = Array.from(document.querySelectorAll<HTMLElement>('nav.shift :is(.ribbon-fill, .tag-ride)'));
      if (ribbon.length) tl.fromTo(ribbon, { opacity: 0 }, { opacity: 1, duration: rb - ra }, ra);
    } else {
      // Mobile: the phone and the rows share a gentle parallax while the hero scrolls away.
      const para = gsap.timeline({
        defaults: { ease: 'none' },
        scrollTrigger: { trigger: section, start: 'top top', end: 'bottom top', scrub: 0.6, invalidateOnRefresh: true },
      });
      for (const band of bands) {
        if (band.el) para.fromTo(band.el, { y: 0 }, { y: () => (innerHeight * band.spec.sinkMob) / 100, duration: 1 }, 0);
      }
      if (float) para.fromTo(float, { y: 0 }, { y: () => innerHeight * 0.015, duration: 1 }, 0);
    }

    return () => {
      removeEventListener(PAUSE_EVENT, onPause);
      root.classList.remove('hero-intro');
      delete root.dataset.heroIntro;
    };
  },
  { dayStart: MOMENTS.clockIn },
);
