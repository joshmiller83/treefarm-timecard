# Shared component contract

Every shared component: where it lives, its `Props`, the `data-*` hooks scenes animate,
and how a real simulator capture replaces it. All of them are built (no stubs left) and
merged on branch `site`; each has a workbench at `/lab/<team>/` with a Playwright spec in
`tests/lab/<team>.spec.ts`. Section teams build against these props and hooks. If a prop or
hook must change, ask the component's owner, change it here, and tell the foundation owner
(branch `site`).

Numbers and strings come from `src/data/ledger.ts` and `src/data/siri.ts`. Never type
a number or a Siri line by hand.

## Ground rules for every mock

- **Points, not pixels.** Phone screens are authored in a 393 × 852 pt space.
  `Phone` sets `container-type: inline-size` and `--pt: calc(100cqw / 393)` on `.screen`;
  every in-screen length is `calc(N * var(--pt))`. Never use `var(--pt)` on `.screen`
  itself (container units resolve against the parent there).
- **Static first.** Server markup is the final state. Scenes only add from-states.
  Under `html.motion` only, hide or offset things; without `.motion` everything shows.
- **Layers.** A section's screens live in one container `<div class="screens" data-screens>`
  inside its `Phone`. Each state is a layer: `<Screen stateId="…" final?>` renders
  `<div class="layer" data-state data-screen>`. Without motion only `[data-final]` shows;
  with motion all layers stack and scenes set opacity (CSS starts non-final layers at 0).
- **The stage moves nodes.** On desktop with motion, `stage.ts` moves the section's
  `[data-screens]` into the stage phone. Style screen content with scoped classes; never
  with selectors that depend on the section around it (`#voice .x` breaks after the move).
- **Accessibility.** The phone root is `role="img"` with an `aria-label`; everything inside
  is `aria-hidden`. Mock text is presentational, so use `div`/`span`, not headings, `nav`
  or buttons. Page-level controls (Try it, ControlsCard copy) are real elements.
- **Scope hook queries to a layer.** Several components share hook names (`[data-trees]` is
  in the Live Activity, the Clock tab and the Team tab; `[data-bar="1".."4"]` are status-bar
  signal bars and `[data-bar="mon".."fri"]` the Clock tab's chart; `[data-timer]` is
  everywhere). One section's `[data-screens]` holds several layers, so query through the
  layer: `q1('[data-screen="clock-1540"] [data-trees]')`.
- **Animate only** transform, opacity, clip-path and stroke-dashoffset (the island morph
  may tween width, height and border-radius on one isolated element). No filter or
  backdrop-filter, no box-shadow animation: bake glows and shadows into layers.
- **Timers.** Live clocks carry `data-clock` (status bar, lock-screen clock) and
  `data-timer` (`auto` | `worked` | `break`). DayClock rewrites them from `day.min`. Use
  `data-clock="fixed"` / `data-timer="fixed"` for frozen crops. Timers that roll use the
  odometer markup: `<span class="odo" data-timer data-odo data-odo-text={text} set:html={odometerHTML(text)} />`
  (`src/scripts/odometer.ts`).
- **Fonts.** System text: `var(--font-system)`. Numbers: `var(--font-mono)` with tabular
  figures. Screen titles: `var(--font-display)` 700 at 34 pt. Lock clock: `var(--font-rounded)` 600 at 92 pt.
- **Truth.** No pay figures (show `•••`), no clock-out control on the lock screen, no
  invite codes, no App Store anything.

## Ownership

| Team | Files |
|---|---|
| **device-a** | `phone/Phone.astro`, `phone/StatusBar.astro`, `phone/Screen.astro`, `phone/LockScreen.astro`, `phone/LiveActivity.astro`, `phone/capture.ts`, `system/lockscreen/`, `src/pages/lab/device-a.astro`, `tests/lab/device-a.spec.ts` |
| **device-b** | `phone/DynamicIsland.astro`, `phone/SiriSnippet.astro`, `phone/SiriGlow.astro`, `phone/DictationWave.astro`, `src/scripts/wave{,.test}.ts`, `ControlsCard.astro`, `src/pages/lab/device-b.astro`, `tests/lab/device-b.spec.ts` |
| **screens** | `app/ClockTab.astro`, `app/TeamTab.astro`, `app/TreeNoteSheet.astro`, `screens/` (AppKit, Glyph, the Clock tab's cards and the clock/notes/team view models), `src/pages/lab/screens.astro`, `tests/lab/screens.spec.ts` |
| **map** | `app/TreesTab.astro`, `app/trees/markup.ts`, `FieldMap.astro`, `src/scripts/fieldmap{,.test}.ts`, `src/scripts/fieldstate.ts`, `src/pages/lab/map.astro`, `tests/lab/map.spec.ts` |
| **report** | `app/ReportTab.astro`, `PaperTimeCard.astro`, `report/` (report helpers and tests), `src/pages/lab/report.astro`, `tests/lab/report.spec.ts` |
| **foundation** (`site`) | everything else: `SectionShell`, `Header`, `DayMark`, `AppIcon`, `app/AppChrome`, `app/Icon`, `app/icons.ts`, styles, data, motion core, tests, CI |
| **section teams** | `src/sections/<Id>.astro` and `src/scripts/scenes/<id>.ts` for their chapter |

Paths below are relative to `site/src/components/`.

---

## device-a

Helpers: `system/lockscreen/activity.ts` (`activityView(props)`: everything the card shows;
`activityLabel(view)`: the sentence for a Phone's `aria-label`; `LA`, `buttonWidth`,
`stripStep`, `stripWidth`, `cardHeight` in pt), `system/lockscreen/wallpaper.ts`
(`WallpaperId`), `phone/capture.ts` (real captures). Lab: `/lab/device-a/`.

### `phone/Phone.astro`

```ts
export interface Props {
  /** aria-label for the role="img" root. Required unless decorative: the build fails without one. */
  label?: string;
  /** CSS length for the height; the width follows the 420 : 879 frame. Default: var(--phone-h). */
  height?: string;
  /** 'stage': the fixed desktop phone; 'inline': a section phone; 'peek': the crew's second phone (black titanium). */
  variant?: 'stage' | 'inline' | 'peek';
  /** aria-hidden instead of role="img" (the stage phone; it repeats the section figures). */
  decorative?: boolean;
  class?: string;
}
// default slot: the screen content (usually <div class="screens" data-screens>…</div>)
```

DOM (keep these classes and hooks):

```html
<div class="phone phone--inline" role="img" aria-label="…" data-phone data-variant="inline">
  <div class="phone-hw" aria-hidden="true">…</div>   <!-- Action, volume, side and Camera Control buttons -->
  <div class="phone-body" aria-hidden="true">        <!-- titanium band, black glass border -->
    <div class="screen">                              <!-- container-type: inline-size; --pt -->
      <slot/>
    </div>
    <div class="phone-island" data-island-rest></div> <!-- 126×37 pt at y 11 pt -->
    <div class="phone-rim" data-rim></div>            <!-- gold rim light: animate opacity -->
    <div class="phone-sheen sheen" data-sheen></div>  <!-- 20deg band of 12% white: util.sheen() -->
  </div>
  <div class="phone-shadow" data-shadow aria-hidden="true"></div>  <!-- pre-blurred contact shadow -->
</div>
```

- `[data-phone]` is `ctx.phone` on mobile. Its transform must be at rest at progress 0 and 1.
- **Geometry.** The outer frame is **420 × 879** (aspect-ratio `420 / 879`), drawn in u = 1/420
  of its width. The screen is exactly **393 × 852 pt**, set in **13.5 u** on every side (a 4.5 u
  titanium band and a 9 u glass border, 3.2% of the width), radius `55 pt`. No Apple logo.
- **Width from height** is `height × 420 / 879`, not `× 393 / 852` (that is the screen, and is
  3.6% narrower). `--stage-x/-y/-w/-h` are the stage phone's outer rect: place extras from
  them, and find the screen at `13.5 / 420` of `--stage-w` inside each edge.
- Height: `height` prop, else `var(--phone-h)` (SectionShell sets it per breakpoint).

### `phone/StatusBar.astro`

```ts
export interface Props {
  /** Shown before DayClock takes over; e.g. '7:02'. Default '7:02'. */
  time?: string;
  /** 'light' = white (lock screen), 'dark' = black (light app screens). */
  tone?: 'light' | 'dark';
  /** false freezes the time (data-clock="fixed"). Default true. */
  live?: boolean;
  /** Signal bars 0–4. Default 4. */
  signal?: 0 | 1 | 2 | 3 | 4;
  /** Shows 'No Service' instead of bars and Wi-Fi (crew offline beat). */
  noService?: boolean;
  /** Battery percent. Default 80. At 20 and below the level is red, as on iOS. */
  battery?: number;
  /** false hides the time (LockScreen passes false: the big clock shows it). Default true. */
  showTime?: boolean;
}
```

Hooks: `[data-statusbar]` root (with `data-battery`, the level, and `data-battery-low` at 20%
and below), `[data-clock]` (time, system 600 17 pt; still present, hidden, when `showTime` is
false), `[data-bar="1".."4"]` (signal bars, fade one by one), `[data-no-service]` (the text,
opacity 0 unless offline: fade it in where the bars were), `[data-wifi]`. Height 54 pt.

### `phone/Screen.astro`

```ts
export interface Props {
  /** Stable id for this state; also the real-capture filename. See the state id registry below. */
  stateId: string;
  /** Alt text for a real capture (the phone's aria-label usually says it all). */
  alt: string;
  /** Marks the layer shown without motion (exactly one per [data-screens]). */
  final?: boolean;
  /** 'dark' for lock screens, 'light' for app screens (background while loading a capture). */
  tone?: 'dark' | 'light';
  class?: string;
}
// default slot: the HTML recreation
```

Renders `<div class="layer" data-state={stateId} data-screen={stateId} data-final? data-capture?>`.
At build time it looks for `public/screens/{stateId}.{avif,webp}` (in Astro's `publicDir`, so
any working directory works) and, when one exists, renders
`<img class="capture" width="1179" height="2556" alt loading="lazy" decoding="async">` filling
the layer instead of the slot. PNG is never used. Keep hooks your scene needs outside the
swapped area (overlays, glows) or accept that a capture is a still.

### `phone/LockScreen.astro`

```ts
export interface Props {
  /** Default ledger DAY.date: 'Friday, October 16'. */
  date?: string;
  /** '7:02'. The big clock carries data-clock unless live is false. */
  time: string;
  live?: boolean;
  /** 'dawn-rows' (default) or 'dusk-rows' (the clock-out hour; fetched only where used). */
  wallpaper?: 'dawn-rows' | 'dusk-rows';
  /** Start with the dim overlay on (lock-screen zoom beat). */
  dim?: boolean;
  /** Status bar signal (0–4) and offline text, as on StatusBar. */
  signal?: 0 | 1 | 2 | 3 | 4;
  noService?: boolean;
}
// slots: default (the LiveActivity), "top" (Siri snippet/glow area), "overlay" (pocket panel etc.)
```

Hooks: `[data-lock]` root (`data-wallpaper-id`), `[data-wallpaper]`, `[data-date]` (20 pt 600
at y 70 pt), `[data-clock]` (big clock 92 pt rounded 600 at y 92 pt; the status bar's own
time is hidden on the lock screen, as on iOS), `[data-dim]` (black overlay, opacity; the
activity sits above it), `[data-padlock]` (the padlock under the island), `[data-activity-slot]`,
`[data-lock-quick]` (flashlight and camera buttons), `[data-home-indicator]`. Wallpaper: SVG fir rows on #0D2418 → #29483A → #C79A5E,
plus the pre-blurred WebP twin behind the Live Activity material. No notifications unless slotted.

### `phone/LiveActivity.astro`

```ts
import type { ActivityState } from '../../data/ledger';
export interface Props {
  /** Fill everything from ledger.liveActivityAt(at). Explicit props below override it. */
  at?: number;
  state?: ActivityState;            // 'working' | 'tapped' | 'lunch' | 'break'
  worked?: string;                  // '6:27:00'
  breakTime?: string;               // '0:00:00'
  breakReason?: string | null;      // 'Sharpening shears'
  trees?: number;                   // 220
  field?: string;                   // 'North field'
  block?: string;                   // 'Block 2'
  fieldPct?: number;                // 0.282
  rows?: [number, number, number];  // [36, 37, 38]
  nextRow?: number;                 // 39 (waiting off the right edge)
  undoRow?: number | null;          // 36 in the tapped state
  /** Timer and counts frozen (static crops). */
  fixed?: boolean;
  /** 'lock' (default): placed on the lock screen. 'solo': a standalone card filling its container's width. */
  placement?: 'lock' | 'solo';
  class?: string;
}
```

Layout: row 1 pill and '{field} · {block}'; row 2 the timer, and the 4 pt field bar on the
right (row 3's right side belongs to Undo, so the bar sits beside the timer; like the app's,
it has no visible label: VoiceOver gets '{shaped} of {total} trees shaped' through
`activityLabel()`); row 3 '{trees} trees this shift', and on the right 'Row {n} marked · Undo'
(tapped) or '{worked} worked' (break and lunch); row 4 the buttons.

Hooks (scenes rely on every one):

| Hook | What it is |
|---|---|
| `[data-la]` | root; `data-state` mirrors the state. Flip it with `tl.set(la, { attr: { 'data-state': … } })`: it turns the timer gold on lunch/break |
| `[data-la-material]`, `[data-la-break]` | green material and the gold break/lunch tint layer (crossfade by opacity) |
| `[data-pill]` > `[data-pill-face="clock"]`, `[data-pill-face="break"]` | **two stacked faces**: green 'On the clock', and gold 'On lunch' / 'On break · {reason}' / 'On break'. Crossfade the faces by opacity; never rewrite pill text to change state. Each face has its own `[data-pill-text="clock"|"break"]`; the gold one already names the coming break (a break from the card has no reason, decisions.md #3), so only a voice break with a reason needs `q1('[data-pill-text="break"]').textContent` set before it fades in |
| `[data-place]` | '{field} · {block}' (on a break the field is dropped so the reason fits) |
| `[data-timer]` | odometer timer, Plex Mono 600 38 pt (gold on break/lunch) |
| `[data-field]` > `[data-fieldbar]` | the 4 pt bar: track, and the fill (`scaleX` = fieldPct, origin left). Tween the fill's scaleX on a tap |
| `[data-trees-line]` > `[data-trees]` | the line, and the odometer count in '{trees} trees this shift'; roll it with `util.odometer` on a tap |
| `[data-undo]` > `[data-undo-row]` | 'Row {n} marked · Undo' (opacity 1 in the tapped state); the row number is its own span |
| `[data-worked-line]` | '{worked} worked', row 3 right, on break/lunch (fade [data-undo] out as it fades in) |
| `[data-strip]` > `[data-strip-track]` > `[data-row="36"]`… | row buttons in a sideways-clipped strip; advance = `x: '-=' + step` (one button + 8 pt gap: `stripStep` pt, or two `[data-row]`s' `offsetLeft` apart in px). A fourth row waits off the right edge. **Tapped** layers render the track one step left with the marked row waiting off the left edge: `x: step → 0` replays the tap |
| `[data-break-btn]` | Break (outlined), stays fixed while the strip moves |
| `[data-back-btn]` | full-width Back to work (#E2A644 / #2A1C04), revealed by clip-path `inset(0 100% 0 0)` → `inset(0)` |

Break and lunch layers render the row buttons at `scaleX(0)` with `transform-origin: 0% 50%`
(inline), so tweening them back to `scaleX: 1` grows them from the left; collapse working rows
with `transformOrigin: '100% 50%'`. Pass `transformOrigin` to choose otherwise.

Geometry: width 361 pt, bottom at y 760 pt, radius 24 pt, padding 12/14 pt, height ≤ 160 pt
(159), buttons 46 pt tall, 77.25 pt wide, radius 14 pt, 8 pt gap. **Never a clock-out button.**

---

## device-b

### `phone/DynamicIsland.astro`

```ts
export interface Props {
  size?: 'rest' | 'compact' | 'expanded';
  row?: number;                 // 37
  time?: string;                // '6:29' (compact, H:MM)
  timer?: string;               // '6:29:10' (expanded)
  field?: string;               // 'North field'
  block?: string;               // 'Block 2'
  rows?: [number, number];      // [37, 38] plus Break
  trees?: number;               // 230 (expanded, under the place)
  /** DayClock drives both timers (data-timer="worked"). Default false (fixed). */
  live?: boolean;
  /** Normal flow, for crops outside a phone (fits its container, max 1 px/pt). */
  inline?: boolean;
}
```

Hooks: `[data-island]` (one element; width/height/border-radius tween between rest 126×37,
compact 250×37, expanded 371×160 radius 44; absolutely positioned, `contain: layout`; the
static size is `data-size`), `[data-island-compact]`, `[data-island-expanded]` (content;
fades in at 70% of the morph), `[data-island-time]` (compact H:MM; with `live` a DayClock
`data-timer="worked"` clipped to H:MM so it agrees with the expanded timer), `[data-timer]`
inside expanded, `[data-island-row="37"]`, `[data-island-row="38"]`, `[data-island-break]`
(the expanded buttons: `util.tap` targets), `[data-island-lens]` (the front camera, drawn at
x 241, y 29.5 pt at every size). Sits at y 11 pt, z-index 8 inside the screen, above every
screen layer. Phone's own rest island (`[data-island-rest]`, the hardware) paints over its
middle, since `.screen` is its own stacking context: black on black with the lens in the same
place, so it never shows; the island draws its own lens too, for crops and stacking changes.

Layout: nothing crosses the camera cutout (the rest island, x 133.5–259.5 pt). Compact:
'Row 37' in the left ear (x 78.5–126), the fir and '6:29' in the right ear (x 265–311).
Expanded: the badge and the solid 'On the clock' pill (#2E7A4E, white, like the Live
Activity's) sit on the camera's centre line, y 29.5 pt; the pill starts right of x 265.5.

**The status bar yields.** Put the island in the same `<Screen>` layer as the status bar.
In a layer whose island is compact or expanded, the status-bar time (`[data-statusbar]
[data-clock]`) moves 30 pt left (`translate`), from the left ear's centre (x 68) to the outer
ear's (x 38), clear of the island; the signal bars, `[data-wifi]` and `[data-no-service]`
fade, leaving the battery; expanded, the whole status bar fades (the island covers it). All
of it follows the custom property `--island-yield` on the layer: 0 rest, 1 compact,
2 expanded (the static value follows `data-size`). Scenes that morph the island tween
`--island-yield` on the `[data-screen]` layer in step with the width, e.g.
`tl.fromTo(layer, { '--island-yield': 0 }, { '--island-yield': 1 }, at)`.
Relies on StatusBar's hooks `[data-statusbar]`, `[data-clock]`, `[data-bar]`, `[data-wifi]`,
`[data-no-service]`.

### `phone/SiriSnippet.astro`

```ts
export interface Props {
  text: string;                 // from SIRI.*.reply (or .ask)
  choices?: readonly string[];  // ['Yes', 'No']
  /** Which choice shows as tapped in the final state. */
  chosen?: string;
  /** Top of the card in pt. Default 64. */
  top?: number;
}
```

Hooks: `[data-snippet]` (card at y 64 pt, 361 pt wide, radius 26, rgba(28,32,30,.92)),
`[data-snippet-text]` (17 pt white; util.typeIn target) with the reply pre-split into
`[data-word="0".."n"]` spans (karaoke-ready), `[data-choice="Yes"]`, `[data-choice="No"]`
(40 pt chips; Yes filled #2E7A4E, No outlined), `[data-choice-ring]` inside each chip (the
gold "tapped" outline: opacity 0 → 1). Header: 20 pt app icon + 'TIME CARD' 11 pt.
The reply wraps greedily (`text-wrap: pretty`) and keeps numbers with their units ('block 2',
'row 14', '10 trees', '34 an hour', '8 hours 30 minutes').

**Siri covers the lock screen's clock.** A `[data-lock]` holding a `[data-snippet]` or a
`[data-wave]` hides its own `[data-date]`, big `[data-clock]` and padlock (opacity 0; the
static final state). Scenes that drop the card in fade those three from 1 to 0 over the same
span as the `[data-snippet]`/`[data-wave]` drop-in (`tl.fromTo(chrome, { opacity: 1 },
{ opacity: 0 }, at)`). The padlock is LockScreen's `[data-padlock]`.

### `phone/SiriGlow.astro`

```ts
export interface Props {
  /** true: the faint static border; false: always the full glow; omitted: full glow under
      html.motion, faint border without it. */
  still?: boolean;
}
```

Hooks: `[data-glow]` (opacity), `[data-glow-ring]` (rotation). A conic gradient
(#88CFA4, #7FB2D9, #C9A0E0, #E2A644) masked to the screen's inner edge, 6 pt wide (the still
border too). Generic, not Apple's asset.

### `phone/DictationWave.astro` and `src/scripts/wave.ts`

```ts
export interface Props {
  bars?: number;          // 24
  seed?: number;          // 7
  /** Progress to draw statically (0–1). */
  progress?: number;
  /** Transcript typed under the wave; without one the card says 'Listening…'. */
  transcript?: string;    // SIRI.shiftNote.answer
  /** Top of the card in pt. Default 64. */
  top?: number;
}
// wave.ts
export const WAVE_MIN: number; // 0.1, a resting bar (a round dot)
export function waveHeights(progress: number, seed?: number, bars?: number): number[]; // 0–1 each, deterministic
export function setWave(wave: HTMLElement | null | undefined, progress: number): void; // writes --h on each bar
```

Hooks: `[data-wave]` (card; `data-seed`, `data-bars`), `[data-wave-bar]` (one bar; its height
h is the custom property `--h`, drawn with transforms only: a middle scaled to h·36 − 3 pt
and two 3 pt round caps moved to ±(h·18 − 1.5) pt), `[data-transcript]` with
`[data-word]` spans, `[data-listening]` ('Listening…'). Bars 3 pt wide, 2 pt gap. Scenes
scrub it with `setWave(waveEl, progress)`.

**One card at a time.** The wave and the snippet share Siri's slot (y 64 pt). When Siri
answers, the SiriSnippet **replaces** the wave card in the same slot (crossfade); never
stack them. Like the snippet, the wave hides the lock screen's date, clock and padlock.

### `ControlsCard.astro` (page level, real text)

```ts
export interface Props {
  /** Highlight the Action button in gold. Default true. */
  highlightAction?: boolean;
  class?: string;
}
```

A `--card-dark` card: three round 64 px tiles 'Next row', 'Break', 'Clock in', plus an
outline of a phone's left edge (fading out down and to the right) with the Action button in
gold and the label 'Action button → Next row'. Hooks: `[data-controls]`,
`[data-control="next-row"|"break"|"clock-in"]`, `[data-action-button]` (glow layer: opacity
pulse), `[data-action-key]` (the gold button shape), `[data-action-label]` (the label: fade or
slide in). Include the qualifier text in the section, not here: Action button on iPhones that
have one; Control Center needs iOS 18 or later.

---

## screens

All app screens render inside `app/AppChrome.astro` (foundation):

```ts
// AppChrome props
{ title: string; tab: 'clock' | 'trees' | 'log' | 'report' | 'team'; admin?: boolean;
  time?: string; noService?: boolean; subtitle?: string; class?: string;
  leading?: { icon: IconName; text?: string; id?: string }[];
  trailing?: { icon: IconName; text?: string; id?: string }[] }
// slots: default (content), "header" (pickers under the title), "overlay" (sheets, banners)
// hooks: [data-app], [data-app-scroll], [data-scroll-layer] (translate for in-phone scroll),
//        [data-tool="gear"], [data-tabbar], [data-tab="clock"]…
```

Tabs are **Clock, Trees, Log, Report, Team** (Team for admins). Settings is a gear in
the Clock tab's toolbar. Icons: `<Icon name="…">` from `app/icons.ts` (add glyphs there
via the foundation owner). The screens team's shared app styles (cards, chips, flags,
buttons, avatars) live in `screens/AppKit.astro`; every value comes from the ledger through
the view models in `screens/clock/clock.ts`, `screens/notes/notes.ts` and `screens/team/team.ts`.

### `app/ClockTab.astro`

```ts
export interface Props {
  /** Ledger minute for every value. Default MOMENTS.pace (3:40 PM). */
  at?: number;
  /** Pace card segment. Default 'today'. */
  range?: 'today' | 'week' | 'season';
  /** Pace rows whose gold left rule shows statically (reduced-motion figures). Default none. */
  highlight?: readonly ('trees-hour' | 'per-tree' | 'pay' | 'best' | 'left')[];
  /** false freezes the status card timer (data-timer="fixed") for static crops. Default true. */
  live?: boolean;
}
```

Recreated from the app's Clock tab (about 1,850 pt tall inside `[data-scroll-layer]`; scenes
translate it), top to bottom, each a card in `screens/clock/`:

- **Status** (`StatusCard`): fir while working, sap on a break or lunch, surface off the
  clock; pill with a pulse light, the running h:mm:ss in Plex Mono 52 pt (odometer markup,
  DayClock rolls it), 'worked today', 'Clocked in at 7:02 AM', [Break] [Clock out].
- **Now working** (`NowWorkingCard`): 'North field · Block 2 · Row 39' and the next three
  rows plus Break as tiles (on a break the tiles rest and a line says what's next).
- **Trees this shift** (`TreesCard`): the count (260 at 3:40), Mark trees, and the field's
  share beside a fir progress bar.
- **Pace** (`PaceCard`): segmented Today | This week | Season; '34 trees an hour', '1:46 a
  tree', 'Pay per tree •••', 'Best day · Thu, Oct 15 · 318 trees', 'About 179 hours left in
  North field at your pace'.
- **Shift notes** (`ShiftNotesCard`, hidden off the clock): the shift's note field, 'Saved'.
- **Hours & pay** (`HoursPayCard`): today and this week, a bar per weekday (today gold), pay
  masked '•••', eye-slash 'Show pay'.

A scroll-edge fade sits under the status bar and above the floating tab bar, so no content
reads through the glass.

Hooks: `[data-clock-tab]` (root of the content, `data-at`), `[data-scroll-layer]` (from
AppChrome), `[data-status-card]` (`data-phase`), `[data-timer]`, `[data-break-line]`,
`[data-status-btn="clock-in"|"break"|"back"|"clock-out"]`, `[data-now-working]`,
`[data-now-row="39"]`… and `[data-now-break]` (not `data-row`: the Live Activity's strip uses
that in the same container), `[data-trees-card]`, `[data-trees]` (odometer: `util.odometer`),
`[data-field-bar]` (fill: scaleX from the left), `[data-field-pct]`, `[data-pace-card]`,
`[data-segment="today"|"week"|"season"]`, `[data-pace-row="trees-hour"|"per-tree"|"pay"|"best"|"left"]`,
each with a `[data-pace-rule]` (3 pt gold rule in the left margin; rests at `scaleY(0)`, tween
to 1; `highlight` draws it statically), `[data-shift-notes]`, `[data-shift-note-text]` (typing
target), `[data-notes-state]`, `[data-hours-card]`, `[data-bar="mon"…"fri"]` (fills,
transform-origin bottom: scaleY grows them from the baseline), `[data-pay]`, `[data-pay-toggle]`.

### `app/TeamTab.astro`

```ts
export interface Props {
  /** Default ledger TEAM (through Fri 3:00 PM). */
  rows?: ReadonlyArray<{ name: string; hours: string; trees: number }>;
}
```

'This week' (the week's date span from the ledger) lists each member's hours and trees, a
total, then Invite someone and Fields & blocks. The status bar shows 3:00 PM (MOMENTS.synced).
Hooks: `[data-team-row="Alex"|"Sam"|"Rosa"]` with `[data-hours]` (odometer markup) and
`[data-trees]` inside, `[data-team-total]`, `[data-invite]` ('Invite someone'),
`[data-fields-row]` ('Fields & blocks ›'). No invite code, no expiry, no pay.

### `app/TreeNoteSheet.astro`

```ts
import type { Person, TreeNote } from '../../data/ledger';
export interface Props {
  /** Default ledger TREE_NOTE. */
  note?: TreeNote;
  /** All of this tree's notes, oldest first (listed newest first). Default [note]. */
  notes?: readonly TreeNote[];
  /** Sheet height as a fraction of the screen. Default 0.55. */
  height?: number;
  /** Ledger minute the sheet is open at: pass the host TreesTab's `at`. Default MOMENTS.treeNote (2:33 PM). */
  at?: number;
  /** Whose phone, for the shaped line's color (gold = their own shift). Default WORKER (Alex). */
  who?: Person;
}
```

An iOS 26 medium-detent sheet, inset 6 pt with concentric corners, opaque: grabber, 'Block 2 ·
Row 36 · Tree 7' in Zilla Slab 24 pt, a close button, whether the tree is shaped (in the map's
colors), the notes newest first (flag chip, text, avatar and byline 'Alex · Today 2:33 PM'),
and [Add note] 50 pt. TreesTab's `sheet` prop renders it with the tab's own `at`, `who` and
that tree's notes, so prefer `<TreesTab sheet={note} …/>` to placing it yourself; standalone,
put it in AppChrome's `overlay` slot or after the tab in the same layer.

Hooks: `[data-sheet]` is the **slide wrapper**: full width, anchored to the screen's bottom,
the sheet plus 40 pt of room above it for the shadow. Tween it `yPercent: 100 → 0`; at 100 the
sheet and its shadow are wholly off screen. Its first child is the visible sheet. Inside:
`[data-note="0"…]` per note, `[data-flag-chip]`, `[data-note-text]`, `[data-note-byline]`,
`[data-shaped]` (`data-shaped` = the state), `[data-add-note]`. A home indicator sits outside
`[data-sheet]` and stays put. Flags are exactly 'Needs attention', 'Dead', 'Replant' (ledger FLAGS).

---

## map

### `app/TreesTab.astro`

```ts
export interface Props {
  /** Ledger minute for which trees are gold. Default MOMENTS.field. */
  at?: number;
  block: number;                         // 2
  /** The rows this screen is about: centred between the controls and the legend when they
      fit, otherwise `from` is the first row shown. An open sheet overrides both. */
  rows: [from: number, to: number];      // [28, 40]
  zoom?: 'All' | 'XS' | 'S' | 'M' | 'L'; // 'L'
  mode?: 'one' | 'fill' | 'erase';
  /** Whose phone: Sam's shows his own row 12 gold (and no Team tab). Default 'Alex'. */
  who?: 'Alex' | 'Sam';
  /** Extra rows to show gold (offline marks before sync). */
  pending?: Array<{ block: number; row: number }>;
  /** Note markers (rust flags). Default: the notes that exist at `at`. */
  notes?: TreeNote[];
  syncLine?: string | null;              // 'Offline · 2 changes waiting' | 'Synced'
  /** Reserve the sync line's 38 pt row even without a line (an empty, hidden [data-sync-line]),
      so states with and without one share the same map geometry. Default: true with a line. */
  syncSlot?: boolean;
  banner?: string | null;                // CONFLICT_MESSAGE
  noService?: boolean;
  /** Open the TreeNoteSheet on this note (the map scrolls so its row stays above the sheet). */
  sheet?: TreeNote | null;
}
```

Light-mode map after the app's FieldLayout: 'Trees', [North field ▾], zoom chips
All XS S M L, the optional sync line, [One | Fill | Erase] and [Undo]; the map with a pinned
block header, row numbers in a 26 pt gutter, striped block; the legend chips Today, Earlier,
Not yet above the floating tab bar. Gold = this person's current shift, green = shaped earlier
by anyone, ring = not yet (decisions.md #4); states come from `treeStatus()` in
`src/scripts/fieldstate.ts`. The conflict banner is a toast just above the legend.

Hooks: `[data-map]` (root; `data-at`, `-who`, `-zoom`, `-mode`, `-block`), `[data-map-row="37"]`
(a row of 10 dots, target block only), `[data-block-row="2-37"]` (every rendered row),
`[data-tree="2-37-4"]` (one dot: `data-s="ring|earlier|today"`; its fills read the custom
properties `--e` (green) and `--g` (gold), so fill a row with
`gsap.to(q('[data-map-row="37"] [data-tree]'), { '--g': 1, stagger: 0.01 })` and crossfade
gold to green with `{ '--g': 0, '--e': 1 }`; pops are transforms), `[data-row-label="37"]`,
`[data-note-marker="2-36-7"]` > `[data-note-ripple]`, `[data-sync-line]`
(`data-sync="offline|synced"`), `[data-sync-count]` (odometer), `[data-sync-plural]`,
`[data-banner]`, `[data-mode]` > `[data-mode-thumb]`, `[data-mode-option="one"|"fill"|"erase"]`,
`[data-undo-btn]`, `[data-zoom-chip="L"]`, `[data-legend]`, `[data-field-picker]`.

### `FieldMap.astro`, `src/scripts/fieldmap.ts` and `src/scripts/fieldstate.ts`

```ts
export interface Props {
  /** Ledger minute for the drawn state. Default MOMENTS.field (2:15 PM). */
  at?: number;
  view?: 'overview' | 'zoom';
  /** Zoomed view. Default block 2 rows 28–40 (ZOOM_TARGET). */
  zoom?: { block: number; from: number; to: number };
  /** Accessible summary. Default: built from the ledger at `at` (at 2:15 PM, the brief's sentence; the close-up has its own). */
  label?: string;
  class?: string;
  /** Draw the field scene's choreography statically at this progress (labs, tests). */
  progress?: number;
  /** Force the overview's orientation instead of following the box's shape. */
  orientation?: 'portrait' | 'landscape';
}
// fieldmap.ts
export function ensureFieldMap(canvas: HTMLCanvasElement, opts?: FieldMapOptions): FieldMapHandle;
export interface FieldMapHandle {
  setProgress(p: number): void;            // the field scene's choreography (sceneState); no-op if unchanged
  draw(state: Partial<MapState>): void;    // anything custom; redraws next frame, once
  render(sharp?: boolean): void;           // synchronous draw (labs, tests)
  resize(): void;
  pointAt(block: number, row: number, tree: number): { x: number; y: number }; // CSS px in the canvas
  readonly state: Readonly<MapState>; readonly orientation: 'portrait' | 'landscape';
  readonly frames: number; destroy(): void;
}
// fieldstate.ts (pure, unit-tested): fieldLayout(), treeStatus(), sceneState(p), finalState(),
// BEATS (the scene's progress windows), fieldSummary(at), zoomSummary(), createTryIt() (the Try it model)
```

North field's 8,540 trees on Canvas 2D (about 40 pattern-filled runs, DPR ≤ 2, one frame per
change). The box takes the width it is given; its aspect comes from the layout: **portrait
below 900px** (blocks 1–7 across, like the app), **landscape from 900px** (the field turned a
quarter turn anticlockwise, about 1.58 : 1, Block 1 bottom-left; the zoom turns it back
upright, so the close-up matches mobile). First paint and no-JS: an inline SVG of the same
state; the canvas loads its renderer within one viewport, draws the final state and hides the
SVG. In the close-up everything outside block 2 rows 28–40 dims to 22%.

`MapState`: `at`, `reveal` (gold rows revealed, in mark order; null = all), `camera` (0
overview, 1 zoomed), `labels`, `demo` (row 37's demo fill), `season` (1 = next season, fills
faded to rings, notes stay), `pulse`, `touch`, `undo` (for the scene's own DOM Undo chip).
`BEATS`: reveal .30–.52, zoomIn .52–.58, labelsIn .55–.59, touch .59–.625, demoIn .61–.64,
undo .64–.67, demoOut .67–.70, seasonOut .73–.81, pulse .79–.87, seasonIn .88–.92,
labelsOut .88–.90, zoomOut .90–.98.

Hooks: `[data-fieldmap]` (the canvas, `role="img"` with the summary as its label),
`[data-fieldmap-box]` (`data-ready` after the first frame), the event `fieldmap:ready` on the
canvas. Page dots: gold #E2A644 (20% larger), green #2E7A4E, ring #6F8F7A, rust #C2462A note
flag (`STAGE_THEME`). Unit tests: 8,540 dots; 2,190 green + 230 gold at 2:15.

---

## report

### `app/ReportTab.astro`

```ts
export interface Props {
  range?: 'This week' | 'Last week' | 'This month' | 'Pick dates';
  /** Show the Pick dates sheet (From/To and a calendar) over the screen. Default false. */
  picker?: boolean;
  /** Status-bar time before DayClock takes over. Default '4:31'. */
  time?: string;
}
```

AppChrome title 'Report', tab 'report': range chips This week | Last week | This month as a
segmented control, the period 'Mon, Oct 12 – Fri, Oct 16' with (Pick dates), totals HOURS
39:55 · TREES 1,347 · DAYS 5, a PREVIEW of the paper in miniature (`PaperTimeCard mini`, the
same proportions as the page card at 720px), [Export PDF] [CSV]. No pay anywhere.

Hooks: `[data-range-chip="this-week"|"last-week"|"this-month"|"pick-dates"]` (the selected
one has `data-selected`), `[data-range-thumb]` (the segmented control's thumb),
`[data-report-total="hours"|"trees"|"days"]`, `[data-paper-thumb]` (the Flip source rect),
`[data-export="pdf"|"csv"]`, and with `picker` the `[data-date-sheet]` and its `[data-date-scrim]`.

### `PaperTimeCard.astro` (page level, a real table)

```ts
import type { Day } from '../data/ledger';
export interface Props {
  /** Default ledger WEEK. */
  days?: readonly Day[];
  /** Default 'Alex'. */
  worker?: string;
  /** Default WEEK_RANGE 'Mon, Oct 12 – Fri, Oct 16'. */
  range?: string;
  /** The job in the band. Default 'Tree trimming'. */
  job?: string;
  /** Show 'Prepared Fri, Oct 16 at 4:31 PM' (the moment of clock-out). Default true. */
  prepared?: boolean;
  /** Presentational miniature for the in-phone preview (divs, no hooks, pt units). */
  mini?: boolean;
  /** Mini only: the preview is still drawing (no example data for this range). */
  pending?: boolean;
  class?: string;
}
```

`<table>` with `<caption>` 'Example time card for Alex, Mon, Oct 12 – Fri, Oct 16';
`<th scope="col">` Date | In | Out | Trees | Hours | Breaks | Notes; totals in `<tfoot>`
'39:55 hours · 1,347 trees' over a true double rule; footnote 'Breaks are listed, not counted.'
and 'Prepared …'. Under 600px of **its own width** (a container query named `tc`, not the
viewport) rows become stacked day blocks with no horizontal scroll; scenes can tell by
`tr[data-day]` computing to `display: flex` (a Flip from the ReportTab preview only matches
the card from 680px wide). Empty cells are visually hidden, never removed, so every row keeps
seven cells for screen readers.

Hooks: `[data-paper]` (root, the Flip target), `[data-paper-shadow]` (the pre-blurred shadow,
its own layer: fade its opacity), `[data-paper-band]` (fir header band), `tr[data-day="mon"…"fri"]`
(print rows by clip-path), `[data-cell="mon-trees"…"fri-hours"]` each holding a `[data-flash]`
gold layer (animate opacity; rests at 0, hugs the number, paints behind the text),
`[data-totals-rule]` (scaleX), `[data-totals]`. No pay column, ever.

---

## Scenes (section teams)

`src/scripts/scenes/<id>.ts`:

```ts
import { registerScene } from '../scene';
registerScene('voice', (ctx) => {
  const { tl, day, util, q, phone, screens } = ctx;
  day.to(tl, MOMENTS.firstRow, 0.4, 0.5);      // tween the shared minute
  util.tap(tl, q('[data-row="36"]')[0], 0.55);
  return () => {/* optional cleanup */};
}, { dayStart: MOMENTS.misheard });
```

`ctx`: `{ id, section, tl, phone, screens, extras, frame, beats, q, q1, day, isDesk, util,
gsap, ScrollTrigger, SplitText, Flip, stage, trigger, tint }`. `tl` is scrubbed (`start 'top top'`,
`end 'bottom bottom'`, `scrub 0.6`) and normalized: place everything between 0 and 1.
`util`: `tap, odometer, karaoke, typeIn, drawLine, crossfade, sheen, callout, ambient`
(see `src/scripts/util.ts`). Leave the phone at rest at 0 and 1, and end screen layers in the
state the next section starts from.

## Real captures: the state id registry

Drop `public/screens/<state-id>.webp` (or `.avif`), 1179 × 2556 and at most 200 KB, and the
matching `<Screen>` renders it instead of the recreation. Encode simulator PNGs first
(`cwebp -q 80 -m 6 -sharp_yuv in.png -o out.webp`; see the site README); `npm test` fails on a
PNG, a wrong size or a heavy file. Capture these first (decisions.md #9):
**`lock-1414-activity`**, **`trees-1415-block2`**, **`report-week`**.

| Section | State ids (final in bold) |
|---|---|
| hero | **`lock-0702-clockin`** |
| voice | `lock-0718-misheard`, `lock-0719-next`, `lock-1201-lunch`, `lock-1231-back`, **`lock-1401-status`** |
| lock-screen | `lock-1414-activity`, **`lock-1414-tapped`**, `home-1416-island-compact`, `home-1416-island-expanded` |
| field | **`trees-1415-block2`** |
| notes | `lock-1430-break`, `lock-1433-treenote`, **`trees-1433-note`**, `lock-1436-dictation`, `lock-1444-back` |
| crew | `trees-1447-block3`, `trees-1456-offline`, **`trees-1500-synced`**, `sam-1449-trees`, `team-1500` |
| pace | `lock-1540-activity`, **`clock-1540`** |
| clock-out | `lock-1631-activity`, `lock-1631-ask`, `lock-1631-answer`, `lock-1631-quiet`, **`report-week`** |
