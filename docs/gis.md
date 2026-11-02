# GPS and GIS

The plan for putting the farm on a real map and using the watch's GPS, motion and heart rate to notice rows you've shaped but not marked. It builds on the Tree care workout and its route (`docs/health.md`), and it replaces §8 of that doc ("Later: the route and the tree grid").

This is a plan, not yet a spec: phase 0 measures what the watch can really do at the farm, and the later phases are sized by what it finds.

**Josh's decisions (2026-11-02):**

1. **Layers of imagery and maps on the trees**, on the iPhone.
2. **One GPS.** When the watch records the route, everything uses the watch's GPS. The phone never runs a second one during a shift.
3. **It learns** what Josh's work looks like, and it **earns trust** before it speaks: suggestions start only once its guesses have matched his marks well enough, shift after shift.
4. **Live suggestions during the shift**, on the watch: "Rows 18–19 in Block 3 look shaped. Mark them?" Never automatic: a suggestion becomes a mark only when Josh says so.
5. **Watch only**, no extra GPS hardware. If the watch can't separate neighboring rows, suggestions name a range instead.
6. **A Time Card row crosses a band north–south** (confirmed from the aerial photo, §0).

---

## 0. What the farm looks like from above

Indiana flies the whole state on a 3-year cycle and publishes the photos free (CC0). The current service covers 2022–2025 at **3-inch (7.6 cm) pixels** around the farm, which is enough to see every tree.

From that imagery (1765 W Blubaugh Ave, Thorntown; the plantation north of Blubaugh, east of the pond):

| | Measured from the photo (about ±10%) |
|---|---|
| A **block** | One band between two mower lanes, about **115 m** east–west and **22 m** north–south (lane included) |
| A **row** | 10 trees running north–south across the band, about **1.8 m** apart, so about 18 m long |
| Row to row | About **1.9 m**, east–west. 61 rows ≈ 115 m |
| Lanes | A darker strip every ~22 m north–south; the main lanes run north–south between the plantation's two columns |

This matches the farm's 14 blocks of 61 rows × 10 trees.

**What that means for GPS.** A good phone or watch fix is off by about 3–5 m. That's **less than a quarter of a band**, so which block you're in is easy. But it's **2–3 rows** east–west, so which row you're in is the hard part. Two things help a lot:

- **Shaping a row is a walk across the band.** About 18 m north or south, then about 1.9 m sideways, then back. GPS is much better at *relative* movement over a minute than at absolute position, so counting those crossings should count rows even when the absolute position is 2 rows off. **This is the main hypothesis phase 0 tests.**
- **Marks are anchors.** Every row Josh marks says "I was at row 14 at 9:02". The engine uses each one to correct GPS's slow-drifting offset, and the marks bound every gap ("marked 14, then 20").

## 1. How it fits together

```
 iPhone                                        Apple Watch (during a Tree care workout)
 ──────                                        ─────────────────────────────────────────
 Trees tab: Grid | Map                          RouteRecorder (CoreLocation) ── route → Health
   imagery tiles (cached for offline)                     │ the same fixes, never a 2nd GPS
   blocks and rows, marks, notes, routes                  ▼
 Block placement editor (admin)                 Matching engine (TreeFarmKit Geo/, pure Swift)
   → BlockPlacement records ── sync ──▶ server     ▲ heart rate (workout builder)
 Reads past routes from Health                     ▲ wrist motion (CMBatchedSensorManager)
                                                   ▲ marks and placements (from the phone)
          ◀── GeoContext (placements, marked rows) │
          ── WatchRequest .markRow ─────────────▶  ▼
                                                Suggestions: card + haptic, or notification
```

The engine runs **on the watch**, where the GPS, the motion sensors and the heart rate are. Live locations never cross to the phone. The phone sends the watch what it needs to match against: block placements, which rows are marked, and the next row.

## 2. Placing blocks on the map

**The record.** A new synced kind, `BlockPlacement`, one per block:

- `blockId`, plus four corners in latitude/longitude: row 1 tree 1, row 1 tree last, last row tree last, last row tree 1.
- Tree positions come from interpolating between the corners (bilinear), so a slightly skewed block still fits.
- `source` (`.imagery(year)`, `.walked`, `.refined`) and `updatedAt`.

It's a separate kind rather than a field on `Block`: the server decodes and re-encodes blocks, so an older app editing a block would wipe the placement. Older apps can't read a kind they don't know, so **the server only sends `blockPlacement` to apps whose pull says they read it**. The server ships first.

**The editor** (admins; Team › Fields › a block › **Place on map**):

- The aerial photo, with the block drawn as an outline and all 610 tree dots over it. Glove-size handles drag the corners until the dots sit on the trees. Labels on row 1 and row 61 make a flipped block obvious.
- **Copy to the next band**: places the next block one band north or south with the same shape, so 14 blocks takes minutes, not an afternoon.
- **Walk a corner** for trees planted after the last flight: stand at the corner tree and hold **Mark corner here**, which averages 30 seconds of fixes.
- Later (phase 4): **Fit to trees** finds the tree blobs in the photo and fits the corners itself.

## 3. The map and its layers (iPhone)

The Trees tab gets **Grid | Map**. The Grid is today's schematic and stays the fastest place to mark. The Map is an `MKMapView` wrapped for SwiftUI, because SwiftUI's `Map` still can't take custom imagery tiles.

**Imagery (base layer, pick one):**

- **Indiana aerial photo**, the default: the state's current service, fetched as Web Mercator tiles for the farm's area (z16–z20, roughly 15 MB) and **kept for offline use**, then zoomed past z20 to see single trees. Older years (the state publishes back to 2005) can be picked to watch blocks grow.
- **Apple satellite**: the fallback, and for anyone outside Indiana.
- **None**: blocks and rows on plain ground, for bright sun.

**Overlays (each on or off):**

- **Blocks and rows**: outlines, names, row numbers at higher zoom.
- **Shaped this season**: each tree a dot, shaped or not, from the marks.
- **Tree notes**: a pin on each noted tree (notes already belong to a tree, so they get a place for free).
- **My route**: any past shift's route, read from Health on the phone (it already has the route; phase 1 adds read access for routes).
- **Where the engine thought you were** (phase 2), and **suggestions** (phase 3).
- **Where I am**: the blue dot, only while the Map is open. It's the phone's own location, briefly, in the foreground.

**Later layers** (each is one more overlay): your own drone mosaic (GeoTIFF or MBTiles import), Indiana's statewide LiDAR as hillshade or contours (drainage, frost pockets), and USDA soil map units.

## 4. One GPS

During a shift, at most one device uses GPS for Time Card:

- **The watch**, whenever a Tree care workout runs with **Record route** on. The engine reads the same fixes the route recorder already gets: one `CLLocationManager`, two listeners.
- **The phone never starts GPS during a shift.** The only exception is the Map's blue dot while the Map is on screen, which is the person looking, not tracking.
- With Record route off, there's no matching and no suggestions. The Settings footnote says so.
- A phone-GPS fallback for people without a watch is possible later. It needs its own decision, and it's not in this plan.

## 5. What the watch senses

All of it comes from the running Tree care workout, so none of it needs a new session:

- **Position**: the route's fixes (about 1 per second while moving), with their accuracy.
- **Heart rate**: from the workout builder, as now.
- **Wrist motion**: `CMBatchedSensorManager` (watchOS 10+), the high-rate accelerometer Apple opened to workout apps. Shaping shears or a knife leave a strong, rhythmic signature that walking doesn't. The watch reduces it on the spot to a few numbers per second (stroke rate, motion energy) and keeps no raw samples.
- **Marks and taps**: every row marked on the watch, by Siri or on the phone, with its time.

## 6. The matching engine (TreeFarmKit `Geo/`)

Pure Swift, like `FieldEngine`, so it's tested on Linux with recorded shifts replayed through it. It updates once a second and costs almost nothing: about 61 rows × 2–3 nearby blocks.

**6.1 Coordinates.** Latitude and longitude become meters east and north of the farm, then each block's own `(across, along)`: which row, and how far along the row.

**6.2 What you're doing**, every few seconds: **shaping**, **moving**, **idle**, or **on a break** (the workout is paused, so GPS is off anyway). It comes from:

- Stroke rate and motion energy, the strongest sign.
- Speed from GPS: shaping is a slow walk with stops.
- Heart rate **relative to your own** walking and resting levels, which the engine learns. On its own it's weak, but it helps tell shaping from standing.

**6.3 Where you are.** A hidden Markov model over `(block, row)`:

- The GPS fix, minus the current offset estimate, gives each row a likelihood, with a spread learned from your marks.
- **Crossings**: each north–south crossing of the band while shaping is evidence of one row (or two, if you turn out to work two rows per pass; phase 0 finds out).
- Moves favor staying, then the next row in walk order, then the neighbors. Blocks only change at lanes.
- How long you stay in a row comes from your own pace (`Pace` already knows trees per hour).

**6.4 Where you should be.** From your last marked row, the walk order (`FieldWalker`) and your pace, the engine predicts a row ("marked 14 at 9:02, about 6 minutes a row, so around 19 by 9:32"). It compares that with where it thinks you are:

- **Agree**: nothing to say.
- **You're ahead of your marks, shaping**: the rows between were likely done (§7).
- **You're in another block**: offer to move the next row there, so Siri's "mark the next row" follows you (§7).

**6.5 Learning.** Everything it learns is stored on the watch as your `GeoProfile`, with a copy on your phone, and never on the farm:

- **GPS offset**: each mark is a known position at a known time, which corrects the slowly drifting offset. It starts each shift from the last one.
- **GPS spread**: how far your fixes really scatter here, by block.
- **Pace and pattern**: seconds per tree, crossings per row, and which way you work through a block.
- **Your activity levels**: heart rate and motion when shaping, walking and standing.
- **Block placement**: tracks from marked rows show if a block sits a meter off. The phone offers the admin a nudge (a `.refined` placement). It's never applied silently.
- If simple statistics aren't enough for the activity model, phase 4 trains a Create ML activity classifier on Josh's own labeled shifts. Marks are the labels.

## 7. Suggestions (live, on the watch)

**What it suggests, in the order they're expected to earn trust:**

1. **Gaps between marks** ("Rows 15–19 between row 14 and row 20 look shaped"). Two marks bound them, so this only needs the right block plus crossings and activity. It's the most likely to work first.
2. **Rows behind you**: you've moved at least 2 rows past them, the engine is sure they were shaped, and they aren't marked.
3. **Another block**: "You're in Block 5. Move the next row there?" (`moveTo`, not a mark).
4. **At clock-out**: the clock-out confirmation lists any rows still suggested: "2 rows look shaped but aren't marked: 18–19. Mark them first?"

**How it shows:**

- **On screen** (the app is up): a full-width card on the Now page, **Mark rows 18–19** as the primary action (Double Tap), **Not now** below, and a haptic.
- **Wrist down**: a local notification with the same two actions. Double Tap takes the primary one.
- **Mark** sends ordinary `.markRow` requests through the existing courier, so they queue out of reach, sync, undo and count like any other mark.
- **Not now** quiets that suggestion. **Not me** (on the card's second page) records that the engine was wrong, which teaches it.
- At most one suggestion every 15 minutes, none on lunch or a break, and none for rows someone else marked.

## 8. "Dialed in": when suggestions turn on

- **Shadow mode first.** From the first shift with Record route on, the engine runs silently. At clock-out it scores itself against the rows actually marked that shift:
  - **Precision**: of the rows it would have suggested, how many you marked anyway.
  - **Recall**: of the rows you marked, how many it thought were shaped.
  - **Row error**: how far its position was from each mark.
- The score goes to the phone as a `GeoSummary` (numbers only, no locations). Settings › Apple Watch shows it: "Row matching: 92% on your last 3 shifts."
- **The gate:** suggestions of each kind (§7) become available once, over the last 3 shifts with at least 20 marked rows, precision is **≥ 90%** for that kind. Josh then turns on **Suggest unmarked rows**. Thresholds are tunable and start strict.
- **If row error stays above about 1 row** (1.9 m) while gaps and blocks score well, suggestions stay at range level, and rows-behind-you never unlocks. That's the "watch only" answer to accuracy.

## 9. Privacy

The rule from `docs/health.md` §5 stands: **health data and locations never reach the farm.** For this feature:

- Live locations, motion and heart rate stay on the watch. The engine runs there.
- The phone sees your routes only through Health, after the shift, on your own phone.
- What syncs: block placements (farm data, admin-edited), and marks you chose to make (as today).
- **Admins never see anyone's route, position or score.** Showing crew coverage to an admin would be a separate decision.
- The phase 0 field log (§10) is the one exception to "live locations stay on the watch". It's opt-in, sent only to your own phone on request, deleted after 30 days, and never committed to the public repo.
- `docs/health.md` §3 ("Nowhere else") changes to match this when the engine lands.

## 10. Phases

Each phase ships on its own and is useful without the next.

**Phase 0: Measure** (a week or two of Josh's normal shifts)
- A **field log** on the watch, behind a developer switch. **Built (2026-11-02):**
  - **The switch:** iPhone Settings › Apple Watch › **Field log (testing)**. Admins only, off by default, and only with workouts on. It travels as `WatchState.fieldLog`.
  - **What it writes:** while a Tree care workout session exists, `FieldLogger` (watch) writes one JSON Lines file per workout (`TreeFarmKit/Geo/FieldLog.swift`): a header, then one line a second. Each line has every raw fix since the last line, the latest heart rate, the session phase, and the wrist motion reduced by `MotionFeatures`: sample count, energy, a first stroke count, and the acceleration's magnitude at 25 a second.
  - **Sources:** the fixes come from the route recorder, so **Record route must be on** for positions. The motion comes from `CMBatchedSensorManager`, which asks for Motion & Fitness the first time.
  - **Getting it to the Mac:** when the workout ends, the file goes to the phone with WatchConnectivity's `transferFile`, which waits if the phone is out of reach. The phone keeps it for 30 days (`FieldLogStore`), and Settings shows **Share N field logs** for AirDrop to the Mac. The watch keeps its copy for 7 days.
  - **Marks:** they aren't in the log. The analysis reads them from the farm server's database by time, which also catches marks made on the phone or by Siri.
- **Place 2–3 blocks by hand** from the photo. The corners can be taken on the Mac first; the editor comes in phase 1.
- **Replay** the logs through a first engine on the Mac. Questions to answer:
  - GPS error across rows, before and after the mark-based offset correction.
  - Whether crossings show up cleanly, and how many per row.
  - Whether wrist strokes separate shaping from walking.
  - How quickly the offset drifts.
- **Decision**: which suggestion kinds are realistic, and the starting thresholds.

**Phase 1: The map** (iPhone and server)
- The `BlockPlacement` kind, server first, gated by client support.
- The Grid | Map switch, Indiana and Apple imagery with an offline cache, and the overlays for blocks and rows, shaped trees, notes, and past routes from Health.
- The placement editor: drag corners, copy to the next band, walk a corner.

**Phase 2: The engine, in shadow mode** (watch)
- The engine in TreeFarmKit, tested with synthetic shifts and (locally only) Josh's logged ones.
- `GeoContext` from phone to watch: the placements of the current field and today's marked rows, as a bitmap per block.
- The watch runs it live and scores each shift. Settings shows the score. On the phone, the map can show where the engine thought you were.

**Phase 3: Suggestions** (watch)
- The kinds in §7, each unlocked by its own score, plus the card, the notification actions, the clock-out list, rate limits and feedback.

**Phase 4: Sharper**
- Fit to trees, placement refinement from tracks, and the Create ML activity model if needed.

**Later**
- Drone, LiDAR, soils and older-year layers; tree-level positions for notes and harvest tags; a phone-GPS fallback; anything for the crew.

## 11. Risks and open questions

- **GPS across rows** is the big one. If crossings don't show and the offset drifts fast, suggestions stop at gaps between marks. That's still useful, and phase 0 says which.
- **How Josh shapes**: one row per pass, or two rows from the aisle between them? It changes the crossing count. Phase 0 shows it.
- **Battery**: GPS plus high-rate motion for 9 hours. The Ultra 2 is rated about 12 hours of GPS workout. Phase 0 measures it. Other watches may get suggestions only with a full charge.
- **The motion API** needs the workout session (which exists) and may need its own permission prompt. To check on the device.
- **Notifications while a workout app runs**: whether a local notification with actions shows with the wrist down, or only in the app. To check on the device. The card covers the app-on-screen case either way.
- **The state's imagery service** moved servers before. The offline cache, plus Apple satellite as a fallback, keeps the map working if it moves again.
- **New plantings** missing from the 2022–25 photo: walk a corner.
- **Suggestion fatigue**: strict gates, rate limits, and Not me as training.

## 12. Device checks (per phase, added to `docs/watch.md` §7.5 as each lands)

- **Phase 0**: a full shift with the field log on, and the battery at clock-out.
- **Phase 1**: the placed blocks' tree dots sit on the trees at full zoom; the map works offline in the field; Health's route draws over the right rows.
- **Phase 2**: the shadow score after three shifts; the engine's track against Josh's own memory of the day.
- **Phase 3**: Double Tap on the card and on the notification through gloves; the clock-out list; no suggestion during lunch.

## Sources

- Indiana statewide orthoimagery: the current ImageServer (`di-ingov.img.arcgis.com/arcgis/rest/services/DynamicWebMercator/Indiana_Current_Imagery/ImageServer`), 2022–2025, 3–6 inch, CC0. Program details in IGIO's 2024 orthophotography presentation.
- Apple: `HKWorkoutRouteQuery` and "Reading route data" (routes are readable once the workout is saved; read access is needed for workouts and routes); `CMBatchedSensorManager` (watchOS 10+); `MapPolyline` in SwiftUI MapKit, with tile overlays still needing `MKMapView`.
- Christmas tree spacing: University of Kentucky extension FOR-17 (6 × 6 ft typical).
- Apple Watch Ultra 2 battery: apple.com/watch/battery (about 12 h of outdoor GPS workout).
