# Health

The spec for the second round of Health work. It adds steps and distance to each shift's workout, an optional GPS route, and a Health card for each shift on the iPhone, and it names the workout **Tree care**. It builds on the watch workout in `docs/watch.md` §2 and changes only what's written here.

**Josh's decisions:**

1. **Time Card keeps recording the shift.** The Action button, Double Tap and keeping the app on the wrist all depend on its workout. Gentler Streak and other apps read the saved workout from Health. Only one workout can run on the watch, so starting another app's workout during a shift still ends Time Card's ("Recording stopped", `docs/watch.md` §2.5).
2. **The workout is called "Tree care"**, not "Other".
3. **GPS is off by default.** When it's on, location only feeds the Tree care workout's route and distance. It goes nowhere else.
4. **The route isn't connected to the tree grid.** That's a separate task for later (§8).

---

## 1. The Tree care workout

Apple's list of workout types is fixed. The watchOS 26.2 SDK still has no gardening, farming or occupational type, and apps can't add one. So **"Tree care" is Time Card's name for the workout, and Health stores it as Other** (`HKWorkoutActivityType.other`, outdoor).

- **Why Other underneath:** Other counts calories from heart rate, with a brisk-walk fallback when the sensor has no reading. That suits arm-heavy shaping. Hiking or walking would switch to motion-based calories, and Fitness would show the shift as a hike. [HK-F3]
- **`ShiftWorkoutType`** (TreeFarmKit `Watch/`): one case today, `.treeCare`, with `name` "Tree care" and `key` "treeCare". A later type (mowing, planting) is one more case.
- **Metadata** (adds to `docs/watch.md` §2.3):

| Key | Value |
|---|---|
| `HKMetadataKeyWorkoutBrandName` | `"Tree care"` (was `"Time Card shift"`) |
| `"TimeCardWorkoutType"` (custom) | `"treeCare"` |

  Everything else in §2.3 is unchanged.
- **Wording.** The watch says "Recording tree care", and the onboarding card is "Record Tree care workouts". The iPhone setting's detail says Health files them as Other: "Clock-in starts a Tree care workout on your watch (Other in Apple Health), lunch and breaks pause it, and clock-out ends it."
- **How Health and Fitness show it** isn't settled until the device check (§7). Apple's apps list workouts by type, so expect "Other" with Time Card as the source. Whether the brand name appears anywhere is to be seen.

## 2. Steps and distance on the watch

- The live data source collects two more types beside the defaults for Other: `enableCollection(for: .stepCount)` and `enableCollection(for: .distanceWalkingRunning)`, both with a nil predicate. Without GPS, distance is the watch's stride estimate.
- **Health access** asks to read `stepCount` and `distanceWalkingRunning` too, and to share `workoutRoute` (so the route needs no second Health prompt later). A watch that allowed Health before this change (Josh's) shows the Health card **once more** ("Time Card now records steps and distance with each shift."), without the notification question. Its workouts keep recording meanwhile: `WorkoutDriver.asksForMore` is true until the new request has been made. The request is remembered by version (`HealthKitWorkoutDriver.readVersion`, now 2), so a later addition asks again the same way.
- **Live:** `WorkoutDriverEvent.metrics` carries steps and meters too. The Today page shows a second line under the heart line: "🚶 1.2 mi · 2,410 steps".
- **Summary:** `WorkoutSummary` gains `steps` and `distanceMeters`. Both are optional, so a summary from an older watch still reads. The summary screen adds "3.4 mi · 8,120 steps". It never scrolls (Double Tap is Done), so to make room the worked time first shrinks to 60%, and only then does the distance line go. The 49 mm watch shows all three lines; a 40–42 mm watch keeps just the heart line, as before. Miles or kilometres follow the watch's region (`Locale.measurementSystem`).

## 3. The GPS route (off by default)

**The setting.** In iPhone Settings › Apple Watch, under "Record shifts as workouts":

- **"Record route (GPS)"**, off by default. It's dimmed and reads as off while workouts are off.
- Detail: "Uses GPS for distance and saves a map of where you worked with the Tree care workout in Health. Uses more battery."
- It's saved per person on this phone (`WatchSettings.recordRoute`) and travels to the watch as `WatchState.recordRoute`. The desk sends `recordWorkouts && recordRoute`.

**On the watch, when it's on:**

- **Permission.** If location was never asked, the onboarding card asks: "Record your route", "GPS measures distance and saves a map of where you worked with the Tree care workout. It stays in Health and never goes to the farm.", **Allow Location** (`requestWhenInUseAuthorization`). It comes after the Health card, never before. A request that gets no answer gives up after two minutes, so the card can't trap anyone. If location is denied, the workout records without a route. The Today page says "Route off · Allow Location for Time Card in Settings on your watch."
- **Only while the workout runs.** `CLLocationManager` (`activityType = .fitness`, best accuracy, 5 m distance filter) updates only while a Tree care session is **running**. It stops on lunch and breaks (the session is paused), at a stop, finish or discard, and when the setting goes off. Turning the setting on mid-shift starts the route from then.
- **Where points go.** Fixes with a horizontal accuracy of 50 m or better are kept. They go in batches of 50 into the workout builder's route, `builder.seriesBuilder(for: .workoutRoute())`, which the workout finishes and attaches when it saves. The last batch is flushed before `finishWorkout()`. Nothing calls `finishRoute`: the header says a route built this way must not. A discarded workout takes its route with it.
- **Nowhere else.** Locations never go to the phone over WatchConnectivity, never into `WorkoutSummary`, any file, the outbox, a sync record or the tree map. The only trace outside Health is the distance number, which comes from the workout's statistics as before. **One exception, opt-in:** an admin's phase 0 field log (`docs/gis.md` §10) records the fixes to a file that goes to their own phone.
- **Distance with GPS on** still comes from `distanceWalkingRunning`. With location allowed on an outdoor session, the watch is expected to refine it with GPS (device check §7). Time Card doesn't add up route points itself.
- **Recovery.** A recovered session gets `seriesBuilder(for: .workoutRoute())` again (it returns the builder's existing route) and restarts updates if it's running with the setting on. Points from before a crash may be lost. That's acceptable.
- **Info.plist (watch):** `NSLocationWhenInUseUsageDescription` = "Time Card records your route during a Tree care workout when you turn on Record route. It stays in Health and is never sent to the farm." There's **no `location` background mode**. A running workout session keeps the app running with the wrist down, and CoreLocation allows "while in use" updates whenever the app is running (not suspended). Setting `allowsBackgroundLocationUpdates` without that mode is a fatal error, so it isn't set. If the device check (§7) shows gaps with the wrist down, add both together.
- **Battery.** Apple rates the Ultra 2 at about 12 hours for a GPS workout and the SE 3 at about 7. A 9-hour shift fits on the Ultra with less to spare. The clock-in battery warning (`docs/watch.md` §2.8) is unchanged.

## 4. The shift's Health card (iPhone)

Each shift in the Log gets a **Health** button beside Edit and Trees. When the three glove buttons don't fit on one line, Health takes a row of its own, so no word breaks. A shift still on the clock shows its numbers so far. The button opens a full-height sheet like the Trees sheet:

- **Header:** the day and times, then the worked time in big type with "worked".
- **Numbers:** steps, distance, flights climbed, active calories, and average and maximum heart rate. Each is left out when Health has none. A row whose number won't fit beside its label ("avg 104 · max 151") puts the number underneath.
- **What it covers:** the shift's **worked time only**: start to end with lunch and breaks cut out (`Shift.workIntervals(at:)`). It's Health's own total over those spans, so it works whichever app recorded (Time Card, Gentler Streak, or none), and steps from the iPhone and the watch aren't counted twice. HealthKit's statistics queries merge sources.
- **The watch's workout,** when the phone has its summary (`WatchDesk.summary(for:)`), adds a line: "Tree care workout · 7:41 active".
- **Footnote:** "From Apple Health, for the time you worked. It stays on this iPhone and is never sent to the farm."
- **Permission:** the first time, a card asks: "See your shift's steps, distance and heart rate" with **Allow Health**. That requests read access for steps, distance, flights, active energy and heart rate. HealthKit doesn't say whether reading was denied, so when every number is empty, the card says: "No Health data for this shift. If you expected some, check Health › Sharing › Apps › Time Card."
- **Code:** `ShiftHealth` holds the values, and `ShiftHealthWording` makes every line (tested). `ShiftHealthReader` is the seam (`AppModel.health`), with `HealthKitShiftHealthReader` as the real one: one `HKStatisticsQuery` per type, with an OR of the work spans as the predicate. A sample that straddles a span's edge counts whole, which moves a total by seconds' worth. UI tests and test hosts get `DemoShiftHealthReader`, which never prompts.
- **Usage string (iPhone)**, now that it reads: "Time Card shows the steps, distance and heart rate from your shifts. They stay on your iPhone and Apple Watch and are never sent to the farm."

## 5. Privacy

The rule from `docs/watch.md` §2.3 stands and now covers location: **health data and routes never leave the person's devices.** Nothing here adds a field to any `SyncRecord` or server API. The route lives only in Health, attached to the workout.

## 6. Wire and settings compatibility

- `WatchState.recordRoute` and `WatchSettings.recordRoute` decode as **false** when missing, so an older phone or saved setting means no GPS.
- `WorkoutSummary.steps` and `.distanceMeters` are optional.
- `WatchWire.version` stays 1: nothing old becomes unreadable.

## 7. Device checks (add to `docs/watch.md` §7.5)

1. The Health card shows again once on the watch and asks for steps and distance (and to save routes). Workouts keep recording before it's answered.
2. A shift with the route off: no location indicator, and distance and steps show live and in the summary.
3. Turning the route on mid-shift: the watch asks for location, the route starts from then, lunch leaves a gap in the map, and the route keeps going with the wrist down for 10 minutes (§3, Info.plist).
4. The saved workout in Fitness and Health: what type and name it shows (§1), whether the route map appears, and whether Gentler Streak picks it up and how it names it.
5. Distance with GPS on against a known walk (a block's length).
6. A full shift with GPS on the Ultra 2: battery at clock-out.
7. The iPhone's Health card for a Time Card shift, and for a day recorded with Gentler Streak instead.

## 8. Later: the route and the tree grid

Planned in `docs/gis.md`: placing blocks on the state's aerial photo, a map with layers on the iPhone, and a matching engine on the watch that learns from Josh's marks and suggests rows shaped but not marked.
