# Shared component contract

Every shared component the parallel teams build: where it lives, its `Props`, the
`data-*` hooks scenes animate, and how a real simulator capture replaces it. Each file
already exists as a **stub** that compiles with these props and renders a labeled box
(plus the hooks), so sections can be built against it today. Replace the stub's body;
keep the `Props` interface and the hooks. If a prop must change, change it here first
and tell the foundation owner (branch `site`).

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
| **device-a** | `phone/Phone.astro`, `phone/StatusBar.astro`, `phone/Screen.astro`, `phone/LockScreen.astro`, `phone/LiveActivity.astro`, `src/pages/lab/device-a.astro` |
| **device-b** | `phone/DynamicIsland.astro`, `phone/SiriSnippet.astro`, `phone/SiriGlow.astro`, `phone/DictationWave.astro`, `src/scripts/wave.ts`, `ControlsCard.astro`, `src/pages/lab/device-b.astro` |
| **screens** | `app/ClockTab.astro`, `app/TeamTab.astro`, `app/TreeNoteSheet.astro`, `src/pages/lab/screens.astro` |
| **map** | `app/TreesTab.astro`, `FieldMap.astro`, `src/scripts/fieldmap.ts`, `src/pages/lab/map.astro` |
| **report** | `app/ReportTab.astro`, `PaperTimeCard.astro`, `src/pages/lab/report.astro` |
| **foundation** (`site`) | everything else: `SectionShell`, `Header`, `DayMark`, `AppIcon`, `app/AppChrome`, `app/Icon`, `app/icons.ts`, styles, data, motion core, tests, CI |
| **section teams** | `src/sections/<Id>.astro` and `src/scripts/scenes/<id>.ts` for their chapter |

Paths below are relative to `site/src/components/`.

---

## device-a

### `phone/Phone.astro`

```ts
export interface Props {
  /** aria-label for the role="img" root (required unless decorative). */
  label?: string;
  /** CSS length for the height; width follows 393/852. Default: var(--phone-h). */
  height?: string;
  /** 'stage': the fixed desktop phone; 'inline': a section phone; 'peek': the crew's second phone. */
  variant?: 'stage' | 'inline' | 'peek';
  /** aria-hidden instead of role="img" (the stage phone; it repeats the section figures). */
  decorative?: boolean;
  class?: string;
}
// default slot: the screen content (usually <div class="screens" data-screens>…</div>)
```

DOM (keep these classes and hooks):

```html
<div class="phone phone--inline" role="img" aria-label="…" data-phone>
  <div class="phone-body" aria-hidden="true">        <!-- titanium edge, bezel, side buttons (Action button) -->
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
- Aspect ratio 393/852, radius `55 pt`, bezel 3.2% of width, no Apple logo.
- Height: `height` prop, else `var(--phone-h)` (SectionShell sets it per breakpoint).

### `phone/StatusBar.astro`

```ts
export interface Props {
  /** Shown before DayClock takes over; e.g. '7:02'. Default '7:02'. */
  time?: string;
  /** 'light' = white (lock screen), 'dark' = ink (app screens). */
  tone?: 'light' | 'dark';
  /** false freezes the time (data-clock="fixed"). Default true. */
  live?: boolean;
  /** Signal bars 0–4. Default 4. */
  signal?: 0 | 1 | 2 | 3 | 4;
  /** Shows 'No Service' instead of bars (crew offline beat). */
  noService?: boolean;
  /** Battery percent. Default 80. */
  battery?: number;
}
```

Hooks: `[data-clock]` (time, -apple-system 600 17 pt), `[data-bar="1".."4"]` (signal bars,
fade one by one), `[data-no-service]` (the text variant, hidden unless offline), `[data-wifi]`.
Height 54 pt.

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

Renders `<div class="layer" data-state={stateId} data-screen={stateId} data-final?>`. At
build time it checks `public/screens/{stateId}.{avif,webp,png}` (1179 × 2556) and, when one
exists, renders `<img width="1179" height="2556" alt loading="lazy" decoding="async">`
filling the layer instead of the slot. Keep hooks your scene needs outside the swapped area
(overlays, glows) or accept that a capture is a still.

### `phone/LockScreen.astro`

```ts
export interface Props {
  /** Default ledger DAY.date: 'Friday, October 16'. */
  date?: string;
  /** '7:02'. The big clock and status bar carry data-clock unless live is false. */
  time: string;
  live?: boolean;
  wallpaper?: 'dawn-rows';
  /** Start with the dim overlay on (lock-screen zoom beat). */
  dim?: boolean;
}
// slots: default (bottom: the LiveActivity), "top" (Siri snippet/glow area), "overlay" (pocket panel etc.)
```

Hooks: `[data-lock]` root, `[data-clock]` (big clock 92 pt ui-rounded 600 at y 92 pt and the
status bar), `[data-date]` (20 pt 600 at y 70 pt), `[data-dim]` (black overlay, opacity),
`[data-wallpaper]`, `[data-activity-slot]`. Wallpaper: SVG fir rows on #0D2418 → #29483A →
#C79A5E, plus the pre-blurred WebP twin behind the Live Activity material. Flashlight and
camera buttons and a white home indicator at the bottom. No notifications unless slotted.

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
}
```

Hooks (scenes rely on every one):

| Hook | What it is |
|---|---|
| `[data-la]` | root, `data-state` mirrors the state |
| `[data-la-material]`, `[data-la-break]` | green material and the gold break/lunch tint layer (crossfade by opacity) |
| `[data-pill]`, `[data-pill-text]` | 'On the clock' / 'On lunch' / 'On break · {reason}' |
| `[data-place]` | '{field} · {block}' |
| `[data-timer]` | odometer timer, Plex Mono 600 38 pt (gold on break/lunch) |
| `[data-worked-line]` | '{worked} worked' under the timer on break/lunch |
| `[data-trees]` | odometer count in '{trees} trees this shift' |
| `[data-fieldbar]` | the 4 pt bar fill (scaleX = fieldPct, origin left) |
| `[data-undo]` | 'Row {n} marked · Undo' (tapped state) |
| `[data-strip]` > `[data-strip-track]` > `[data-row="36"]`… | overflow-clipped row buttons; advance = translateX by one button + 8 pt gap; 4th row waits off the right |
| `[data-break-btn]` | Break (outlined), stays fixed while the strip moves |
| `[data-back-btn]` | full-width Back to work (#E2A644 / #2A1C04), revealed by clip-path |

Geometry: width 361 pt, bottom at y 760 pt, radius 24 pt, padding 12/14 pt, height ≤ 160 pt,
buttons 46 pt tall, radius 14 pt, 8 pt gap. **Never a clock-out button.**

---

## device-b

### `phone/DynamicIsland.astro`

```ts
export interface Props {
  size?: 'rest' | 'compact' | 'expanded';
  row?: number;                 // 37
  time?: string;                // '6:29' (compact)
  timer?: string;               // '6:29:10' (expanded)
  field?: string;               // 'North field'
  block?: string;               // 'Block 2'
  rows?: [number, number];      // [37, 38] plus Break
}
```

Hooks: `[data-island]` (one element; width/height/border-radius tween between rest 126×37,
compact 250×37, expanded 371×160 radius 44; absolutely positioned, `contain: layout`),
`[data-island-compact]`, `[data-island-expanded]` (content; fades in at 70% of the morph),
`[data-timer]` inside expanded. Sits at y 11 pt over Phone's rest island.

### `phone/SiriSnippet.astro`

```ts
export interface Props {
  text: string;                 // from SIRI.*.reply
  choices?: readonly string[];  // ['Yes', 'No']
  /** Which choice shows as tapped in the final state. */
  chosen?: string;
}
```

Hooks: `[data-snippet]` (card at y 64 pt, 361 pt wide, radius 26, rgba(28,32,30,.92)),
`[data-snippet-text]` (17 pt white; util.typeIn target), `[data-choice="Yes"]`, `[data-choice="No"]`
(40 pt chips; Yes filled #2E7A4E, No outlined). Header: 20 pt app icon + 'TIME CARD' 11 pt.

### `phone/SiriGlow.astro`

```ts
export interface Props {
  /** Reduced motion: a faint static border instead of the glow. */
  still?: boolean;
}
```

Hooks: `[data-glow]` (opacity), `[data-glow-ring]` (rotation). A conic gradient
(#88CFA4, #7FB2D9, #C9A0E0, #E2A644) masked to the screen's inner edge, 6 pt wide.
Generic, not Apple's asset.

### `phone/DictationWave.astro` and `src/scripts/wave.ts`

```ts
export interface Props {
  bars?: number;          // 24
  seed?: number;          // 7
  /** Progress to draw statically (0–1). */
  progress?: number;
  /** Transcript typed under the wave. */
  transcript?: string;    // SIRI.shiftNote.answer
}
// wave.ts
export function waveHeights(progress: number, seed?: number, bars?: number): number[]; // 0–1 each, deterministic
```

Hooks: `[data-wave]`, `[data-wave-bar]` (scaleY from waveHeights), `[data-transcript]`.
Bars 3 pt wide, 2 pt gap. Unit-test that the same progress gives the same heights.

### `ControlsCard.astro` (page level, real text)

```ts
export interface Props {
  /** Highlight the Action button in gold. Default true. */
  highlightAction?: boolean;
}
```

A `--card-dark` card: three round 64 px tiles 'Next row', 'Break', 'Clock in', plus an
outline of a phone's left edge with the Action button in gold and the label
'Action button → Next row'. Hooks: `[data-controls]`, `[data-control="next-row"|"break"|"clock-in"]`,
`[data-action-button]` (glow layer: opacity pulse). Include the qualifier text in the section,
not here: Action button on iPhones that have one; Control Center needs iOS 18 or later.

---

## screens

All app screens render inside `app/AppChrome.astro` (foundation):

```ts
// AppChrome props
{ title: string; tab: 'clock' | 'trees' | 'log' | 'report' | 'team'; admin?: boolean;
  time?: string; noService?: boolean; subtitle?: string;
  leading?: { icon: IconName; text?: string; id?: string }[];
  trailing?: { icon: IconName; text?: string; id?: string }[] }
// slots: default (content), "header" (pickers under the title), "overlay" (sheets, banners)
// hooks: [data-app], [data-app-scroll], [data-scroll-layer] (translate for in-phone scroll),
//        [data-tool="gear"], [data-tabbar], [data-tab="clock"]…
```

Tabs are **Clock, Trees, Log, Report, Team** (Team for admins). Settings is a gear in
the Clock tab's toolbar. Icons: `<Icon name="…">` from `app/icons.ts` (add glyphs there
via the foundation owner).

### `app/ClockTab.astro`

```ts
export interface Props {
  /** Ledger minute for every value. Default MOMENTS.pace (3:40 PM). */
  at?: number;
  /** Pace card segment. Default 'today'. */
  range?: 'today' | 'week' | 'season';
}
```

Content (1,700 pt tall scroll layer): status card (#1D5B3A, 'On the clock', timer 40 pt
mono, 'Clocked in at 7:02 AM', [Break] [Clock out]); Now working 'North field · Block 2 ·
Row 39' with [Row 39][Row 40][Row 41][Break]; Trees this shift 260; Pace card (segmented
Today | This week | Season; '34 trees an hour', '1:46 a tree', 'Pay per tree •••',
'Best day · Thu, Oct 15 · 318 trees', 'About 179 hours left in North field at your pace');
Hours & pay chart (Mon 8:37 … Fri 7:39 gold), pay '•••', eye-slash 'Show pay'.

Hooks: `[data-scroll-layer]` (from AppChrome), `[data-status-card]`, `[data-timer]`,
`[data-now-working]`, `[data-trees]`, `[data-pace-card]`, `[data-pace-row="trees-hour"|"per-tree"|"pay"|"best"|"left"]`,
`[data-pace-rule]` (3 pt gold rule, scaleY), `[data-hours-card]`, `[data-bar="mon"…"fri"]`
(scaleY from the baseline), `[data-pay]`, `[data-pay-toggle]`.

### `app/TeamTab.astro`

```ts
export interface Props {
  /** Default ledger TEAM (through Fri 3:00 PM). */
  rows?: ReadonlyArray<{ name: string; hours: string; trees: number }>;
}
```

Hooks: `[data-team-row="Alex"|"Sam"|"Rosa"]`, `[data-hours]`, `[data-trees]`,
`[data-invite]` ('Invite someone'), `[data-fields-row]` ('Fields & blocks ›'). No invite
code, no expiry, no pay.

### `app/TreeNoteSheet.astro`

```ts
import type { TreeNote } from '../../data/ledger';
export interface Props {
  /** Default ledger TREE_NOTE. */
  note?: TreeNote;
  /** Sheet height as a fraction of the screen. Default 0.55. */
  height?: number;
}
```

Overlay for TreesTab (use AppChrome's `overlay` slot or position absolutely). Grabber,
'Block 2 · Row 36 · Tree 7' Zilla Slab 24 pt, flag chip (rust, white), the note, byline
'Alex · Today 2:33 PM', [Add note] 50 pt. Hooks: `[data-sheet]` (yPercent 100 → 0),
`[data-flag-chip]`, `[data-note-text]`, `[data-add-note]`. Flags are exactly
'Needs attention', 'Dead', 'Replant' (ledger FLAGS).

---

## map

### `app/TreesTab.astro`

```ts
export interface Props {
  /** Ledger minute for which trees are gold. Default MOMENTS.field. */
  at?: number;
  block: number;                         // 2
  rows: [from: number, to: number];      // [28, 40]
  zoom?: 'All' | 'XS' | 'S' | 'M' | 'L'; // 'L'
  mode?: 'one' | 'fill' | 'erase';
  /** Whose phone: Sam's shows his own row 12 gold. Default 'Alex'. */
  who?: 'Alex' | 'Sam';
  /** Extra rows to show gold (offline marks before sync). */
  pending?: Array<{ block: number; row: number }>;
  notes?: TreeNote[];                    // markers (rust flags)
  syncLine?: string | null;              // 'Offline · 2 changes waiting' | 'Synced'
  banner?: string | null;                // CONFLICT_MESSAGE
  noService?: boolean;
  /** Open the TreeNoteSheet on this note. */
  sheet?: TreeNote | null;
}
```

Light-mode map: gold #B57A12 (today, this person), green #1D5B3A (shaped earlier, anyone),
ring #A9C2AF (not yet); row numbers in a left margin at 13 pt mono; legend chips Today,
Earlier, Not yet. Hooks: `[data-map]`, `[data-map-row="37"]` (a row of 10 dots),
`[data-tree="2-37-4"]` (one dot), `[data-row-label="37"]`, `[data-note-marker="2-36-7"]`,
`[data-sync-line]`, `[data-sync-count]`, `[data-banner]` (ink bg, 4 pt rust left rule,
white 15 pt), `[data-mode]`, `[data-undo-btn]`, `[data-zoom-chip="L"]`.

### `FieldMap.astro` and `src/scripts/fieldmap.ts`

```ts
export interface Props {
  /** Ledger minute for the drawn state. Default MOMENTS.field (2:15 PM). */
  at?: number;
  view?: 'overview' | 'zoom';
  /** Zoomed view: block 2 rows 28–40. */
  zoom?: { block: number; from: number; to: number };
  /** Accessible summary (defaults to the ledger sentence in the brief). */
  label?: string;
  class?: string;
}
// fieldmap.ts (pure layout is unit-tested)
export function fieldLayout(): { width: number; height: number; dots: Array<{ x: number; y: number; block: number; row: number; tree: number }> };
export function createFieldMap(canvas: HTMLCanvasElement, opts): { setProgress(p: number): void; draw(state): void; destroy(): void };
```

Canvas 2D, DPR ≤ 2, sprites pre-rendered, overview bitmap cached, redraw only on change,
init within one viewport (IntersectionObserver rootMargin 100%). Root `<canvas role="img"
aria-label>` with `[data-fieldmap]`. Page dots: gold #E2A644 (20% larger), green #2E7A4E,
ring #6F8F7A 1.5 px, rust note flag. Unit tests: 8,540 dots; 2,190 green + 230 gold at 2:15.

---

## report

### `app/ReportTab.astro`

```ts
export interface Props {
  range?: 'This week' | 'Last week' | 'This month' | 'Pick dates';
}
```

AppChrome title 'Report', tab 'report'. Range chips (This week selected), a paper preview
thumbnail, [Export PDF] [CSV]. Hooks: `[data-range-chip="this-week"…]`, `[data-paper-thumb]`
(the Flip source rect), `[data-export="pdf"|"csv"]`. No pay.

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
}
```

`<table>` with `<caption>` 'Example time card for Alex, Mon, Oct 12 – Fri, Oct 16';
`<th scope="col">` Date | In | Out | Trees | Hours | Breaks | Notes; totals in `<tfoot>`
'39:55 hours · 1,347 trees' over a double rule; footnote 'Breaks are listed, not counted.'
Stacked day blocks under 600 px (no horizontal scroll). Hooks: `[data-paper]`,
`[data-paper-shadow]` (separate pre-blurred layer), `tr[data-day="mon"…"fri"]`,
`[data-cell="fri-trees"]`, `[data-cell="fri-hours"]`, `[data-totals-rule]`, `[data-totals]`,
`[data-paper-band]`. No pay column, ever.

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

Drop `public/screens/<state-id>.png` (or `.webp`/`.avif`), 1179 × 2556, and the matching
`<Screen>` renders it instead of the recreation. Capture these first (decisions.md #9):
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
