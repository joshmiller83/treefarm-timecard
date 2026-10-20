# Apple Watch

The spec for Time Card on Apple Watch. It is the plan of record for the watch work: the parallel slices in section 8 build exactly this, test-first, against the contracts named here.

**Two decisions from Josh shape everything:**

1. **The iPhone is always nearby, and it stays the single source of truth.** The watch is a companion. It drives the phone over WatchConnectivity and never holds the farm, the store or the sync engine. A tap made while the phone is out of reach waits on the watch with the time it was made, and the phone applies it at that time once it is back, but only to the shift it was made in.
2. **Every shift records as an Apple Watch workout.** Clock-in starts an outdoor workout, lunch and breaks pause it, and clock-out ends it. Health logs heart rate and calories, and the running workout keeps Time Card on the wrist for the whole shift.

**Why the watch matters:** ordinary leather or insulated work gloves don't register on the watch's touchscreen, and Apple Watch has no glove mode. So the inputs that work in the field are hands-free: **Double Tap, the Digital Crown, the Ultra's Action button and Siri**. Every shift action has to work through them. Touch is the backup, for bare fingers, knuckles and conductive-tip gloves, so every target is still huge. [UI-F5, UI-P3]

**Research key.** Citations point to the four research reports behind this spec: **UI** (watch UI and input), **WC** (WatchConnectivity), **HK** (HealthKit workouts) and **SYS** (complications, Smart Stack, Live Activity, project setup). `F` is a finding, `P` a pitfall and `R` a recommendation, so `[WC-F4]` is WatchConnectivity finding 4. The key Apple sources are listed at the end.

---

## 1. Architecture

### 1.1 The picture

```
 ┌──────────────────────────── Apple Watch ────────────────────────────┐
 │  Double Tap · Crown · Buttons · Siri (watch) · Action button (Ultra) │
 │                │                                                    │
 │        WatchShiftModel (@MainActor)                                 │
 │          confirmed WatchState + pending/in-flight → displayed state │
 │          │            │                     │                       │
 │   WatchCourier    ShiftWorkout ──────▶ HKWorkoutSession + builder   │
 │   (actor, owns    (one serial input queue;                          │
 │    WatchOutbox,    WorkoutPlan.reconcile decides)                   │
 │    saved to disk)                                                   │
 │          │        WatchStateFile (displayed state, App Group) ──▶ complications
 └──────────┼──────────────────────────────────────────────────────────┘
            │ sendMessageData: WatchEnvelope(.request) ⇄ (.reply)
            │ updateApplicationContext: WatchState (latest only)
            │ transferCurrentComplicationUserInfo: WatchState (phase changes)
            │ HKHealthStore.startWatchApp (phone clock-in → watch workout)
 ┌──────────┼───────────────────────── iPhone ─────────────────────────┐
 │   PhoneWatchBridge (@MainActor, activated in AppModel.init)          │
 │          │                                                          │
 │      WatchDesk ── WatchInbox (dedupe + shift aliases)               │
 │          │   └── makeState(): the one revision counter (KeyValueStore)
 │          ▼                                                          │
 │   FieldActions.perform(_:at:newShiftId:) ── Store + outbox ──sync──▶ Server
 │   Siri · Live Activity · app ──▶ FieldActions (unchanged)           │
 └──────────────────────────────────────────────────────────────────────┘
```

The watch sends **requests** and shows **state**, and nothing else. Every rule, every sentence and every record still comes from `FieldEngine` on the phone, so the watch can't drift from Siri or the lock screen. This is the "one action layer" from `docs/architecture.md`, extended by one more door.

### 1.2 Wire protocol (TreeFarmKit `Watch/`)

`WatchLink.swift` already has `WatchRequest` (with `issuedAt`), `WatchReply`, `WatchState`, `WatchOutbox` and `WatchTiming`. The watch work changes it as follows. Slice 0 makes these changes, with tests (section 8).

- **Transport: `sendMessageData` for all live traffic, in both directions.** It carries `Data`, which is `Sendable`, so no `[String: Any]` crosses an isolation boundary under Swift 6. Every message is a `WatchEnvelope { v: Int; message: WatchMessage }` encoded with `JSONCoding`. `WatchMessage` is `.request(WatchRequest)`, `.reply(WatchReply)`, `.state(WatchState)` or `.workoutSummary(WorkoutSummary)`. `WatchWire.version = 1`. [WC-R1, WC-R8]
- **State: `updateApplicationContext(["tc.state": Data, "v": 1])`** after every change, so a watch that wakes up later always gets the latest. It is coalesced over 250 ms. When `isReachable`, the phone also sends `.state` with `sendMessageData` (no reply) so the screen updates at once. [WC-F9, WC-R1]
- **Complication pushes:** on a phase change made on the phone, `transferCurrentComplicationUserInfo` carries a `.state` envelope (section 1.3 step 6). It arrives on the watch in `session(_:didReceiveUserInfo:)` and is handled exactly like a context. [SYS-R7]
- **No other `transferUserInfo` in v1.** The Simulator doesn't support it, and its delivery time on iOS is undocumented. [WC-F8, WC-F10]
- **No workout mirroring as a channel.** A suspended iPhone app gets mirrored data only every few minutes. Mirroring also has a 26.x regression (code 554) and doesn't run in simulators. [WC-F16, HK-F9, HK-R12]

**Changes to the existing types:**

| Type | Change | Why |
|---|---|---|
| `WatchRequest` | add `userId: UUID?` (the person the watch believed was signed in) and `shiftId: UUID?`. For `.clockIn`, `shiftId` is a **new UUID the watch mints** for the shift it is about to show; the phone creates the shift with that id. For the shift-scoped commands (`clockOut`, `startBreak`, `endBreak`, `markRow`, `markTrees`, `addShiftNote`, `cancelShift`) it is the open shift's id **in the watch's displayed state** when the tap was made. It is nil for questions, `refresh` and `undo` | Queued taps must never apply to someone else, or to a later shift than the one they were made in |
| `WatchReply` | add `state: WatchState?`, `appliedAt: Date?` and `keepQueued: Bool`. Add `static func unreadable(_ speech: String) -> WatchReply` with `requestId = UUID(uuid: UUID_NULL)` and `keepQueued: true`, for an envelope the phone can't decode. The courier matches a reply to its request by the `sendMessageData` call, not by `requestId` | The watch updates when its own tap is answered. `keepQueued` means "couldn't run now, try later" (phone not yet unlocked after a reboot, store error, protocol too new). Otherwise the request leaves the outbox whatever the answer. [WC-R1, WC-P3] |
| `WatchState` | add `epoch: UUID`, `revision: Int`, `userId: UUID?`, `shiftId: UUID?`, `shiftStart: Date?`, `lastClosedShift: ClosedShift?` (`shiftId`, `start`, `end`, `worked`, `trees`), `appliedRequestIds: [UUID]` (the last 50), `hadLunchToday: Bool`, `pacePerHour: Double?`, `farmTimeZone: String` and `usualStart: DateComponents?` (hour and minute: the median start of the last 10 shifts). `nextRows` grows to **up to 40** chips, about 6 KB. The UI shows 3 and Siri suggests the first 10; the rest let the watch keep marking while the phone is away. Add `func supersedes(_ old: WatchState?) -> Bool` = `old == nil || epoch != old!.epoch || revision > old!.revision` | Ordering that survives a reinstall [WC-P9], workout alignment [HK-P2, HK-R3], clearing the outbox after a lost reply [WC-R2], the Action button's pause kind (4.2), Smart Stack relevance (4.3) |
| `WatchOutbox` | refuses `.undo` and `.markNextRow`. Past the limit (200) it drops the oldest **row marks** first and never drops `clockIn`, `clockOut`, `startBreak`, `endBreak` or `cancelShift`. Adds `acknowledge(_ ids:)` and `removeLast()` | Replay safety [WC-F15, WC-P5, WC-P18] |
| `WatchTiming` | adds `effectiveTime(issuedAt:receivedAt:notBefore:)` = `min(max(issuedAt, notBefore ?? .distantPast), receivedAt)` and `notBefore(for: FieldCommand, state: FieldState) -> Date?` (below) | A late tap can't land before something already recorded, so breaks can't overlap and a break can't end before it started |
| `FieldCommand` | adds `.cancelShift(UUID)`: soft-deletes the open shift (`deletedAt`) when it has no marks and no breaks and the command's event time is within 5 min of its start. Otherwise it fails: "That shift already has work on it. Change it in the Log." Undo stays as it is | "Undo clock-in" on the watch (3.4) |
| `Clock.clockIn` / `FieldEngine.perform` | `Clock.clockIn` gains `id: UUID = UUID()`. `FieldEngine.perform` gains `newShiftId: UUID? = nil`, passed to it for `.clockIn` | The phone creates the shift with the watch's minted id |

**`WatchTiming.notBefore(for:state:)`** is pure and tested on its own:

| Command | `notBefore` |
|---|---|
| `clockOut`, `startBreak`, `endBreak`, `markRow`, `markTrees`, `addShiftNote`, `cancelShift` | the **latest** of: the open shift's start, every break's start and every break's end in that shift. An open break's start counts, so a queued `endBreak` or `clockOut` can't end a break before it began |
| `clockIn` | the end of the person's latest closed shift (nil if there is none) |
| anything else | nil |

`Clock.clockIn`, `Clock.endBreak` and `Clock.clockOut` don't check ordering themselves (they only check open or closed), so this clamp is the only thing that keeps a watch tap from saving an invalid shift. Tests: open break, a closed shift before a clock-in, no shift at all.

**New pure types** (TreeFarmKit `Watch/`, tested with `swift test`):

- `WatchInbox`: the phone's ledger of answered requests, from `WatchRequest.id` to `WatchReply`, **stored with `state = nil`** so 500 entries stay small. It keeps the last 500 entries or 7 days. A retried request gets the saved reply back with a **fresh** state and **does not run again**. It also keeps `shiftAliases: [UUID: UUID]`: when a watch `clockIn` with minted id M is refused because shift S is already open, the desk records M → S, and later requests tagged M act on S. [WC-F15, WC-R2]
- `WatchConfirm.question(for: FieldCommand, state: WatchState, now: Date) -> String?`: the watch's own copy of `FieldEngine.confirmation`, built from `WatchState`. It asks before clock-out ("You've worked 7 h 12 min today. Clock out?") and before marking a row more than 5 rows away or in another block. A test checks that its text equals `FieldEngine.confirmation` for the same situation. It needs **no round trip**, so it works with the phone out of reach. [UI-F17, UI-R8]
- `WatchPrecheck.refusal(for: FieldCommand, state: WatchState?) -> String?`: catches obvious failures from the cached state so a command that's bound to fail isn't queued while the phone is away. With **no state at all** it refuses every command with "Open Time Card on your iPhone once." Otherwise it uses `Speech` text ("You're not clocked in."). It is used **only when the phone is unreachable**. When the phone is in reach, the phone decides.
- `WatchOptimism.apply(_ command: FieldCommand, shiftId: UUID?, to: WatchState, at: Date) -> WatchState`: the predicted state. A mark drops the chip it marked, a break changes the phase, a clock-in opens a shift with the minted `shiftId`, `cancelShift` returns to off the clock, and so on. It doesn't change `epoch` or `revision`.
- `WatchStateBuilder.build(...) -> WatchState`: builds the state from `FieldState` on the phone. `WatchState.signedOut(epoch:revision:now:)` covers the signed-out case.
- `WatchDisplay`: every string and glyph name the watch app, the complications and the Live Activity's small layout show ("Working", "Lunch", "Row 14 done", "Block 2 · 38 trees", "Out of rows the watch knows. Bring your phone closer.", `leaf.fill`, `cup.and.saucer.fill`, `pause.fill`). It is tested once, like `Speech`.
- `ResumeOnce<T>`: one per `send`. A `Mutex` (or `OSAllocatedUnfairLock`) around an optional `CheckedContinuation`. `resume(returning:)` and `resume(throwing:)` take the continuation out under the lock, so the first caller wins and later callers do nothing.
- `WatchTransport` (protocol) and `WatchCourier` (actor). See 1.5.
- `WorkoutSummary` (slice 0, fully defined with a round-trip test), `WorkoutLocal`, `WorkoutInputs` and `WorkoutPlan.reconcile(...)`. See section 2.

### 1.3 The phone side: `PhoneWatchBridge` and `WatchDesk`

`iOS/App/Watch/PhoneWatchBridge.swift`, `@MainActor`. `AppModel` owns it as `let watch: PhoneWatchBridge`. The decisions live in `WatchDesk` (TimeCardCore), which the bridge calls.

1. **Activation happens in `AppModel.init`, not in a view.** A watch message can launch the iPhone app in the background with no scene, and the existing `WindowGroup .task { await model.start() }` would never run. [WC-F12, WC-P6]
2. **`AppModel.start()` becomes safe to call concurrently first.** Today a second caller returns early while `session.start()` is still loading, and gets "Open Time Card to sign in." The fix keeps a `startTask: Task<Void, Never>?` that every caller awaits. `IntentRunner` and the bridge both go through it. [WC-F13, WC-P7, WC-R5]
3. **One revision counter.** `WatchDesk.makeState()` builds **every** `WatchState` the phone sends: published, attached to a reply, or signed out. Each call takes the next value of one counter stored in the phone's `KeyValueStore` under `watch.revision`, with `watch.epoch` beside it. The epoch is a UUID made when the counter is first created, so a reinstall, a new phone or a lost store starts a new epoch, and the watch accepts the new states even though their revision is lower (`supersedes`, 1.2). A reply's state and a later publish can never tie or go backwards.
4. **Answering a request:** `WatchDesk.handle(_ data: Data, receivedAt: Date) -> Data`, envelope in and envelope out. Every path returns a reply, so the bridge calls the reply handler **exactly once**. [WC-P3, WC-R8]
   1. **Decode.** If the envelope is undecodable or its version too new: `WatchReply.unreadable("Update Time Card on your iPhone.")`, with the current state attached.
   2. **Inbox.** A hit returns the saved reply with a fresh `makeState()`.
   3. **Signed out:** reply `FieldActions.signedOut` with `keepQueued: true`.
   4. **Wrong person.** For a command, `request.userId == nil` or different from the signed-in person counts as a mismatch: "These taps were for Josh, so they weren't applied." (or "These taps were made before you signed in, so they weren't applied.") with `keepQueued: false`.
   5. **Right shift.** Resolve `request.shiftId` through `WatchInbox.shiftAliases`, then:
      - `clockIn` with an open shift: the engine's refusal ("You're already clocked in since 7:00."), and record the alias minted id → open shift id.
      - `clockIn` whose `issuedAt` is earlier than the end of the person's latest closed shift: "That clock-in at 6:40 was before your last shift ended at 7:10, so it wasn't applied."
      - A shift-scoped command whose shift id isn't the open shift's id: refuse, `keepQueued: false`, naming the shift: "That clock-out was for the shift that started at 7:02, which is already closed, so it wasn't applied." / "Row 14 was marked during the shift that started at 7:02, which is already closed, so it wasn't applied. Fix it in the Log." / with no open shift at all: "You're not clocked in, so that lunch wasn't applied."
   6. **Run it:** `FieldActions.perform(command, at: WatchTiming.effectiveTime(issuedAt:receivedAt:notBefore: WatchTiming.notBefore(for:state:)), newShiftId: request.shiftId if clockIn)`. The **event time** (shift start, break start, `markedAt`) is the effective time. Every record's **`updatedAt` is `receivedAt`**, so the sync rule "newest `updatedAt` wins" isn't fooled by a backdated tap. A pure `SyncRecord.stamped(updatedAt:)` does the stamping, with tests. [WC-F14, WC-P17, WC-R4] The desk **skips `FieldEngine.confirmation`** because the watch already asked (`WatchConfirm`).
   7. **A question:** `FieldActions.answer`. `.pay` is never asked from the watch. **`.refresh`:** no change, just the reply with state.
   8. **Save** the reply to `WatchInbox` with `state = nil`, then return it with `makeState()` attached.
   - **Settings are read on every call** through `settings: () -> WatchSettings`, so turning "Record shifts as workouts" off mid-session shows up in the very next state.
5. **Publishing state.** `publish(reason:)` calls `desk.makeState()`, then `updateApplicationContext`, and also sends `.state` when reachable. It runs from `AppModel.liveSnapshotChanged` (every field action from any door), after `session.start()`, after each sync push or pull, on `sceneBecameActive`, on sign-in and sign-out, on `activationDidComplete`, on `sessionWatchStateDidChange`, and when the Settings toggle changes. It publishes only when `isPaired && isWatchAppInstalled`. [WC-R6]
6. **Complication push.** On a phase change made on the phone while the watch app isn't reachable, call `transferCurrentComplicationUserInfo` with a `.state` envelope if `isComplicationEnabled && remainingComplicationUserInfoTransfers > 0`. That allows at most a handful a day. Never send one per row. With no budget left, nothing is sent; the context still carries the change. [SYS-R7, WC-P13]
7. **Starting the watch workout for a phone clock-in.** When `publish` sees the phase go from off the clock to clocked in, the clock-in **didn't** come through the desk, `recordWorkouts` is on, and the watch is paired with the app installed, it:
   - **first** updates the application context (`HKWorkoutConfiguration` carries no custom data, so the watch reads the shift from the context) [HK-P3];
   - **then** calls `WatchWorkoutLauncher.startShiftWorkout(timeout: .seconds(10))`, which wraps `HKHealthStore.startWatchApp(toHandle:)`. The timeout is there because the completion can hang when the watch is off. [HK-F8, HK-P4, HK-R5]
   - Context delivery is asynchronous, so the watch may launch **before** the new state arrives. Section 2.2's reconcile rules make that harmless. [WC-F9, HK-P3]
8. **Background time.** Hold `UIApplication.beginBackgroundTask` from the moment a request arrives until its reply is sent. [WC-F7]
9. **Watch switch.** Implement `sessionDidBecomeInactive`, and call `activate()` again in `sessionDidDeactivate`. [WC-F1]

### 1.4 The watch side

- **`WatchShiftModel`** (`@MainActor @Observable`, `.shared`) is the only thing the views, intents and workout code talk to. It holds the **confirmed** state (the newest `WatchState` from the phone, accepted only when it `supersedes` the current one), the courier's outbox and in-flight requests, the **displayed** state, the reachability (`.reachable`, `.outOfReach`, `.needsUnlock`, `.neverConnected`), the waiting count and the current toast.
- **The displayed state** is recomputed on every state, outbox or in-flight change:

  ```swift
  displayed = (outbox.pending + inFlight)              // oldest first, no duplicates
      .filter { !confirmed.appliedRequestIds.contains($0.id) }
      .reduce(confirmed) { WatchOptimism.apply($1.command, shiftId: $1.shiftId, to: $0, at: $1.issuedAt) }
  ```

  A context push that arrives while rows 14 and 15 are queued still shows row 16 next. Every view, the complications (`WatchStateFile` saves `displayed`, not the raw phone state) and `WatchConfirm` read `displayed`. `WorkoutPlan` reads the confirmed state plus the requests (section 2.2).
- **`WatchCourier`** (actor) owns the persistent `WatchOutbox`. It saves it as JSON in the App Group container through a `WatchOutboxStore`, after every change. It sends **one request at a time**, oldest first, and waits for each reply.
- **`submit(_ request:, durable: Bool)`:**
  - **Durable** (every command except `.undo`): written to the outbox **first**, then sent. A reply removes it. A lost reply leaves it queued for a retry, which `WatchInbox` makes harmless. In-flight requests are exposed as `inFlight` for the displayed state and for `WorkoutPlan`.
  - **Live only** (`.undo`, questions, `.refresh`): sent directly. When unreachable, `.notSent("Undo needs your phone nearby.")` (or the question's equivalent) and nothing is stored.
  - The badge and "2 waiting" count only outbox items **not in flight**, so a normal in-reach tap never flashes a badge.
- **What's sent for a row.** The watch always sends **`.markRow(chip.rowRef)` for the chip it showed**, never `.markNextRow`. What you see is what gets marked, live or queued, even if Siri or the lock screen moved things meanwhile. Two quick Double Taps mark row 14 and then row 15, because the displayed state has already moved to the next chip. [WC-R3] With **no chip** (Double Tap, the Action button's `MarkNextRowIntent` or Siri's `NextRowIntent`), nothing is queued and the watch says `WatchDisplay`'s line: "Every row in North is shaped." when the state shows `fieldShaped == fieldTotal`, otherwise "Out of rows the watch knows. Bring your phone closer."
- **Optimistic UI.** A tap updates the screen at once and shows a small "sending" dot. The reply then settles it:
  - Success: `.success` haptic and the reply's `lastAction` as a toast ("Row 14 marked").
  - Refused: `.failure` haptic, the screen recomputes from `reply.state`, and the reply's `speech` shows as a toast for 4 s ("Row 14 was shaped by Sam on Oct 16. Next open row is 15.").
  - Queued: `.retry` haptic and the toast "Saved on watch · 2 waiting".
- **Undo.** Undo sends `.undo` live, only when the phone is reachable. While taps are waiting, Undo takes back the **last queued tap** locally ("Took back row 15. It wasn't sent yet."). With nothing queued and the phone away, it says "Undo needs your phone nearby."
- **When the outbox flushes:** after activation, on `sessionReachabilityDidChange(true)`, on `scenePhase == .active`, after every reply, and once a minute while a workout session exists, including a **stopped** one (the session keeps the app running and reachable with the wrist down). [WC-F4, WC-R7, WC-R9]
- **Waiting.** After 3 s with no reply, the button shows "Waiting for phone…" and the request stays in the outbox until it's answered. Nobody knows the real reply timeout. [WC-F7] When `iOSDeviceNeedsUnlockAfterRebootForReachability` is true, the watch says "Unlock your phone once."
- **Lost replies.** Each `WatchState` carries `appliedRequestIds`, and `WatchCourier.acknowledge(state)` clears those from the outbox. [WC-R2]
- **A reply's state arrives with its answer.** `CourierSnapshot.replyState` is the newest state any reply carried, set in the same step that drops the answered request. The model takes it whenever it reads the snapshot, so no change ever shows a flushed clock-in answered while the state held still says off the clock (rule 6 in 2.2 would finish the new shift's workout).
- **Background wakes.** `.backgroundTask(.watchConnectivity)` activates the session and completes only once activation is done, `hasContentPending` is false **and** `await transport.drained()` returns, meaning the model has handled every context and user-info event the transport delivered. Handling saves `displayed` to `WatchStateFile` and reloads the complications when `ComplicationReload.needsReload` says so. [WC-F11, WC-P14]

### 1.5 Swift 6 threading (both sides)

WatchConnectivity and HealthKit have no `Sendable` annotations and call back on their own serial queues. Closures written in `@MainActor` code are inferred `@MainActor` and **trap at runtime** ("Incorrect actor executor assumption"). The compiler doesn't warn. [WC-F2, WC-F3, WC-P1]

- **`WCSessionTransport: NSObject, WCSessionDelegate, WatchTransport, @unchecked Sendable`** (in `iOS/WatchLink/`, compiled into both apps). Every delegate method is `nonisolated`, including `session(_:didReceiveMessageData:replyHandler:)`, `session(_:didReceiveApplicationContext:)` and `session(_:didReceiveUserInfo:)`.
- **Its only shared mutable state** is the events `AsyncStream.Continuation` and a lock-guarded count of delivered-but-unhandled context and user-info events (for `drained()`).
- **`send(_:timeout:)`** makes a `ResumeOnce` per call. The `sendMessageData` reply handler, its error handler and a timeout `Task` all call `resume`. Only the first wins, and the timeout task is cancelled when the send completes. A reply that arrives after the 4 s timeout is ignored instead of resuming a continuation twice (a fatal error). [WC-P2]
- Incoming data goes into **one `AsyncStream<WatchTransportEvent>`**, consumed by **one** `@MainActor` loop on each side. That keeps WatchConnectivity's serial order. No callback gets its own `Task { @MainActor in }`. [WC-P8] The reply handler travels inside `WatchReplySink` (an `@unchecked Sendable` box holding an `@Sendable (Data) -> Void`).
- HealthKit's `HKWorkoutSessionDelegate` and `HKLiveWorkoutBuilderDelegate` are `nonisolated`. They yield into an `AsyncStream<WorkoutDriverEvent>`, which `ShiftWorkout` consumes on the main actor. [HK-P8]
- **`ShiftWorkout` is never reentrant.** It owns one `AsyncStream<WorkoutInput>` consumed by a single main-actor loop with a `running` flag. `reconcile(...)`, `handleLaunch()`, `recoverIfNeeded()` and `recordAgain()` only **yield** to it. The queue keeps `.recover`, `.phoneLaunch` and `.recordAgain` in order, and coalesces `.inputs` to the newest one. `.recover` always runs first: the loop doesn't take any other input until the launch-time recovery has finished. So two quick changes can't start two sessions, and a `startWatchApp` launch can't race recovery. Starting over an existing or orphaned session is the reported WatchConnectivity-reachability breaker. [HK-P10]
- Watch targets set `SWIFT_VERSION: 6.0` and `SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated`, matching the iOS code, which marks `@MainActor` explicitly. [WC-R11]

---

## 2. The workout

### 2.1 Configuration

- `HKWorkoutConfiguration`: `activityType = .other` and `locationType = .outdoor`. There's no gardening or occupational type, and `.other` is Apple's catch-all. [HK-F3] No CoreLocation and no route builder. On the first device run, check that no location indicator appears.
- Onboarding tells people how calories are counted with Apple's wording for `.other`: "you earn the calorie equivalent of a brisk walk anytime sensor readings are unavailable." [HK-F3, HK-R2]
- The **watch owns the session**: it's created only on the watch, in the foreground, or from `handle(_ workoutConfiguration:)`. [HK-F5, HK-P1]

### 2.2 Lifecycle by event and source

`ShiftWorkout` (watch, `@MainActor`) never decides on its own. On each input it asks the pure `WorkoutPlan.reconcile(inputs:local:now:)` what to do and does exactly that. [HK-R1]

- `WorkoutInputs`: `confirmed: WatchState?` (the phone's newest state, no optimism), `outbox: [WatchRequest]`, `inFlight: [WatchRequest]`, `refusedClockIns: [UUID]` (minted shift ids of watch clock-ins the phone refused, the last 10).
- `WorkoutLocal`: `phase` (`.none`, `.running`, `.paused`, `.stopped`, `.ended`), `shiftId`, `origin` (`.watchTap`, `.phoneLaunch`, `.actionButton`, `.recovered`), `startedAt`, `stoppedAt`, `syncIdentifier`, `stoppedUnexpectedly`, `lastFinishedShiftId`.
- Steps: `.start(at:shiftId:origin:)`, `.tag(shiftId:)`, `.pause`, `.resume`, `.stop(at:)`, `.finish(at:)`, `.discard`, `.notifyStuckClockOut`. An empty list means do nothing.
- "Pending" below means in `outbox` **or** `inFlight`.

**What each event does:**

| Event | Where it came from | What the phone does | What the watch workout does |
|---|---|---|---|
| **Clock in** | Watch: button, Double Tap, watch Siri (`ClockInIntent` opens the app) or the Action button (`StartShiftWorkoutIntent`) | Applies `.clockIn` at `issuedAt` (live or queued), creating the shift with the watch's minted id | **Starts at once** in the foreground, tagged with the minted id: `startActivity(with: issuedAt)` and `beginCollection(at: issuedAt)`, before any reply. If the phone refuses because a shift is already open, retag to that shift. If it refuses for any other reason, **discard** [HK-R4] |
| **Clock in** | Phone: app, phone Siri, Live Activity | Applies `.clockIn` now. The bridge updates the context, then calls `startWatchApp` (10 s timeout) | `handle(_ workoutConfiguration:)` yields `.phoneLaunch`. If a session exists, nothing. If the confirmed state already shows the shift: start tagged at `shiftStart` if it's no more than 5 min ago, else at **now**. If the state is stale (still off the clock): start **untagged at now** with origin `.phoneLaunch`, and tag when the state arrives. Never backdate further: `.other` would invent brisk-walk calories for time the watch never measured. [HK-P6, HK-R5] If the launch fails or times out, start the next time the app comes forward, with the same 5-minute rule and the toast "Recording from 7:14" |
| **Undo clock-in** | Watch (3.4) | Applies `.cancelShift(shiftId)` | **Discard** at once |
| **Lunch / break** | Any | Applies `.startBreak` | `pause()` as soon as the watch knows: immediately for a watch tap, otherwise when the state arrives. `pause()` takes no date, so Health's active time can differ from paid time by seconds. **The time card is the truth.** [HK-F2, HK-P5] |
| **Back to work** | Any | Applies `.endBreak` | `resume()`, with the same timing as pause |
| **Clock out** | Watch (after the `WatchConfirm` dialog), live or queued | Applies `.clockOut` at `issuedAt` | **Stop now, finish on acknowledgement:** `session.stopActivity(with: issuedAt)` at once, so the end date is exact. The session then **stays in `.stopped`**, which still counts as an active session, so the app keeps running and reachable and the outbox keeps flushing. When the clock-out is answered (a reply, or its id in `appliedRequestIds`, refused or not), run the finish sequence at `stoppedAt`. **After 60 minutes** without an answer, finish anyway and post the local notification "Open Time Card near your iPhone to finish clocking out." That reminder is **scheduled with the system at the stop** (so it comes even if the session ends from outside or the app is gone by then) and taken back once the clock-out is answered. Meanwhile a full-width banner reads **"Clock-out waiting for iPhone"** |
| **Clock out** | Phone, Siri on the phone, or a sync | Applies `.clockOut` | Finish at `lastClosedShift.end` (rule 6 below) |
| **Shift edited on the phone** (start time changed) | Phone | Saves | Nothing. The workout isn't stretched to match. [HK-P6] |

**`WorkoutPlan.reconcile` rules, checked in order (the first that matches decides):**

1. **Recording off** (`confirmed.recordWorkouts == false`): a running, paused or stopped session → `.finish(at: stoppedAt ?? now)`. No new sessions.
2. **Stopped, waiting for a clock-out:** local `.stopped` and the clock-out for `local.shiftId` is no longer pending → `.finish(at: stoppedAt)`. Still pending and `now − stoppedAt ≥ 60 min` → `.finish(at: stoppedAt)`, `.notifyStuckClockOut`. A pending `clockIn` for a **different** shift also finishes it first, then rule 4 starts the new one.
3. **Pending clock-out** for `local.shiftId` while running or paused → `.stop(at: clockOut.issuedAt)`.
4. **Pending clock-in** with minted id M: no session → `.start(at: issuedAt, shiftId: M, origin: .watchTap or .actionButton)`. A session that is untagged → `.tag(M)`. Otherwise nothing. **A pending clock-in always prevents a discard.**
5. **Pending `cancelShift(local.shiftId)`** → `.discard`.
6. **Confirmed state off the clock**, a session running or paused, nothing clock-in-related pending:
   - `lastClosedShift.shiftId == local.shiftId`, or the session is untagged and `lastClosedShift.end` falls within `[startedAt, now]` → `.finish(at: lastClosedShift.end)`, clamped to no earlier than the session's start and no later than now.
   - `local.shiftId` is in `refusedClockIns` → `.discard`.
   - `confirmed.updatedAt > local.startedAt` (the phone knew about this session and still says off the clock) → `.finish(at: now)`, which discards on its own when under 2 minutes.
   - Otherwise the state is older than the session (a stale context right after a phone launch) → nothing.
7. **Confirmed state on the clock** with shift S:
   - No session, `lastFinishedShiftId != S` and not `stoppedUnexpectedly` → `.start(at:)` with the 5-minute rule, tagged S, origin `.phoneLaunch` or `.recovered`.
   - Untagged session, or a session tagged with a minted id in `refusedClockIns` (the phone already had a shift open) → `.tag(S)`.
   - Session tagged with `lastClosedShift.shiftId` (the phone clocked out and in again) → `.finish(at: lastClosedShift.end)`, then start S.
   - Then match the phase: on lunch or a break and running → `.pause`. Working and paused → `.resume`.

**The finish sequence** (Apple's current order) [HK-F1, HK-R6]:

1. `session.stopActivity(with: end)` unless it is already stopped, then wait for `.stopped` in `workoutSession(_:didChangeTo:from:date:)`.
2. `builder.endCollection(at: end)`.
3. Discard if the active duration (`builder.elapsedTime`) is **under 2 min**: `builder.discardWorkout()` and `session.end()`, with no summary. A mistaken clock-in leaves no junk workout. [HK-P14]
4. Otherwise `builder.addMetadata(...)`, `builder.finishWorkout()` (which saves the `HKWorkout`), then `session.end()`.
5. Build the `WorkoutSummary`, set `lastFinishedShiftId`, and show the summary screen (2.6).

### 2.3 Metadata [HK-F4, HK-R7]

| Key | Value |
|---|---|
| `HKMetadataKeyWorkoutBrandName` | `"Time Card shift"` |
| `"TimeCardShiftID"` (custom) | the shift UUID as a string, when known |
| `HKMetadataKeySyncIdentifier` | a UUID made when the session starts and saved with it, so a recovered session can't be saved twice |
| `HKMetadataKeySyncVersion` | `1` |
| `HKMetadataKeyTimeZone` | `WatchState.farmTimeZone` |
| `HKMetadataKeyIndoorWorkout` | `false` |

**Health data never leaves the person's devices.** Heart rate and calories aren't in any `SyncRecord` and never reach the farm server, so an employer never sees a worker's health data. [HK-P16]

### 2.4 Permissions, Info.plist and entitlements [HK-F6, HK-F7, HK-R10]

- **Watch:** `requestAuthorization(toShare: [.workoutType()], read: [heartRate, activeEnergyBurned])`. Nothing more. [HK-F16]
  - **When:** on the watch's first launch, if `recordWorkouts` is on. A full-screen card says "Record shifts as workouts" with an **Allow Health** button. The prompt has to happen early, because the Action button only launches the app until authorization has been requested once. [UI-F10, HK-F7]
  - **If denied:** shifts work normally with no workout. The Today page shows "Workouts off · Allow Time Card in the Health app on your iPhone."
  - **Notifications:** the same card then asks `UNUserNotificationCenter` for `[.alert, .sound]`, worded "Remind me if a clock-out gets stuck." Only the 60-minute stuck clock-out (2.2) uses it. The reminder is scheduled with the system at the stop, for 60 minutes later, and taken back once the clock-out is answered.
- **iPhone:** gets the HealthKit entitlement and both usage strings, because it calls `startWatchApp`. It **doesn't ask for authorization**, unless the device test shows that `startWatchApp` fails without it. In that case it asks for share `[workoutType]` only, from the Settings toggle. [HK-R10]
- **Usage strings** (the same in both apps):
  - `NSHealthShareUsageDescription`: "Time Card shows your heart rate and calories during a shift. They stay on your iPhone and Apple Watch and are never sent to the farm."
  - `NSHealthUpdateUsageDescription`: "Time Card saves each shift as an Other workout in Health, paused during lunch and breaks."
- **Watch background modes:** `WKBackgroundModes: [workout-processing]`. Without it the session dies when the app goes to the background (`errorUserExitedWorkoutSession`). Also `UIBackgroundModes: [audio]`, which Apple asks for when an app plays haptics during a workout. [HK-F5, UI-F7]
- **Entitlement:** `com.apple.developer.healthkit: true` on the watch app and the iPhone app. The free Personal Team allows HealthKit, App Groups and Background Modes. [HK-F6, SYS-F12]

### 2.5 Crash recovery and sessions ended from outside the app

- **Recovery:** `@WKApplicationDelegateAdaptor(WatchAppDelegate.self)` implements `handleActiveWorkoutRecovery()`, which yields `.recover`. `ShiftWorkout` calls `HKHealthStore.recoverActiveWorkoutSession`, makes a **new** `HKLiveWorkoutDataSource`, reattaches both delegates, restores `WorkoutLocal` (saved to the App Group on every change, including `stoppedAt`), and reconciles. A recovered `.stopped` session goes straight back to rule 2. [HK-F10, HK-R8]
- **At every launch, recovery runs before any start.** The input queue enforces it (1.5). Starting a fresh session over an orphaned one has been reported to break WatchConnectivity reachability. [HK-P10]
- **Ended from outside:** watchOS has no system button that ends another app's workout session. It ends when another workout starts (`errorAnotherWorkoutSessionStarted`), on a force-quit or a crash, on a battery shutdown, or on an error. [HK-F11]
- **A stopped session ended from outside** (a watch clock-out still waiting for the phone) is a finished shift, not a lost recording: it finishes at `stoppedAt` with its summary, offers **no** Record again, and keeps the stuck-clock-out reminder already scheduled with the system. `live.recording` goes to `.idle` while `live.waitingClockOut` stays true until the phone answers.
- **A running or paused session ended from outside:**
  - Save what was collected (finish at now if the builder is still usable).
  - **Keep the shift on the clock.** It is never a clock-out. [HK-P11]
  - Set `stoppedUnexpectedly` and show the banner "Recording stopped" with a full-width **Record again** button. That yields `.recordAgain`, which starts a new session with a new sync identifier and the same shift id.
  - No automatic restart after an "another workout" error. After a shutdown with no recoverable session, it restarts at now with the toast "Recording from 2:14".

### 2.6 The shift summary

- **When it shows:** on the watch right after a finish that the watch drove. After a clock-out made on the phone, it shows the next time the watch app is opened within 1 hour. After that, it becomes the "Last shift" line on the off-the-clock screen until the next clock-in.
- **What it shows:**
  - From `lastClosedShift`: worked time and trees (or, while the clock-out still waits, the watch's own count with "waiting for iPhone").
  - From the builder: average and maximum heart rate, active kcal and active duration.
  - It **never shows pay**.
- **Sending it to the phone:** `WorkoutSummary` goes to the phone as `.workoutSummary` (`sendMessageData`, no reply). If the phone is out of reach, it waits in a one-slot `pendingSummary` file and goes with the next outbox flush. The phone keeps it in its local store under `watch.workout.<shiftId>`. It is for the worker only and never syncs. Showing it in the Log is a later follow-up. [HK-R15]

### 2.7 When `recordWorkouts` is off or Health is denied

There's no session, so the system returns to the watch face after about 2 minutes. Background haptics stop, and the watch is reachable only while the app is on screen. Everything still works through the outbox. Onboarding suggests Settings › General › Return to Clock › Time Card › **1 hour**. **We never run a session only to keep the app on screen**, because that risks App Review guidelines 2.5.1 and 2.5.4. [UI-P5, HK-P15]

**The Action button without workouts:** the first press still clocks in (`StartShiftWorkoutIntent.perform` runs `.clockIn`) and opens the app, but starts no session. With no session there's no "next action", so later presses only open the app. The iPhone's Apple Watch settings and the watch's Today page say "Action button needs workouts on." [UI-F10]

### 2.8 Battery

- The SE 3 is rated for 7 hours of workout tracking, so a 9-hour shift may not fit. [HK-F14] At clock-in, the watch sets `WKInterfaceDevice.current().isBatteryMonitoringEnabled = true` (otherwise `batteryLevel` reads −1), and if `batteryLevel < 0.5`, shows "Battery 42%. Charge at lunch to last the shift."
- Low Power Mode keeps recording heart rate, but **turns off Always On and Double Tap**. The Today page shows "Low Power: Double Tap is off". [UI-P1, HK-P13]
- Updates stay cheap: `Text(timerInterval:)` instead of per-second timers, WatchConnectivity traffic only on state changes, and no sub-second animation. [HK-R14]

---

## 3. Screens and input for gloves

### 3.1 Structure

```
NavigationStack
└─ (signed out / never connected) → SetupScreen
└─ (off the clock)               → OffClockScreen            (one page, no scrolling)
└─ (on the clock)                → TabView(.page) horizontal, opens on Now:
       [ Controls ]  ←  [ Now ]  →  [ Today ]
```

- **The pages are horizontal, as in Apple's Workout app.** Vertical pages and scroll views fight with Double Tap, which takes over scrolling and paging. [UI-F2, UI-F4, UI-P2, UI-R1]
- **Only Now and OffClock declare the primary action**, and only while they're on screen: `handGestureShortcut(.primaryAction, isEnabled: page == .now && !dialogShown)`.
- **Today is the only page that scrolls**, and it has no primary action.
- **Every wrist raise lands on Now:** after 30 s away, `scenePhase == .active` resets the selection to `.now`.
- **SetupScreen** also carries the Siri note: "Say 'Clock in with Time Card' once and tap Allow. If you said no, Siri on the watch can't be turned back on for Time Card yet." [UI-F12]

**Colors:** fir green (`#1D5B3A`) for working, sap gold (`#B57A12`) for lunch and breaks, and rust for clock-out. On tinted or Liquid Glass faces color is lost, so each phase also has its own **glyph and word**: `leaf.fill` "Working", `cup.and.saucer.fill` "Lunch", `pause.fill` "Break". [SYS-P11]

**Type:**
- Timers use `.system(.largeTitle, design: .rounded).monospacedDigit()` scaled with `@ScaledMetric`, not Plex Mono. The custom font is reported to break `Text(timerInterval:)` in the Smart Stack, and the system font follows Dynamic Type. [SYS-F5]
- Labels use text styles. Text must still fit at 140% enlargement, so `ViewThatFits` shortens it in steps ("Row 14 done" → "Row 14" → "14").
- The Now page **must not scroll**, even on a 40 mm SE 3 at accessibility sizes. If it scrolled, Double Tap would scroll instead of acting. [UI-P13, UI-R11]

**Screen sizes** (points). Mockups and screenshots use the simulators on this Mac (watchOS 26.2): SE 3 40 mm, Series 11 42 mm and 46 mm, Ultra 3 49 mm. 41 mm (176×215) and 45 mm (198×242) Series 7–10 watches fall in the same size classes.

| 40 mm | 42 mm | 44 mm | 46 mm | 49 mm Ultra 3 | 49 mm Ultra 2 (Josh) |
|---|---|---|---|---|---|
| 162×197 | 187×223 | 184×224 | 208×248 | 211×257 | 205×251 |

**Button sizes** (the default control is 44 pt, and these are well above it) [UI-F5]:

| | 40 / 41 / 42 mm | 44 / 45 / 46 mm | 49 mm |
|---|---|---|---|
| Primary (Now and OffClock **Clock in**) | 60 pt tall, full width | 64 pt | 68 pt |
| Controls grid | 56 pt, 2 per row | 60 pt | 62 pt |
| Clock out | 52 pt, full width, rust | 56 pt | 58 pt |
| Undo clock-in, Record again | 48 pt, full width | 52 pt | 54 pt |

### 3.2 Now: working (the primary screen)

```
40 mm · 162×197           42 mm · 187×223              46 mm · 208×248                49 mm · 211×257
╭────────────────────╮   ╭───────────────────────╮   ╭──────────────────────────╮   ╭───────────────────────────╮
│ ⇡2          10:42  │   │ ⇡2             10:42  │   │ ⇡2                10:42  │   │ ⇡2                 10:42  │
│ 🍃 WORKING          │   │ 🍃 WORKING             │   │ 🍃 WORKING                │   │ 🍃 WORKING                 │
│      3:41:07       │   │       3:41:07         │   │                          │   │                           │
│ Block 2 · 38 trees │   │  Block 2 · 38 trees   │   │         3:41:07          │   │          3:41:07          │
│╭──────────────────╮│   │╭─────────────────────╮│   │       worked today       │   │        worked today       │
││  ✓ Row 14 done   ││   ││   ✓  Row 14 done    ││   │    Block 2 · 38 trees    │   │ Block 2 · 38 trees · ♥104 │
│╰──────────────────╯│   │╰─────────────────────╯│   │ ╭──────────────────────╮ │   │ ╭───────────────────────╮ │
│   ● ○ ○   • ● •    │   │    ● ○ ○    • ● •     │   │ │    ✓  Row 14 done    │ │   │ │    ✓  Row 14 done     │ │
╰────────────────────╯   ╰───────────────────────╯   │ ╰──────────────────────╯ │   │ │                       │ │
                                                     │      ● ○ ○    • ● •      │   │ ╰───────────────────────╯ │
                                                     ╰──────────────────────────╯   │       ● ○ ○    • ● •      │
                                                                                    ╰───────────────────────────╯
 ⇡2     queue badge (iphone.slash + count of taps waiting, not in flight); tap → Queue sheet
 ● ○ ○  crown chips: rows 14 / 15 / 16 (selected filled)      • ● •  page dots (Controls / Now / Today)
 40 and 42 mm drop "worked today" and the heart rate; 49 mm adds ♥ and a taller button.
```

- **Timer:** `Text(timerInterval: snapshot.timerStart...Date.distantFuture, countsDown: false)`. It ticks by itself, also in Always On.
- **Primary button:** labelled from the selected chip and carrying `.handGestureShortcut(.primaryAction)`. **Double Tap = mark the shown row.** [UI-F1, UI-F2, UI-R2]
- **Digital Crown:** a focusable chip selector over the first 3 `nextRows`, using `digitalCrownRotation(detent: $chipIndex, from: 0, through: chips.count - 1, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true, onIdle:)`.
  - Turning it changes the button to "Row 15 done", and pressing or Double Tapping sends `.markRow` for that chip.
  - Six seconds after `onIdle`, it snaps back to the first chip.
  - Focus is set again with `@FocusState` on every appear, because focus is fragile in TabViews.
  - VoiceOver gets `accessibilityAdjustableAction` and the spoken value "Row 15 in block 2".
  - The crown does nothing else on the shift screens. [UI-F3, UI-R3, UI-P11]
- **No chips left:** when the state shows `fieldShaped == fieldTotal`, the button reads "Field done" and is disabled, and the primary action moves to nothing. When chips ran out only because the phone is away (more than 40 rows marked offline), it reads "Out of rows the watch knows" with "Bring your phone closer" under it, also disabled.

### 3.3 Now: lunch or break

```
46 mm
╭──────────────────────────╮
│                   12:13  │
│ ☕ LUNCH · since 12:01    │   gold
│                          │
│         0:12:40          │   break timer: Text(breakStart, style: .timer)
│     3:41 worked today    │   frozen workedSoFar
│ ╭──────────────────────╮ │
│ │   ▶  Back to work    │ │   primary action (Double Tap)
│ ╰──────────────────────╯ │
│          • ● •           │
╰──────────────────────────╯
```

A break looks the same, with `pause.fill` "BREAK", plus the reason when there is one. The crown is inactive.

### 3.4 Off the clock

```
46 mm, off the clock                46 mm, first 2 min after a watch clock-in (Now)
╭──────────────────────────╮        ╭──────────────────────────╮
│ Time Card          6:58  │        │ 🍃 WORKING          7:01  │
│ Dull's Tree Farm · North │        │         0:02:14          │
│ ╭──────────────────────╮ │        │ ╭──────────────────────╮ │
│ │                      │ │        │ │    ✓  Row 14 done    │ │  primary action
│ │     ▶  Clock in      │ │        │ ╰──────────────────────╯ │
│ │                      │ │        │ ╭──────────────────────╮ │
│ ╰──────────────────────╯ │        │ │   ↶  Undo clock-in   │ │  52 pt, plain, 2 min only
│ Starts: Block 2 · Row 14 │        │ ╰──────────────────────╯ │
│ Last shift 8:12 · 412 tr │        ╰──────────────────────────╯
╰──────────────────────────╯
 Clock in: 64 pt (the Primary row of 3.1), fir green, primary action (Double Tap).
 "Last shift 8:12 · 412 trees" shortens through ViewThatFits; after a split shift it reads "6.5 h today".
 With a clock-out waiting, a full-width gold banner "Clock-out waiting for iPhone" sits above Clock in.
```

- **Clock In is the off-clock primary action, and Double Tap fires it.** UI-P1 says to map only undoable actions to Double Tap, and `FieldEngine.clockIn` has no undo entry. So a watch clock-in **is** made undoable: for 2 minutes the Now page shows **Undo clock-in**, which sends the durable `.cancelShift(shiftId)` (it works while queued, too). The phone soft-deletes the shift, and the workout is discarded at once (rule 5). A shears pinch while the off-clock screen is up costs one button press, not a trip to the phone's Log.
- **Clock Out is never the primary action, anywhere.** [UI-F2, UI-P1]
- **Signed out:** "Open Time Card on your iPhone to sign in." with no buttons.
- **Phone never reached:** "Open Time Card on your iPhone once." with a Try again button.

### 3.5 Controls (left page)

```
46 mm (working)                      46 mm (on lunch)
╭──────────────────────────╮         ╭──────────────────────────╮
│ ╭──────────╮╭──────────╮ │         │ ╭──────────────────────╮ │
│ │ ☕ Lunch  ││ ⏸ Break  │ │         │ │   ▶  Back to work    │ │
│ ╰──────────╯╰──────────╯ │         │ ╰──────────────────────╯ │
│ ╭──────────╮╭──────────╮ │         │ ╭──────────╮╭──────────╮ │
│ │ ↶ Undo   ││ 💧 Lock  │ │         │ │ ↶ Undo   ││ 💧 Lock  │ │
│ ╰──────────╯╰──────────╯ │         │ ╰──────────╯╰──────────╯ │
│ ╭──────────────────────╮ │         │ ╭──────────────────────╮ │
│ │   ■  Clock out       │ │         │ │   ■  Clock out       │ │
│ ╰──────────────────────╯ │         │ ╰──────────────────────╯ │
╰──────────────────────────╯         ╰──────────────────────────╯
```

- **Break** starts `.startBreak(.break, reason: "")`. A reason can only be given by voice on the phone.
- **Lock** calls `WKInterfaceDevice.current().enableWaterLock()`. This "rain lock" stops phantom taps from wet needles or sap. It's shown only while a workout session runs, the app is in the foreground, and `waterResistanceRating != .ipx7` (so `.wr50` and the Ultra's `.wr100` both get it). The pure gate is `WaterLockGate.isAvailable(rating:sessionActive:foreground:)`. The person unlocks it by turning the crown. [UI-F9, UI-R9]
- **Undo** follows 1.4.
- **Clock out** opens the confirmation (3.8).
- **No primary action on this page.**

### 3.6 Today (right page, scrolls)

```
46 mm
╭──────────────────────────╮
│ Today                    │
│ 6:40 worked · 212 trees  │
│ 34 trees an hour         │
│ North ▓▓▓▓▓▓▓░░░ 62%     │   fieldShaped / fieldTotal
│ ♥ 104 bpm · 612 kcal     │   live from the builder
│ ● Recording shift workout│   or "Workouts off · …" / "Recording stopped [Record again]"
│ ──────────────────────── │
│ iPhone: in reach         │   or "out of reach · 2 waiting" / "unlock once"
│ 2 taps waiting · 10:31   │   → Queue sheet
│ Low Power: Double Tap off│   only when it applies
╰──────────────────────────╯
```

There's no pay, ever, because bystanders can see a wrist. `WatchState` doesn't carry it.

### 3.7 Queue indicator and sheet

- **Badge:** the badge on Now (`iphone.slash` with the count) shows only when taps are waiting (outbox items not in flight). It is not `.privacySensitive()` and stays visible in Always On.
- **Sheet:** lists each waiting tap with its time, for example "10:31 · Row 14 done" and "10:35 · Lunch". Under it: "These will count at the time you tapped once your iPhone is back." If `dropped > 0`, it adds "3 older row taps couldn't be kept."
- **After the flush:** refused items stay listed for 1 hour with the phone's sentence, for example "10:35 Lunch: You're already on lunch since 10:34." or "Row 14 was marked during the shift that started at 7:02, which is already closed…". The person can see what didn't apply.

### 3.8 Confirmations

```
46 mm
╭──────────────────────────╮
│ You've worked 7 h 12 min │
│ today. Clock out?        │   WatchConfirm text (same as Siri)
│ ╭──────────────────────╮ │
│ │   Yes, clock out     │ │   rust
│ ╰──────────────────────╯ │
│ ╭──────────────────────╮ │
│ │   Keep working       │ │
│ ╰──────────────────────╯ │
╰──────────────────────────╯
```

- `confirmationDialog`. **Double Tap is disabled while it shows**, so a pinch can never confirm a clock-out.
- A row far away (a Siri "mark row 40") asks "Row 40 in block 2? That's 26 rows ahead." the same way.

### 3.9 Shift summary

```
46 mm
╭──────────────────────────╮
│ ✓ Shift done             │
│          8:12            │
│  worked · 412 trees      │
│ ♥ avg 104 · max 151      │
│ 🔥 1,120 kcal · 7:41 act. │
│ ╭──────────────────────╮ │
│ │        Done          │ │   primary action
│ ╰──────────────────────╯ │
╰──────────────────────────╯
```

- One screen, `ShiftDoneScreen`, worded by `WorkoutSummaryContent` (which also gives VoiceOver "Average heart rate 104, maximum 151" and "1,120 calories, 7 hours 41 minutes active"). It never scrolls, because Double Tap is Done: on a small watch or at large text it drops the energy line, then the heart line.
- While the clock-out still waits for the phone, the banner "Clock-out waiting for iPhone" takes the title's place and the trees line reads "412 trees · waiting for iPhone".
- Done dismisses it on the model and in the workout's summary slot.

### 3.10 Toasts

- **Position and size:** they sit over the bottom of the timer area and never over the primary button. Two lines at most.
- **How long they stay:** 2.5 s for success, 4 s for a refusal, and 2.5 s for "Saved on watch".
- **Wording:** `WatchReply.lastAction` when it succeeded, otherwise `speech`, cut with `lineLimit(2)` and ending in "…". The full sentence goes to VoiceOver.

### 3.11 Haptics (`WatchHaptics`, mapped to meaning) [UI-F8, UI-R4, UI-P6]

| Event | `WKHapticType` |
|---|---|
| Clock-in sent or workout started | `.start` |
| Clock-out, workout stopped | `.stop` |
| Phone confirmed a tap | `.success` |
| Phone refused a tap | `.failure` |
| Tap queued (phone out of reach) | `.retry` |
| Break started / back to work | `.directionDown` / `.directionUp` |
| Crown detent | built into `digitalCrownRotation` |

- **One haptic per reply, never one per second.** Calls less than 100 ms apart cancel each other.
- **Heart rate pauses while a haptic plays**, which is one more reason to stay sparse.
- `WKInterfaceDevice.play` works in the background only during a workout session, which every recorded shift has.

### 3.12 Always On [UI-F6, UI-R5, UI-P7]

- When `@Environment(\.isLuminanceReduced)` is true, filled buttons become outlined, chips and secondary text dim, and the timer, phase word and "Row 14" stay bright.
- **Timers:** `Text(timerInterval:)` and `.timer` styles update by themselves. Any `TimelineView` is built from `context.date`, never `Date()`, because the system renders up to 5 minutes ahead.
- **Refresh rate:** the running workout gives a cadence of about 1 Hz. There is no animation shorter than a second.
- **SE 3** has Always On, despite older Apple docs. [UI-P12]

### 3.13 Accessibility

- **One element per timer:** "Worked 3 hours 41 minutes".
- **Spoken button labels:** "Mark row 14 in block 2 shaped".
- **A tap path for everything:** Double Tap turns off under AssistiveTouch, VoiceOver hand gestures or Low Power Mode, so every Double Tap and crown action is also an ordinary `Button`. [UI-F15, UI-R11]

---

## 4. Siri, the Action button, complications, the Live Activity and controls

### 4.1 Siri on the watch

- **The watch app ships its own `AppShortcutsProvider` (`WatchShortcuts`).** App Shortcuts from the iPhone app don't run on the watch. Flexible matching is off there, so phrases must match exactly. With the phone in a pocket, the watch usually answers "Hey Siri". [UI-F12, UI-P8]
- **Display name and aliases:** `CFBundleDisplayName` is "Time Card", and `INAlternativeAppNames` are "Tree Card" and "Tree Farm".
- **The phrase source of truth is `docs/voice-test.md` plus the table below.** `docs/voice-test.md` has the watch's list in its "Apple Watch" section, with the same wording. The phone's `TimeCardShortcuts` keeps its own, wider list (the phone has flexible matching); a watch phrase is always one the phone also understands.
- **The Siri opt-in:** a declined App Shortcuts opt-in on watchOS 26.6 has been reported impossible to re-enable or detect. SetupScreen warns about it (3.1), and the device checklist covers it. [UI-F12]

An app may have at most 10 App Shortcuts, and these are the 10. Every phrase ends in "in \(.applicationName)" and also exists with "with \(.applicationName)":

| # | Intent (watch target) | Phrases | Does |
|---|---|---|---|
| 1 | `ClockInIntent` (`openAppWhenRun = true`, so the workout can start in the foreground and WatchConnectivity is reachable) | Clock in · Punch in · Start work · Start my shift | `.clockIn(fieldId: nil)` with a minted shift id, plus the workout |
| 2 | `ClockOutIntent` | Clock out · Punch out · End my shift · Stop work | `requestConfirmation` with the `WatchConfirm` text, then `.clockOut` |
| 3 | `TakeLunchIntent` | Take lunch · Start lunch | `.startBreak(.lunch, reason: "")` |
| 4 | `TakeBreakIntent` | Take a break · Start a break | `.startBreak(.break, reason: "")` |
| 5 | `BackToWorkIntent` | Back to work · End my break | `.endBreak` |
| 6 | `NextRowIntent` | Next row · Row done · Mark the next row | `.markRow(first chip)`; no chip → the no-chip line (1.4), nothing queued |
| 7 | `MarkRowIntent(row: WatchRowEntity)` | Mark \(\.$row) · \(\.$row) done; with no row: "Mark a row" asks "Which row?" | `.markRow`, with `WatchConfirm` when more than 5 rows away |
| 8 | `UndoIntent` | Undo · Undo that | `.undo` (rules in 1.4) |
| 9 | `StatusIntent` | How long have I worked · How many trees · What row am I on · What's my pace | One spoken answer covering all four. From the phone when reachable (`FieldAnswers`), otherwise from the cache with "as of 10:42" |
| 10 | `AddNoteIntent` | Add a note | `requestValueDialog` dictation, then `.addShiftNote` |

- **`WatchRowEntity`:** its id is `"<blockId>-<row>"` and it displays as "row 14". Its `EntityQuery`:
  - `suggestedEntities()` returns the first 10 chips of the displayed `nextRows`;
  - `entities(for:)` parses ids;
  - `entities(matching:)` (an `EntityStringQuery`) parses a spoken number, so "Mark row 40" builds `RowRef(blockId: nextRows.first.blockId, row: 39)` even when row 40 isn't a chip. With no chips, it returns nothing and Siri says the no-chip line. [UI-F17]
- **Parameterized phrases stay fresh:** the model calls `WatchShortcuts.updateAppShortcutParameters()` whenever the first chip changes.
- **Phone only, on purpose:** moving blocks, tree notes, changing the start time and pay are answered by the phone, by raising the phone or using AirPods. They are left out because of the 10-shortcut cap and because each one is a long dialog.
- **How an intent runs:**
  - It calls `WatchShiftModel.shared.perform(_:source: .siri)` and returns `WatchReply.speech` as its dialog.
  - If the phone is unreachable, it queues the command and says "Saved on your watch. It'll reach your phone when it's back in range."
  - If `WatchPrecheck` refuses (including "Open Time Card on your iPhone once." with no state), it says the refusal and queues nothing. [UI-R7]
- **Off the clock with the app in the background,** `isReachable` is false. Only Clock In opens the app, and the other commands queue or are refused by the precheck. [UI-F13, UI-P5]

### 4.2 The Ultra Action button [UI-F10, UI-R6, HK-F12, HK-R13]

All of these intents live in the **watch app target**, not an extension, and keep the default `openAppWhenRun`. `PauseWorkoutIntent` and `ResumeWorkoutIntent` are AppIntents **protocols**, so our types conform to them under our own names.

| Press | Intent | Does |
|---|---|---|
| First press (Settings › Action Button › Workout › Time Card) | `StartShiftWorkoutIntent: StartWorkoutIntent`, with `@Parameter var style: ShiftWorkoutStyle` (one case `.treeShift`, "Tree shift", subtitle "Clock in and record") and `static var suggestedWorkouts: [StartShiftWorkoutIntent] { [StartShiftWorkoutIntent(style: .treeShift)] }` | Within 30 s: `perform(.clockIn)` with a minted id, and the session starts through reconcile with origin `.actionButton`. If the state already shows a shift on the clock, it only starts or attaches the workout and says "Recording your shift." With recording off or Health denied: 2.7 |
| Later presses while working | donated next action `MarkNextRowIntent` (label "Mark Next Row") | `.markRow(first chip)`; no chip → the no-chip line |
| Later presses on lunch or a break | `ResumeWorkIntent` donated instead (label "Resume Work") | `.endBreak` |
| Action + side button | `PauseShiftIntent: PauseWorkoutIntent` | Lunch if `!hadLunchToday`, otherwise a break |
| Action + side while paused | `ResumeShiftIntent: ResumeWorkoutIntent` | `.endBreak` |

- **Donations:** `ActionButtonDonor` donates again on every phase change (`StartShiftWorkoutIntent(style: .treeShift).donate(result: .result(actionButtonIntent: …))`). Only the latest donation counts. With no session (recording off or denied) it donates nothing.
- **The button never clocks out.** Stopping belongs in the UI, and a cuff can press the button by accident. [UI-P9, UI-P11]
- **Test on watchOS 26.1 or later**, since 26.0.x had Action-button bugs.

### 4.3 Complications (watch widget extension) [SYS-F6, SYS-R6, SYS-R7, SYS-R8]

**How the extension gets its data:**
- One `StaticConfiguration`, kind `"timecard.watch.shift"`, supporting all four accessory families.
- Its data is the **displayed** `WatchState` and the waiting count that the watch app writes to the App Group (`WatchStateFile`). **The extension never touches WCSession.** [SYS-P9]
- The timeline is one entry with policy `.never`; the timers tick by themselves. While off-the-clock hours show ("6.5 h today"), a **second entry at the farm's next midnight** reads them as 0 ("IN"), so yesterday's hours never greet the morning. It is still `.never`, so midnight spends no reload. `ComplicationDay` decides the day the hours belong to (the phone's `updatedAt`, or the end of a clock-out the watch made itself).

**When it reloads:** the watch app's observer calls `ComplicationReload.reload()` (`reloadTimelines` + `invalidateRelevance`; a timeline reload alone never asks for relevance again) only when the pure `ComplicationReload.needsReload(old:new:)` says something shown changed: `signedIn`, the phase, the first chip, the field, the waiting count going between 0 and more than 0, a clock-out waiting, `lastClosedShift`, `usualStart`, the farm's zone, the trees this shift, the moments the timers count from, and off the clock the hours today **and the day they belong to** (the same hours on a later day redraw). Most reloads happen with the app in the foreground, where they aren't counted. [SYS-F8, SYS-P8]

**Rendering rules:**
- Timers and glyphs use `.widgetAccentable()`.
- Backgrounds go in `.containerBackground(for: .widget)`.
- Timers get a fixed frame with `lineLimit(1)` and `minimumScaleFactor(0.7)`, because Always On can change "3:41" into "3 hr".
- Tapping any complication opens the app, which is the glove-friendly way back in.

**Exact content:**

| Family | Working | Lunch / break | Off the clock | Signed out / no data |
|---|---|---|---|---|
| `.accessoryCircular` | Ring `ProgressView(timerInterval: timerStart...timerStart+8h)`; centre `leaf.fill` over **"14"** (next row) | Frozen ring `ProgressView(value: workedSoFar/8h)`; centre `cup.and.saucer.fill` or `pause.fill` over break timer **"12:40"** | No ring; `leaf` outline over **"6.5h"** today (or **"IN"** at 0) | `iphone` over **"—"** |
| `.accessoryRectangular` (also the Smart Stack widget) | L1 `leaf.fill` **"Working · Block 2"**; L2 big timer **"3:41:07"**; L3 **"Row 14 next · 38 trees"** | L1 `cup.and.saucer.fill` **"Lunch since 12:01"**; L2 big break timer **"0:12:40"**; L3 **"3:41 worked today"** | L1 **"Time Card"**; L2 big **"Clock in"**; L3 **"6.5 h today · Row 14 next"** | L1 **"Time Card"**; L2 **"Open on iPhone"** |
| `.accessoryCorner` | Centre `leaf.fill`; curved `.widgetLabel` timer **"3:41"** + **"R14"** (`.widgetCurvesContent()`) | Centre `cup.and.saucer.fill`; label **"Lunch 12:40"** | Centre `leaf`; label **"6.5 h today"** | Centre `iphone`; label **"Time Card"** |
| `.accessoryInline` | `leaf.fill` **"3:41:07 · Row 14"** | `cup.and.saucer.fill` **"Lunch 12:40 · 3:41 worked"** | `leaf` **"6.5 h today"** | **"Time Card"** |

- **Waiting taps:** while taps are waiting, rectangular L3 becomes **"Taps waiting for iPhone"** (no count: the complication reloads only when taps start or stop waiting, so a count would go stale as the queue drains in the background), and with a clock-out waiting, **"Clock-out waiting for iPhone"**.
- **Relevance** (watchOS 11 `relevance()`; watchOS ignores `TimelineEntryRelevance`) [SYS-F7, SYS-R8]:
  - While clocked in: `WidgetRelevanceAttribute(context: .date(from: shiftStart, to: shiftStart + 10h))`.
  - Off the clock, when `usualStart` is known: `.date(interval:kind:)` windows from 30 min before to 60 min after `usualStart` in `farmTimeZone`, **for today (unless it's over) and each of the next 7 days**, so "Clock in" rises in the Smart Stack in the morning. Relevance is only asked for again after `invalidateRelevance`, so a Friday clock-out has to carry Monday's window. With no `usualStart` (fewer than 3 shifts), no off-clock relevance.
  - Test with WidgetKit Developer Mode on.

### 4.4 The iPhone Live Activity on the watch (`.small` family) [SYS-F1–F5, SYS-R5]

**The iPhone Live Activity work is on the `watch` branch** (merged from `app`): the real lock-screen activity with its row buttons, and `LiveActivityController` with the restart and `.immediate` dismissal. So slice c builds the `.small` family now (8.1).

**What the watch needs from that activity:**
- `ActivityConfiguration(for: TimeCardActivityAttributes.self)` gains `.supplementalActivityFamilies([.small])`, which needs iOS 18 (section 5). Its lock-screen closure branches on `@Environment(\.activityFamily)`.
- `.small` is the watch Smart Stack card, and CarPlay uses the same layout with its buttons turned off. `.medium` stays the iPhone lock screen.
- Without `.small`, the watch squeezes the lock-screen layout until it's cut off. [SYS-P3]

**Size:** the card is 191×81.5 pt on Josh's Ultra 2 (49 mm), 198×81.5 on Ultra 3, 194×80.5 at 46 mm, 176×72.5 at 42 mm and **152×69.5 at 40 mm**, which is the smallest size to design for.

```
Working                                      Lunch / break
┌───────────────────────────────────┐        ┌───────────────────────────────────┐
│ 🍃 Working · Block 2     3:41:07  │ 18 pt  │ ☕ Lunch                   0:12:40 │
│ Next Row 14 · 38 trees            │ 14 pt  │ Since 12:01 · 3:41 worked          │
│ ╭───────────────────────────────╮ │        │ ╭───────────────────────────────╮ │
│ │       ✓  Row 14 done          │ │ 36 pt  │ │       ▶  Back to work         │ │
│ ╰───────────────────────────────╯ │        │ ╰───────────────────────────────╯ │
└───────────────────────────────────┘        └───────────────────────────────────┘
```

- **One control only,** as the HIG asks: `Button(intent: MarkRowIntent(blockId:row:))` for the first chip while working, `BackToWorkButtonIntent` on a break (both from `iOS/Shared/Intents/LiveActivityButtons.swift`). Undo and Break stay off the card.
- **Double Tap** fires the button from the Smart Stack through `.handGestureShortcut(.primaryAction)` on Series 9+ and Ultra 2+. [UI-F14, SYS-F3]
- **On a break, line 1 is just the phase** ("Lunch", "Break") and line 2 carries the worked total ("Since 12:01 · 3:41 worked"): on a 40 mm card the title gives way to the timer, and nothing redraws the card when a break passes an hour, so the total must live on line 2.
- **Fonts:** timers use the system font (`.system(.title3, design: .rounded).monospacedDigit()`), not Plex Mono. The `.small` family replaces the compact Dynamic Island views on the watch, so those keep the iPhone's fonts. [SYS-F5, SYS-P4]
- **Stale:** ten minutes before iOS ends the activity at 8 hours, line 2 says the lock screen's "Open Time Card" (the button stays).
- **Ending:** the controller must end with `dismissalPolicy: .immediate` at clock-out and at the 8-hour restart. Otherwise an ended card stays up to 4 hours and two cards stack. Updates use no `alertConfiguration`. [SYS-P14]
- **Opening the watch app:** the watch app's Info.plist has `WKSupportsLiveActivityLaunchAttributeTypes = ["TimeCardActivityAttributes"]`. It works on **watchOS 11.1+**: tapping the card opens the watch app. On 11.0 the tap shows "Open on iPhone", which is acceptable, so there is no gate. Name the type explicitly, because an empty array is reported not to work. [SYS-F4, SYS-P6]
- **Limit:** a Live Activity button runs `LiveActivityIntent` **on the iPhone**, with no outbox and no `issuedAt`. It's a phone-in-reach convenience. The watch app is the reliable path. [SYS-F3, SYS-P5]

### 4.5 Controls

**No watch-native controls in v1.**
- On watchOS 26, an iPhone app's Control Center controls can be placed in the watch's Control Center and Smart Stack, and they run on the phone. [UI-F11] The iPhone app's controls (Clock In, Next Row, Break, in `iOS/Widgets/TimeCardControls.swift`) reach the watch this way with no watch code.
- Shipping watch-built controls would **hide** the iPhone ones from the watch. [SYS-F9, SYS-P13]
- Watch-built control intents run in the widget extension, which has no WCSession and no outbox. [SYS-P9]
- Ultra owners already get the Action button (4.2), and everyone gets Double Tap.

Revisit with watchOS 26 `ControlWidgetButton` intents that open the watch app (`openAppWhenRun`) and enqueue through `WatchShiftModel`, gated `#available(watchOS 26, *)`. [SYS-R9]

---

## 5. Project setup (XcodeGen)

XcodeGen 2.46.0 and Xcode 26.3 were checked to build an iOS app with an embedded single-target watch app and a watch widget extension. [SYS-F10]

### 5.1 Targets and bundle ids

| Target | Type / platform | Bundle id | Sources |
|---|---|---|---|
| `TimeCard` (existing) | application / iOS | `$(BUNDLE_ID_PREFIX).timecard` | `App`, `Shared`, **+ `WatchLink`** |
| `TimeCardWidgets` (existing) | app-extension / iOS | `…timecard.widgets` | `Widgets`, `Shared` |
| `TimeCardTests` (existing) | bundle.unit-test / iOS | `…timecard.tests` | `Tests` **+ package product `TreeFarmKitTestSupport`** |
| **`TimeCardWatch`** | application / watchOS | `…timecard.watchkitapp` | `Watch/App`, `Watch/Shared`, `WatchLink` |
| **`TimeCardWatchWidgets`** | app-extension / watchOS | `…timecard.watchkitapp.widgets` | `Watch/Widgets`, `Watch/Shared` |
| **`TimeCardWatchTests`** | bundle.unit-test / watchOS | `…timecard.watchkitapp.tests` | `WatchTests` + `TreeFarmKitTestSupport` |
| **`TimeCardWatchUITests`** | bundle.ui-testing / watchOS | `…timecard.watchkitapp.uitests` | `WatchUITests` |

- **No `Shared` in watch targets.** `iOS/Shared` imports TimeCardCore (GRDB, iOS and macOS only) and ActivityKit, and it declares `LiveActivityIntent`s, so none of it compiles for watchOS. The watch targets link **TreeFarmKit only**. [SYS-F11, SYS-P1]
- **Package reference:** add `packages: TreeFarmKit: { path: ../Packages/TreeFarmKit }` to `project.yml`. It's the same path TimeCardCore uses, so SwiftPM sees a single identity.
- **`TreeFarmKitTestSupport`:** a new library product in `Packages/TreeFarmKit/Package.swift` (target `Sources/TreeFarmKitTestSupport/`, depends on TreeFarmKit) holding `FakeWatchTransport` and `InMemoryOutboxStore`. TreeFarmKit's own tests, `TimeCardTests` and `TimeCardWatchTests` all link it; the apps never do.

### 5.2 `project.yml` additions (exact)

`project.yml` generates every Info.plist and entitlements file below, so **those files are owned by slice 0** (section 8). A slice that needs a key asks the lead.

```yaml
options:
  deploymentTarget:
    iOS: "18.0"        # was 17.0; same iPhones (XS/XR, SE 2 and later)
    watchOS: "11.0"
packages:
  TimeCardCore: { path: TimeCardCore }
  TreeFarmKit: { path: ../Packages/TreeFarmKit }
targets:
  TimeCard:
    sources: [ … existing …, WatchLink ]
    info.properties:   # added to the existing list
      NSHealthShareUsageDescription: "Time Card shows your heart rate and calories during a shift. They stay on your iPhone and Apple Watch and are never sent to the farm."
      NSHealthUpdateUsageDescription: "Time Card saves each shift as an Other workout in Health, paused during lunch and breaks."
    entitlements.properties:
      com.apple.developer.healthkit: true
      com.apple.developer.healthkit.access: []
    dependencies: [ … existing …, { target: TimeCardWatch } ]   # → "Embed Watch Content"
  TimeCardTests:
    dependencies: [ … existing …, { package: TreeFarmKit, product: TreeFarmKitTestSupport } ]
  TimeCardWatch:
    type: application
    platform: watchOS
    sources:
      - Watch/App
      - Watch/Shared
      - WatchLink
    info:
      path: Watch/App/Info.plist
      properties:
        CFBundleDisplayName: Time Card
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        INAlternativeAppNames:
          - INAlternativeAppName: Tree Card
          - INAlternativeAppName: Tree Farm
        WKApplication: true
        WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX).timecard
        WKRunsIndependentlyOfCompanionApp: false
        WKBackgroundModes: [workout-processing]
        UIBackgroundModes: [audio]
        WKSupportsLiveActivityLaunchAttributeTypes: [TimeCardActivityAttributes]   # used on watchOS 11.1+
        NSHealthShareUsageDescription: (same text as iOS)
        NSHealthUpdateUsageDescription: (same text as iOS)
        TimeCardAppGroup: group.$(BUNDLE_ID_PREFIX).timecard
    entitlements:
      path: Watch/App/TimeCardWatch.entitlements
      properties:
        com.apple.security.application-groups: [group.$(BUNDLE_ID_PREFIX).timecard]
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
    settings:
      base:
        PRODUCT_NAME: TimeCardWatch
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).timecard.watchkitapp
        TARGETED_DEVICE_FAMILY: "4"
        SWIFT_VERSION: "6.0"
        SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon      # single-size 1024 watchOS icon
    dependencies:
      - target: TimeCardWatchWidgets                     # → Watch.app/PlugIns
      - package: TreeFarmKit
      - sdk: HealthKit.framework
      - sdk: WatchConnectivity.framework
      - sdk: UserNotifications.framework
  TimeCardWatchWidgets:
    type: app-extension
    platform: watchOS
    sources: [Watch/Widgets, Watch/Shared]
    info:
      path: Watch/Widgets/Info.plist
      properties:
        CFBundleDisplayName: Time Card
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        TimeCardAppGroup: group.$(BUNDLE_ID_PREFIX).timecard
        NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }
    entitlements:
      path: Watch/Widgets/TimeCardWatchWidgets.entitlements
      properties:
        com.apple.security.application-groups: [group.$(BUNDLE_ID_PREFIX).timecard]
    settings:
      base:
        PRODUCT_NAME: TimeCardWatchWidgets
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).timecard.watchkitapp.widgets
        TARGETED_DEVICE_FAMILY: "4"
        SKIP_INSTALL: YES
        SWIFT_VERSION: "6.0"
        SWIFT_DEFAULT_ACTOR_ISOLATION: nonisolated
    dependencies:
      - package: TreeFarmKit
      - sdk: WidgetKit.framework
      - sdk: SwiftUI.framework
  TimeCardWatchTests:
    type: bundle.unit-test
    platform: watchOS
    sources: [WatchTests]
    dependencies:
      - target: TimeCardWatch
      - package: TreeFarmKit
        product: TreeFarmKitTestSupport
    settings.base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).timecard.watchkitapp.tests, GENERATE_INFOPLIST_FILE: YES }
  TimeCardWatchUITests:
    type: bundle.ui-testing
    platform: watchOS
    sources: [WatchUITests]
    dependencies: [{ target: TimeCardWatch }]
    settings.base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).timecard.watchkitapp.uitests, GENERATE_INFOPLIST_FILE: YES, TEST_TARGET_NAME: TimeCardWatch }
schemes:
  TimeCardWatch:
    build: { targets: { TimeCardWatch: all } }
    run: { config: Debug }
    test: { config: Debug, targets: [TimeCardWatchTests, TimeCardWatchUITests] }
```

- **Watch-specific values go at target level.** XcodeGen platform presets override project-level settings. [SYS-P18]
- **The watch target needs an app icon:** a watchOS single-size 1024 AppIcon at `Watch/App/Resources/Assets.xcassets`, or asset compilation fails. [SYS-P19]
- **The `App Group` id is the same as the phone's.** On the watch it's a separate container.

### 5.3 Embedding

- The iOS app's dependency on `TimeCardWatch` produces **Embed Watch Content**, giving `TimeCard.app/Watch/TimeCardWatch.app`.
- The watch app's dependency on the widget produces **Embed Foundation Extensions**, giving `TimeCardWatch.app/PlugIns/TimeCardWatchWidgets.appex`.
- Both were checked in the generated project. [SYS-F10]

### 5.4 Deployment targets and `@available`

- **iOS goes from 17.0 to 18.0.** That's what `.supplementalActivityFamilies` needs, and it can't be applied conditionally. `WidgetBundleBuilder` has `if #available` but no `else`, and `WidgetConfiguration` has no type eraser. Registering two configurations for the same attributes is undefined. iOS 18 supports the same iPhones as iOS 17. [SYS-F11, SYS-P2, SYS-R1]
- **watchOS minimum is 11.0.** That brings `handGestureShortcut`, the Live Activity in the Smart Stack, `relevance()`, interactive Smart Stack widgets and `AccessoryWidgetGroup` with no checks. TreeFarmKit's `.watchOS(.v10)` stays as it is.
- **The one 11.1 behavior** is `WKSupportsLiveActivityLaunchAttributeTypes` (a plist key, so no code gate; 11.0 shows "Open on iPhone"). [SYS-F4]
- **No `@available` gates are needed in v1** at these minimums. Any API newer than the minimums must be gated, and none ships in v1:
  - `if #available(watchOS 26, *)`: `ControlWidgetButton`, `RelevanceConfiguration`, `WidgetPushHandler`.
  - `if #available(iOS 26, *)` and watchOS 27 APIs: the iPhone workout builder, workout zones, Watch Connectivity widget refresh. The watchOS 27 ones need Xcode 27 anyway. [WC-F17, HK-F17]
- **Toolchain:** Xcode 26.3 ships the watchOS 26.2 SDK. **Don't update Josh's watch to watchOS 27 mid-season** while the iMac stays on Xcode 26.3. [SYS-P16, HK-P17]

### 5.5 The iPhone's Settings toggle

Settings gets an **Apple Watch** section (`WatchSettingsSection`), shown only when `isPaired`:

- **Record shifts as workouts**, default **on**. It's saved per person on this phone, read by `WatchDesk` on every call, and travels to the watch as `WatchState.recordWorkouts`. Changing it publishes at once.
- **Status line:** "Time Card on your watch · in reach", "… not installed: install it from the Watch app", or "No Apple Watch paired".
- **Footnote:** "Workouts keep Time Card on your watch all shift and log heart rate and calories in Health. They never go to the farm." With the toggle off, it adds: "The Action button needs workouts on."

---

## 6. Edge cases

Each line gets a test first where a test is possible. The test column says where.

| Case | Behaviour | Test |
|---|---|---|
| **Phone out of reach, then back** | Taps queue with `issuedAt` and the displayed shift id, the badge counts them, and the `.retry` haptic plays. The screen keeps showing the queued result (row 16 next with 14 and 15 queued), even when a context push arrives. On reachability, the courier flushes oldest first, one at a time. The phone applies each at `effectiveTime` (clamped by `notBefore`), with `updatedAt = receivedAt`. Refused items are listed in the Queue sheet for 1 h | `WatchCourierTests`, `WatchDeskTests`, `WatchShiftModelTests` |
| **More than 40 rows marked out of reach** | `nextRows` carries 40 chips, so about 4 hours of marking fits. Past that: "Out of rows the watch knows. Bring your phone closer." Never "Field done" unless `fieldShaped == fieldTotal` | `WatchOptimismTests`, `WatchDisplayTests` |
| **Queued clock-out reaches the phone after a new shift started** (watch clock-out queued yesterday; today a phone clock-in) | The clock-out carries yesterday's shift id, which isn't the open shift, so it's refused: "That clock-out was for the shift that started at 7:02, which is already closed, so it wasn't applied." Today's shift is untouched | `WatchDeskTests` "queued clockOut after a new phone clock-in is refused" |
| **Queued row marks from a closed shift** | Refused with the shift named, shown in the Queue sheet; the person fixes it in the Log | `WatchDeskTests` "marks from a closed shift are refused" |
| **Queued clock-in older than the last closed shift's end** | Refused: "That clock-in at 6:40 was before your last shift ended at 7:10…" | `WatchDeskTests` |
| **Watch clock-in queued while the phone already clocked in** | Refused with the engine's sentence. The minted id is aliased to the open shift, so the marks queued after it still apply, and the watch workout is retagged | `WatchDeskTests`, `WorkoutPlanTests` |
| **Watch clock-out while the phone is out of reach** | The workout stops at the tap time but the session stays (stopped) for up to 60 min, keeping the app alive and flushing once a minute. "Clock-out waiting for iPhone" banner. On the answer, finish. At 60 min, finish and notify "Open Time Card near your iPhone to finish clocking out." | `WorkoutPlanTests` "queued clockOut → stop now, finish on ack or after 60 min", device |
| **A reply lost mid-flight** | The request is durable, so it stays queued and is resent. `WatchInbox` returns the saved reply (with fresh state), so row 14 isn't marked twice. `appliedRequestIds` in the next state clears it | `WatchInboxTests`, `WatchCourierTests` |
| **A reply that arrives after the 4 s timeout** | `ResumeOnce` ignores it. The retry is answered from `WatchInbox` | `ResumeOnceTests`, `WatchCourierTests` |
| **A queued tap the phone's state has moved past** (Siri on the phone took lunch first) | The command runs against the phone's state and fails with the engine's sentence ("You're already on lunch since 10:34."), shown in the Queue sheet. It is never forced in | `WatchDeskTests` |
| **A queued end of break earlier than the break's start** (break started on the phone at 10:40, watch "back to work" tapped at 10:38) | `notBefore` includes the open break's start, so it ends at 10:40, never before | `WatchLinkTests` (`notBefore`), `WatchDeskTests` |
| **Outbox overflow** (more than 200) | Drops the oldest row marks first and never a clock-in, clock-out, break transition or cancel. Shows the "couldn't be kept" count | `WatchLinkTests` |
| **App killed mid-workout** (watch) | `handleActiveWorkoutRecovery` → `.recover`, which runs before any other workout input: recover the session, reattach the data source and delegates, restore `WorkoutLocal`, reconcile | `ShiftWorkoutTests` "handle() during recovery → no second session", device |
| **Two state changes during a slow start** | One serial input queue, newest inputs only: one start | `ShiftWorkoutTests` "two reconcile inputs during a slow start → one start" |
| **iPhone app killed or never launched** | `sendMessageData` wakes it. `AppModel.init` activates WCSession. The bridge awaits `startTask` before calling the desk, so there's no false "sign in" | `AppModelTests` (concurrent start), device |
| **Phone reinstalled, new phone or store reset** | A new `epoch`; the watch accepts the lower revision instead of freezing | `WatchShiftModelTests` "new epoch with lower revision is accepted" |
| **Phone rebooted, not yet unlocked** | The watch shows "Unlock your phone once" (`iOSDeviceNeedsUnlockAfterRebootForReachability`). The phone replies `keepQueued: true` if the store can't open | `WatchDeskTests`, device |
| **Siri clock-in on the phone while the watch sleeps** | The bridge updates the context, then `startWatchApp` with a 10 s timeout. If the watch launches before the context arrives, it starts untagged at now and tags when the state comes; a stale off-clock state doesn't discard it. If the launch fails or the watch is off-wrist, the workout starts at the next foreground: at `shiftStart` if within 5 min, else now, with the toast "Recording from 7:14" | `PhoneWatchBridgeTests`, `WorkoutPlanTests` "stale off-clock context right after a phone launch → no discard" |
| **Siri on the watch with the phone out of reach** | It queues and says "Saved on your watch…". `WatchPrecheck` refuses commands that are bound to fail. Questions are answered from the cache with "as of …" | `WatchIntentTests` |
| **Watch never connected** (no state yet) | Every command is refused before queueing: "Open Time Card on your iPhone once." The phone treats a command with `userId == nil` as a mismatch anyway | `WatchPrecheckTests`, `WatchDeskTests` |
| **Both devices acting at once** (lock-screen "Row 14" and watch "Row 14" within a second) | The phone runs one at a time on the main actor. The second gets "Row 14 is already marked." with a `.failure` haptic, and the watch shows the phone's state. Two clock-outs: the second gets "You're not clocked in." and the watch workout still finishes (the clock-out was answered) | `WatchDeskTests`, `WorkoutPlanTests` |
| **Double Tap twice fast** | The displayed state has moved to row 15, so the second tap marks 15. Each tap is its own request in order | `WatchOptimismTests`, UI test |
| **Double Tap on the off-clock screen by accident** | A shift starts; **Undo clock-in** for 2 min cancels it on the phone and discards the workout | `WatchDeskTests` (`cancelShift`), `WorkoutPlanTests` |
| **Signed out on the phone** | `WatchState.signedIn == false` → "Open Time Card on your iPhone to sign in." Queued taps stay (with `userId`). If the same person signs in, they apply. A different person: "These taps were for Josh, so they weren't applied," and they're dropped | `WatchDeskTests` |
| **Older or newer app on one side** (TestFlight updates them separately) | Envelope `v` mismatch → `WatchReply.unreadable("Update Time Card on your iPhone")` (or watch), `keepQueued: true` | `WatchLinkTests`, `WatchDeskTests` |
| **Live Activity ended** (8 h, swiped, or turned off) | The watch app doesn't depend on it. The Smart Stack card goes away. Once the Live Activity work lands, its controller restarts the activity on foreground with `.immediate` dismissal, so cards don't stack | `LiveActivitySmallTests` (after the prerequisite) |
| **Workout ended from outside** (Apple's Workout app started, crash, battery) | Collected data is saved, the **shift stays on the clock**, and the banner "Recording stopped [Record again]" appears. Never a clock-out. A **stopped** session (a watch clock-out waiting) ended from outside finishes at `stoppedAt` with its summary, offers no Record again, and keeps the stuck reminder | `ShiftWorkoutTests` |
| **Phone clock-out with an untagged session** (launch before the context, recovery with no saved id) | Finishes at `lastClosedShift.end` when it falls inside the session, else at now. Never runs forever | `WorkoutPlanTests` "untagged session + phone clock-out → finish" |
| **HealthKit denied, never asked, or recording off** | No workout. The Today page explains. The Action button clocks in on the first press and only opens the app after that; Settings says "Action button needs workouts on" | `ShiftWorkoutTests`, `ActionButtonDonorTests` |
| **`recordWorkouts` turned off mid-shift** | The desk reads settings per call, so the next state says off; finish the running workout now (normal save). No new sessions | `WatchDeskTests`, `WorkoutPlanTests` |
| **A clock-in by mistake, then clock-out within 2 min** | The workout is discarded; Undo clock-in removes the shift | `WorkoutPlanTests` |
| **Rain or sap phantom taps** | The Lock (Water Lock) button, on `.wr50` and `.wr100` watches. Under it, Next row works through the Action button and Siri. The crown unlocks | `WatchShiftModelTests` (gate), device |
| **Low Power Mode** | Double Tap and Always On are off and recording continues. The Today page notes it, and buttons, crown and Siri still work | device |
| **Watch switched** (a second watch paired) | `sessionDidDeactivate` → `activate()`. The new watch gets the context and its own outbox is empty | device |
| **Field fully shaped** | No chips and `fieldShaped == fieldTotal`. The primary button reads "Field done", disabled. The Action button's next action says "Every row in North is shaped." and queues nothing | `WatchDisplayTests`, `WatchShiftModelTests` |
| **Siri opt-in declined on the watch** | Can't be re-enabled or detected (reported on 26.6). Buttons, Double Tap and the Action button still work; SetupScreen warned beforehand | device |
| **Personal Team App ID limits** | The free team gets 10 App IDs per 7 days, and capability changes reportedly count. This adds 2 (`watchkitapp`, `watchkitapp.widgets`). Fix the ids once and never rename them. Add HealthKit and App Groups in **one** change. Profiles expire after 7 days, so rebuild both apps weekly, or the watch app stops launching and workouts with it. Devices: iPhone + watch = 2 of 3. No Push until the paid team, so no APNs for the Live Activity, widgets or controls. Run watch UI tests only in the Simulator, so their runner doesn't spend an App ID [SYS-F12, SYS-P15, SYS-R10] | — |

---

## 7. Test plan

The repo rule holds: failing test → code → green → commit, for every slice.

### 7.1 Seams (protocols) so everything can be faked

| Protocol | Lives in | Real | Fake |
|---|---|---|---|
| `WatchTransport` | TreeFarmKit `Watch/` | `WCSessionTransport` (`iOS/WatchLink`) | `FakeWatchTransport` (`TreeFarmKitTestSupport`, linked by the TreeFarmKit, iOS and watch test targets): scripted reachability, recorded sends, replies, delays, late replies, lost replies, errors, context and user-info deliveries |
| `WatchOutboxStore` | TreeFarmKit | `FileOutboxStore` (App Group JSON) | `InMemoryOutboxStore` (`TreeFarmKitTestSupport`) |
| `WorkoutDriver` | watch app `Workout/` | `HealthKitWorkoutDriver` (HKWorkoutSession + HKLiveWorkoutBuilder) | `FakeWorkoutDriver`: records start, pause, resume, stop, finish and discard with dates, can be made slow, and emits state and metric events and unexpected ends |
| `WatchWorkoutLauncher` | iOS app `Watch/` | `HealthKitWatchLauncher` (`startWatchApp`) | returns `.started`, `.timedOut` or `.failed` |
| `ActionButtonDonating` | watch app `Intents/` | wraps `donate(result:)` | records donations |
| `WatchHaptics` | watch app | `WKInterfaceDevice.play` | records events |
| `ShiftNotifier` | watch app `Workout/` | `UNUserNotificationCenter` | records requests |

### 7.2 Unit tests

**TreeFarmKit** (`swift test`, macOS and Linux, no simulator):
- `WatchLinkTests` (extended):
  - Envelope round trip, version refusal, and a `WorkoutSummary` round trip.
  - `supersedes`: higher revision accepted, equal or lower ignored, new epoch with a lower revision accepted.
  - The outbox refuses undo and next-row, keeps clock transitions and `cancelShift` past the limit, `acknowledge`, and `removeLast`.
  - `effectiveTime` clamping, and `notBefore` for an open break, a closed shift before a clock-in, and no shift.
  - `SyncRecord.stamped(updatedAt:)`.
- `FieldEngineTests` (extended): `.clockIn` with `newShiftId` uses it; `.cancelShift` soft-deletes an empty shift within 5 min and refuses one with marks, breaks or later.
- `ResumeOnceTests`: reply then timeout, timeout then reply ("reply after timeout doesn't crash and is ignored"), error then reply.
- `WatchInboxTests`: dedupe, the 500/7-day bound, persistence round trip, replies stored without state, aliases.
- `WatchConfirmTests`: equals `FieldEngine.confirmation` text for clock-out, a row 6+ away, and another block. Returns nil for close rows.
- `WatchPrecheckTests`: no state, not clocked in, already on a break, not on a break.
- `WatchOptimismTests`: each command's predicted state. Two marks in a row move two chips. "Mark 12 rows offline" keeps going past the 10th chip. Clock-in opens a shift with the minted id; `cancelShift` closes it.
- `WatchStateBuilderTests`:
  - The shift id and start come from the open shift.
  - Up to 40 chips.
  - `hadLunchToday`, `lastClosedShift`, `appliedRequestIds` (the last 50).
  - `usualStart` is the median of the last 10 shift starts in the farm's time zone, nil with fewer than 3.
  - Signed out.
  - No pay field.
- `WatchDisplayTests`: every phase, string and glyph, plus field done, out of known rows, and stale shift.
- `WatchCourierTests`:
  - One request in flight at a time, in order.
  - Unreachable → queued.
  - Timeout → stays queued with a "waiting" event.
  - "Late reply after timeout → retry is deduped by WatchInbox" (fake transport backed by a scripted inbox).
  - `keepQueued` → stays.
  - A refusal still leaves the outbox.
  - "Durable command survives a lost reply"; a state with its id clears it.
  - "Undo while reachable bypasses the outbox"; undo while unreachable → `.notSent`.
  - `inFlight` is exposed while a send is pending, and the waiting count excludes it.
  - Taking back the last queued tap.
- `WorkoutPlanTests`: a table over (confirmed phase × local session × pending and in-flight requests × refused clock-ins × now). It covers:
  - Every row of 2.2 and every reconcile rule.
  - "Stale off-clock context right after a phone launch → no discard."
  - "In-flight clockIn plus stale state → no discard."
  - "Queued clockOut → stop now, finish on ack or after 60 min" (with `.notifyStuckClockOut`).
  - "Untagged session + phone clock-out → finish."
  - Refused clock-in → discard. Already open → retag.
  - `cancelShift` → discard.
  - Discard under 2 min. The 5-minute backdating cap.
  - Recording turned off mid-shift.
  - Another-workout end → no automatic restart.

**TimeCardCore** (`swift test`):
- `WatchDeskTests`:
  - A duplicate id runs once; a replay hit carries a fresh state.
  - The event time is the effective time and `updatedAt` is `receivedAt`, checked on shift, break and mark records.
  - "Queued clockOut after a new phone clock-in is refused."
  - "Marks from a closed shift are refused."
  - A clock-in older than the last closed shift's end is refused.
  - A refused clock-in records an alias, and a later mark with the minted id applies to the open shift.
  - A clock-in creates the shift with the minted id.
  - `userId` mismatch, and `userId == nil` treated as a mismatch.
  - Signed out → `keepQueued`.
  - Undecodable or too-new → an `unreadable` reply is sent.
  - "Reply state and published state share the counter": a reply's revision is higher than the publish before it and lower than the one after.
  - The revision and epoch persist across a new desk on the same store; an empty store makes a new epoch.
  - A settings change between two requests shows in the second state.
  - Questions. A reply always carries `state`.
- `FieldActionsTests`: `perform(_:at:newShiftId:)`.

**iOS app tests** (`xcodebuild test`, iPhone simulator):
- `PhoneWatchBridgeTests` (fake transport and launcher):
  - Publishing is coalesced within 250 ms and every state comes from `desk.makeState()`.
  - Nothing is published when not paired or not installed.
  - A phone clock-in launches the watch workout only when `recordWorkouts` is on, the clock-in didn't come from the watch, and the context was updated **before** the launch.
  - The complication transfer happens only on phase changes with budget left, and carries a `.state` envelope.
  - Every request is answered exactly once.
- `AppModelTests`: concurrent `start()` callers all see a loaded session.
- `LiveActivitySmallTests` (slice c, after the prerequisite): the `.small` view model picks the right single control per phase and uses no custom font.
- `WatchSettingsTests`: toggle persistence per person.

**Watch unit tests** (`TimeCardWatchTests`, watchOS simulator):
- `WatchShiftModelTests`:
  - The displayed state, then reply success, refusal or queue, each with its haptic and toast.
  - "New state with 2 queued marks still shows row 16."
  - "Applied ids aren't applied twice."
  - "New epoch with lower revision is accepted"; an older revision in the same epoch is ignored.
  - "No chip → nothing queued", with the right line for field done and for out of known rows.
  - Undo rules. Undo clock-in shown for 2 minutes only.
  - `WaterLockGate`: `.wr50` and `.wr100` yes, `.ipx7` no, no session no, background no.
  - Wrist-raise resets to Now.
  - A user-info event is handled like a context, and `drained()` returns only after it.
  - `WatchStateFile` receives `displayed`, and `ComplicationReload.needsReload` gates the reload.
- `ShiftWorkoutTests` (fake driver): start, pause, resume, stop and finish order and dates; the metadata set; recovery path; "two reconcile inputs during a slow start → one start"; "handle() during recovery → no second session"; unexpected end → banner, shift kept; authorization denied; the stuck-clock-out notification at 60 min.
- `ComplicationReloadTests` (slice c): each field that matters triggers a reload; a timer tick or a later chip doesn't.
- `WatchIntentTests`: each of the 10 intents against a fake model, covering reachable, unreachable, no state and precheck refusal; `ClockOutIntent` asks for confirmation; `StatusIntent` gives the cached answer with "as of"; "mark row 40" resolves through `entities(matching:)`; `updateAppShortcutParameters()` runs when the first chip changes.
- `ActionButtonDonorTests`: next-row donation while working, resume-work donation on a break, re-donation on every phase change; `PauseShiftIntent` picks lunch then break; `ResumeShiftIntent` ends the break; recording off → the first press clocks in with no session and nothing is donated.

### 7.3 Watch simulator UI tests (`TimeCardWatchUITests`)

**Setup:**
- Launch argument `-watchDemo` swaps in a `FakeWatchTransport` driven by a scripted in-process "phone". It uses `WatchStateBuilder` over a demo `FieldState`, so the sentences are real.
- `-watchPhoneAway` starts unreachable.

**Flows:**
- Off clock → **Clock in** → Now shows the timer and "Row 14 done" → tap it → toast "Row 14 marked" → the chip moves to 15.
- Crown: `XCUIDevice.shared.rotateDigitalCrown(delta:)` changes the label to "Row 16 done".
- Double Tap: when `XCUIDevice.shared.supportsHandGestures`, call `XCUIDevice.shared.perform(handGesture: .doubleTap)` (watchOS 10+) and assert that the row was marked. On a simulator without hand gestures (none of ours), skip with a note.
- Undo clock-in: clock in, tap **Undo clock-in** → back to the off-clock screen.
- Controls → Lunch → Now shows "Back to work" → Back to work → Clock out → confirmation → **Yes, clock out** → summary → Done.
- `-watchPhoneAway`: two taps → badge "2" → Queue sheet lists them → the script pushes a context without them → the screen still shows row 16 → the script brings the phone back → badge clears.
- `-watchPhoneAway` clock-out → "Clock-out waiting for iPhone" banner → phone back → banner clears and the summary shows.

**Screenshots:** every screen on the SE 3 40 mm, Series 11 42 mm and 46 mm, and Ultra 3 49 mm simulators, at default text size and at accessibility XL. Assert that the Now screen **doesn't scroll** at any of them.

**Always On:** the simulator's Lock toggles the reduced-luminance rendering. Snapshot it.

### 7.4 Paired-simulator integration

There's no usable pair on the iMac yet. Create one [WC-F18, WC-R13]:

```
xcrun simctl delete unavailable
xcrun simctl pair 9C35265B-4986-4DB4-B0D0-12B5AFF931C7 7838EFD1-AD53-4E6D-8FFF-FCAE89E00EE7   # Ultra 3 49 mm + iPhone 17 Pro
xcrun simctl pair_activate <printed pair id>
```

**Run the iOS app with the stub server, then the watch app. Check:**
- Activation on both sides.
- Request and reply through `sendMessageData`.
- State push by context and by message, with revisions rising and one epoch.
- Reachability changes.
- Out of range, simulated by shutting down the phone simulator, then booting it again → the outbox flushes and the taps apply at their tap times to the right shift. Verify in the phone's Log.
- `startWatchApp` from the phone simulator starts the watch workout (reported flaky; record the result) and survives a context that arrives after the launch.
- Simulated heart rate in the watch workout.
- The first Action-button press (Settings › Action Button on the Ultra simulator).
- Siri phrases run from the watch Shortcuts app.

**Not testable in the Simulator, so device only:** `transferCurrentComplicationUserInfo` and `didReceiveUserInfo`, Bluetooth range and timing, real suspension, a stopped session's lifetime, Action + side pause, mirroring, watch switching, unlock after reboot. [WC-F19, HK-F15]

**How to run it** (Xcode 26.3, iPhone 17 on iOS 26.3 paired with an Ultra 3 on watchOS 26.2, both builds signed to run locally so HealthKit and the App Group work):

```
xcrun simctl launch <phone> <prefix>.timecard -UITestInMemory -UITestWatchLink
TEST_RUNNER_WATCH_PAIRED_PHONE=1 xcodebuild test-without-building -scheme TimeCardWatch \
  -only-testing:TimeCardWatchUITests/WatchPairedUITests/testTheWatchDrivesThePairedPhone …
TEST_RUNNER_WATCH_PAIRED_PHONE=1 xcodebuild test-without-building -scheme TimeCard \
  -only-testing:TimeCardUITests/WatchLinkUITests …          # with the watch app closed
```

The stalled-phone test also needs `TEST_RUNNER_WATCH_PAIRED_STALL=1` and a script that sends the phone app `SIGSTOP` once the attachment `stall-working` shows in the log, and `SIGCONT` some time after `stall-lunch-waiting`.

**Results on the paired simulators (Oct 19, 2026):**
- Activation on both sides, and the phone's state reached the watch: the demo farm ("Pine Hollow Tree Farm · North Field", "Starts: Block 1 · Row 5").
- Requests and replies through `sendMessageData`: clock in, mark row 5 (the toast "Row 5 marked", the button moves to row 6), lunch, back to work, clock out with the confirmation, then the summary ("12 trees"; the workout was under 2 minutes, so no heart line). `testTheWatchDrivesThePairedPhone` passes.
- A new phone launch (new in-memory store, so a new epoch with a lower revision) replaced the watch's state.
- Health on the watch: the first-launch card, then the system's Health sheet (Review, the switches, Next), drivable from a UI test. The workout then recorded with simulated heart rate (57–58 bpm on Now and Today, "Recording shift workout").
- A stalled phone, standing in for "out of range" (shutting the phone simulator down loses its in-memory farm): the phone app stopped with `SIGSTOP`, the watch's lunch waited ("Saved on watch · 1 waiting", the badge), the phone resumed 75 s later, and the lunch applied **at its tap time**: the phone shows "Lunch started 10:21 PM" though it ran it at 10:23, and the watch's badge cleared once the phone's state listed it. `testATapWaitsForAStalledPhoneThenAppliesAtItsTime` passes. The watch's own reachability stayed "in reach" throughout, so the out-of-reach path itself (no send at all) is covered by the unit and demo UI tests, not here.
- `startWatchApp`: a clock-in on the phone, with the watch app closed, launched it within a second, and its Now page showed the shift with the workout's heart rate. The phone never asked for Health authorization (2.4).
- Not done in the simulator: the Action button's first press and Siri phrases on the watch (covered by `ActionButtonDonorTests` and `WatchIntentTests`; device checks in 7.5).

### 7.5 Real-hardware checklist (Josh's iPhone 15 Pro Max on iOS 26.6 + Apple Watch Ultra 2)

Run everything **detached from Xcode**, because the debugger stops suspension. [WC-F11, WC-P15]

**Setup:**
- Developer Mode on the watch (Settings › Privacy & Security, restart, Turn On) and Trust on both devices.
- Mac, iPhone and watch on one network with client isolation off, or on the iPhone hotspot.
- The iPhone cabled for the first install. [SYS-F13, SYS-R11, WC-P20]

**Workout:**
- [ ] HealthKit and notification prompts on the watch. The workout appears in Fitness as **Other**, with "Time Card shift" and the metadata.
- [ ] No location indicator during the workout.
- [ ] Phone-side `startWatchApp` works without phone authorization. If not, add share `[workoutType]` from the toggle (2.4).

**Staying on screen and reachable:**
- [ ] Wrist down for 10 minutes mid-shift: the app returns on raise, and `isReachable` stays true (the outbox flushes with the wrist down).
- [ ] **Lunch (paused workout) keeps the app on screen and reachable.**
- [ ] **A stopped session (clock-out made 50 m from the phone) keeps the app alive; walking back within 60 min finishes the clock-out on its own.** Past 60 min, the notification arrives.
- [ ] Haptics play with the wrist down during the workout.

**Range and delivery:**
- [ ] Walk 50 m from the phone and mark 3 rows plus a lunch, then walk back. All apply at their tap times, and the Queue sheet clears.
- [ ] Kill the iPhone app, then tap on the watch: it's woken and applies once.
- [ ] Reboot the iPhone without unlocking: "Unlock your phone once". Unlock: the taps apply.
- [ ] Siri on the phone (AirPods) "clock in" with the watch on the wrist and the screen off: the watch workout starts within 10 s or at the next raise.
- [ ] Take lunch on the phone with the watch app in the background: the complication updates through `transferCurrentComplicationUserInfo` (`didReceiveUserInfo`), and the background task completes.

**Hands-free input:**
- [ ] **Double Tap through Josh's real work gloves** and with shears in hand. Note any false fires, including on the off-clock screen (then Undo clock-in).
- [ ] Crown row selection through gloves. A cuff bumping the crown is visible and undoable.
- [ ] Action button: the first press clocks in and records; **the second press marks the next row once the session is running** (the donation follows the session); on lunch a press resumes; Action + side pauses and resumes.
- [ ] Water Lock appears on the Ultra 2 (`.wr100`), and whether Double Tap and the crown selector still work under it.

**Siri, Smart Stack and complications:**
- [ ] Siri on the watch: every phrase in 4.1, out loud, with the phone in a pocket and with the phone away. Accept the App Shortcuts opt-in the first time (it may not come back if declined).
- [ ] "Mark row 40 in Time Card" on the watch resolves and asks to confirm. Try it said directly, and as "Mark a row" → "Which row?" → "forty", and record which path works: watch phrases need an exact match, and a parameterized phrase is filled only from `suggestedEntities()` (the first 10 chips), so the direct phrase may match only when row 40 is a chip. The second path goes through `entities(matching:)`, which is tested.
- [ ] Smart Stack Live Activity (once the prerequisite lands): the layout at 49 mm. Double Tap marks the row. **Tap the card's button with the phone out of reach and record what happens.** Tapping the card opens the watch app.
- [ ] Complications on Josh's face: all four families. Always On timer format and width. Tinted face legibility. "Clock in" rises in the Smart Stack around the usual start.

**Failure and recovery:**
- [ ] Kill the watch app from Xcode mid-shift: the workout recovers with no duplicate.
- [ ] Crash relaunch: record whether `recoverActiveWorkoutSession()` succeeds when called from `applicationDidFinishLaunching`, or only from `handleActiveWorkoutRecovery()`.
- [ ] Start Apple's Workout app mid-shift: "Recording stopped", the shift is still on the clock, Record again works.
- [ ] Start Apple's Workout app while a watch clock-out waits (phone away): the shift summary shows, no "Recording stopped", and the reminder still arrives at 60 min.

**Endurance:**
- [ ] **A full 8–9 h shift:** battery at clock-out, how much of the shift the app stayed on screen, and the Exercise minutes and calories credited for **Other**. Decide whether they look honest. [HK-P7]

---

## 8. Build plan for parallel agents

### 8.1 Order

1. **Slice 0 (lead, lands first, alone):** all shared contracts, as compiling code with tests. Stub bodies for every type that another slice implements, with the exact signatures below. Plus the `project.yml` targets, every Info.plist and entitlements file, `TreeFarmKitTestSupport`, and empty folders.
2. **Slices a, b, c and d run in parallel**, each only inside its own folders. Each opens with failing tests.
3. **The lead integrates:** pair the simulators, run 7.3 and 7.4, then the device checklist. The lead also merges each slice's edge-case lines (from its PR description) into `docs/edge-cases.md`.

**Prerequisite for slice c's Live Activity part:** the real iPhone Live Activity (lock-screen layout with row buttons), its `LiveActivityController` (with the 8-hour restart and `.immediate` dismissal) and the iPhone Control Center controls. All three are on the `watch` branch, so slice c builds `LiveActivitySmall.swift` too.

**No slice edits a file another slice owns.** If a contract or a plist key has to change, stop and ask the lead, who changes it in slice 0's files for everyone.

### 8.2 File ownership

| Slice | Owns (create or edit) |
|---|---|
| **0 · Contracts (lead)** | `Packages/TreeFarmKit/Package.swift`; `Packages/TreeFarmKit/Sources/TreeFarmKit/Watch/{WatchLink,WatchInbox,WatchConfirm,WatchPrecheck,WatchOptimism,WatchStateBuilder,WatchDisplay,WatchTransport,ResumeOnce}.swift` (`WatchLink.swift` includes `WorkoutSummary`, `ClosedShift`, `WorkoutLocal`, `WorkoutInputs`, `WorkoutStep`); `Packages/TreeFarmKit/Sources/TreeFarmKit/Field/FieldEngine.swift` (`cancelShift`, `newShiftId`) and `Time/Clock.swift` (`id:`); `Packages/TreeFarmKit/Sources/TreeFarmKit/Sync/SyncRecordStamp.swift` (new); `Packages/TreeFarmKit/Sources/TreeFarmKitTestSupport/**` (`FakeWatchTransport`, `InMemoryOutboxStore`); `Packages/TreeFarmKit/Tests/TreeFarmKitTests/Watch/{WatchLink,WatchInbox,WatchConfirm,WatchPrecheck,WatchOptimism,WatchStateBuilder,WatchDisplay,ResumeOnce}Tests.swift` and the `FieldEngineTests` additions; `iOS/TimeCardCore/Sources/TimeCardCore/Field/FieldActions.swift` (`perform(_:at:newShiftId:)`); `iOS/App/AppModel.swift` (`startTask`, `let watch: PhoneWatchBridge`, publish hooks); `iOS/App/TimeCardApp.swift`; `iOS/project.yml` + regenerated `iOS/TimeCard.xcodeproj`; **every Info.plist and entitlements file it generates** (`iOS/App/Info.plist`, `iOS/App/TimeCard.entitlements`, `iOS/Watch/App/Info.plist`, `iOS/Watch/App/TimeCardWatch.entitlements`, `iOS/Watch/Widgets/Info.plist`, `iOS/Watch/Widgets/TimeCardWatchWidgets.entitlements`); `iOS/WatchLink/WCSessionTransport.swift`; `iOS/Watch/Shared/WatchStateFile.swift`; stub files for every slice type listed in 8.3, each marked `// STUB: slice X replaces`; `docs/watch.md`, `docs/edge-cases.md`, `docs/voice-test.md` |
| **a · Watch app shell, model, outbox, screens** | `iOS/Watch/App/TimeCardWatchApp.swift`, `iOS/Watch/App/WatchAppDelegate.swift`, `iOS/Watch/App/Resources/**`, `iOS/Watch/App/Model/**` (`WatchShiftModel`, `FileOutboxStore`, `WatchHaptics`, `WaterLockGate`), `iOS/Watch/App/Views/**` (including SetupScreen); `Packages/TreeFarmKit/Sources/TreeFarmKit/Watch/WatchCourier.swift` + `Tests/TreeFarmKitTests/Watch/WatchCourierTests.swift`; `iOS/WatchTests/Model/**`; `iOS/WatchUITests/**` |
| **b · Workout + HealthKit, both devices** | `iOS/Watch/App/Workout/**` (`ShiftWorkout`, `WorkoutDriver`, `HealthKitWorkoutDriver`, `ShiftNotifier`, `WorkoutSummaryView`, onboarding Health and notification card); `Packages/TreeFarmKit/Sources/TreeFarmKit/Watch/WorkoutPlan.swift` + `Tests/TreeFarmKitTests/Watch/WorkoutPlanTests.swift`; `iOS/App/Watch/WatchWorkoutLauncher.swift`; `iOS/Tests/Watch/WatchWorkoutLauncherTests.swift`; `iOS/WatchTests/Workout/**` |
| **c · Complications + Live Activity small family** | `iOS/Watch/Widgets/**` except its Info.plist and entitlements (bundle, provider, the four family views, relevance); `iOS/Watch/Shared/ComplicationReload.swift`; `iOS/WatchTests/Complications/**`; after the prerequisite: `iOS/Widgets/LiveActivitySmall.swift` (new), the `.supplementalActivityFamilies([.small])` modifier and `activityFamily` branch in `iOS/Widgets/TimeCardLiveActivity.swift`, `iOS/Tests/LiveActivity/LiveActivitySmallTests.swift` |
| **d · iPhone bridge, Settings toggle, watch Siri and Action button** | `iOS/App/Watch/{PhoneWatchBridge,WatchComplicationPusher}.swift`; `iOS/TimeCardCore/Sources/TimeCardCore/Watch/**` (`WatchDesk`, `WatchSettings`) + `iOS/TimeCardCore/Tests/TimeCardCoreTests/Watch/**`; `iOS/App/Views/Settings/WatchSettingsSection.swift` + **one inserted line** in `SettingsView.swift`; `iOS/Tests/Watch/PhoneWatchBridgeTests.swift`; `iOS/Watch/App/Intents/**` (10 Siri intents, `WatchShortcuts`, `WatchRowEntity` + its query, `StartShiftWorkoutIntent`, `ShiftWorkoutStyle`, `MarkNextRowIntent`, `ResumeWorkIntent`, `PauseShiftIntent`, `ResumeShiftIntent`, `ActionButtonDonor`); `iOS/WatchTests/Intents/**` |

### 8.3 Shared contracts (exact names; slice 0 lands them, stubs where marked)

**TreeFarmKit `Watch/` (slice 0 implements, with tests):**

```swift
public enum WatchWire { public static let version = 1 }
public enum WatchMessage: Codable, Sendable {
    case request(WatchRequest), reply(WatchReply), state(WatchState), workoutSummary(WorkoutSummary)
}
public struct WatchEnvelope: Codable, Sendable {
    public var v: Int; public var message: WatchMessage
    public init(_ message: WatchMessage)
    public func data() throws -> Data
    public static func decode(_ data: Data) throws -> WatchEnvelope   // throws WatchWireError.unsupportedVersion(Int)
}
// FieldCommand  += case cancelShift(UUID)
// Clock.clockIn(id: UUID = UUID(), userId:farmId:rateCents:at:shifts:)
// FieldEngine.perform(_:state:undo:now:newShiftId: UUID? = nil)
// WatchRequest  += userId: UUID?, shiftId: UUID?            (see 1.2 for what shiftId means per command)
//                  var command: FieldCommand? { get }; var isShiftScoped: Bool { get }
// WatchReply    += state: WatchState?, appliedAt: Date?, keepQueued: Bool
//                  static func unreadable(_ speech: String) -> WatchReply   // requestId = UUID(uuid: UUID_NULL)
// WatchState    += epoch: UUID, revision: Int, userId: UUID?, shiftId: UUID?, shiftStart: Date?,
//                  lastClosedShift: ClosedShift?, appliedRequestIds: [UUID], hadLunchToday: Bool,
//                  pacePerHour: Double?, farmTimeZone: String, usualStart: DateComponents?
//                  nextRows: up to 40
//                  func supersedes(_ old: WatchState?) -> Bool
//                  static func signedOut(epoch: UUID, revision: Int, now: Date) -> WatchState
public struct ClosedShift: Codable, Hashable, Sendable { public var shiftId: UUID; public var start, end: Date; public var worked: TimeInterval; public var trees: Int }
// WatchOutbox   += mutating func acknowledge(_ ids: [UUID]); mutating func removeLast() -> WatchRequest?
// WatchTiming   += static func effectiveTime(issuedAt: Date, receivedAt: Date, notBefore: Date?) -> Date
//                  static func notBefore(for: FieldCommand, state: FieldState) -> Date?
public struct WatchInbox: Codable, Sendable {
    public init(limit: Int = 500, maxAge: TimeInterval = 7 * 86_400)
    public func reply(for id: UUID) -> WatchReply?                       // state is always nil
    public mutating func record(_ reply: WatchReply, at: Date)           // strips state
    public func recentIds(_ count: Int) -> [UUID]
    public func resolve(shiftId: UUID?) -> UUID?                         // follows aliases
    public mutating func alias(_ minted: UUID, to shiftId: UUID, at: Date)
}
public enum WatchConfirm   { public static func question(for: FieldCommand, state: WatchState, now: Date) -> String? }
public enum WatchPrecheck  { public static func refusal(for: FieldCommand, state: WatchState?) -> String? }
public enum WatchOptimism  { public static func apply(_: FieldCommand, shiftId: UUID?, to: WatchState, at: Date) -> WatchState
                             public static func displayed(confirmed: WatchState?, pending: [WatchRequest]) -> WatchState? }
public enum WatchStateBuilder {
    public static func build(state: FieldState, now: Date, epoch: UUID, revision: Int, recordWorkouts: Bool,
                             appliedRequestIds: [UUID], lastAction: String?, canUndo: Bool) -> WatchState
}
public enum WatchDisplay { /* phaseTitle(_:), phaseGlyph(_:), primaryLabel(_:), placeLine(_:), queueLine(count:), noChipLine(_:), … */ }
extension SyncRecord { public func stamped(updatedAt: Date) -> SyncRecord }

public final class ResumeOnce<T: Sendable>: Sendable {
    public init(_ continuation: CheckedContinuation<T, any Error>)
    public func resume(returning: T)      // first call wins; later calls do nothing
    public func resume(throwing: any Error)
}
public protocol WatchTransport: Sendable {
    var isReachable: Bool { get }
    var hasContentPending: Bool { get }
    var events: AsyncStream<WatchTransportEvent> { get }
    func activate()
    func send(_ message: Data, timeout: Duration) async throws -> Data      // envelope in, envelope(.reply) out; ResumeOnce inside
    func post(_ message: Data) async throws                                  // no reply
    func publishContext(_ state: Data) throws                                // updateApplicationContext
    func transferComplicationState(_ state: Data) -> Bool                    // iOS only; false elsewhere
    func drained() async                                                     // every delivered context/user-info event marked done
}
public enum WatchTransportEvent: Sendable {
    case activated(paired: Bool, installed: Bool, complicationEnabled: Bool)
    case reachabilityChanged(Bool), needsUnlock(Bool)
    case received(Data, reply: WatchReplySink?)
    case contextReceived(Data, done: WatchEventDone)
    case userInfoReceived(Data, done: WatchEventDone)                        // transferCurrentComplicationUserInfo
}
public struct WatchReplySink: Sendable { public let send: @Sendable (Data) -> Void }
public struct WatchEventDone: Sendable { public let call: @Sendable () -> Void; public func callAsFunction() }
public protocol WatchOutboxStore: Sendable { func load() -> WatchOutbox?; func save(_ outbox: WatchOutbox) }

public struct WorkoutSummary: Codable, Hashable, Sendable {
    public var shiftId: UUID?; public var start, end: Date; public var activeDuration: TimeInterval
    public var activeKcal: Double?; public var avgHeartRate: Double?; public var maxHeartRate: Double?
}
public struct WorkoutLocal: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable { case none, running, paused, stopped, ended }
    public enum Origin: String, Codable, Sendable { case watchTap, phoneLaunch, actionButton, recovered }
    public var phase: Phase; public var shiftId: UUID?; public var origin: Origin?
    public var startedAt: Date?; public var stoppedAt: Date?; public var syncIdentifier: UUID?
    public var stoppedUnexpectedly: Bool; public var lastFinishedShiftId: UUID?
}
public struct WorkoutInputs: Equatable, Sendable {
    public var confirmed: WatchState?; public var outbox: [WatchRequest]; public var inFlight: [WatchRequest]
    public var refusedClockIns: [UUID]
}
public enum WorkoutStep: Equatable, Sendable {
    case start(at: Date, shiftId: UUID?, origin: WorkoutLocal.Origin), tag(shiftId: UUID)
    case pause, resume, stop(at: Date), finish(at: Date), discard, notifyStuckClockOut
}
```

**Slice a implements** (slice 0 stubs the signatures):

```swift
public actor WatchCourier {                        // TreeFarmKit/Watch/WatchCourier.swift
    public init(transport: any WatchTransport, store: any WatchOutboxStore,
                replyTimeout: Duration = .seconds(4), now: @escaping @Sendable () -> Date)
    public func submit(_ request: WatchRequest, durable: Bool) async -> CourierResult  // .replied(WatchReply) | .queued(count: Int) | .notSent(String)
    public func flush() async
    public func acknowledge(_ state: WatchState)
    public func takeBackLastQueued() -> WatchRequest?
    public var outbox: WatchOutbox { get }
    public var inFlight: [WatchRequest] { get }
    public nonisolated var updates: AsyncStream<CourierEvent> { get }   // .replied(WatchRequest, WatchReply), .queued, .waiting(UUID), .flushed, .dropped(Int)
}
@MainActor @Observable final class WatchShiftModel {          // watch app
    static let shared: WatchShiftModel
    private(set) var confirmed: WatchState?
    private(set) var displayed: WatchState?
    private(set) var reach: PhoneReach                          // .reachable | .outOfReach | .needsUnlock | .neverConnected
    private(set) var waitingCount: Int                          // outbox items not in flight
    var toast: WatchToast?
    func perform(_ command: FieldCommand, source: WatchSource) async -> WatchOutcome   // .done(reply) | .refused(reply) | .queued(String) | .notSent(String)
    func ask(_ question: FieldQuestion) async -> String
    func confirmation(for command: FieldCommand) -> String?
    func undo() async -> WatchOutcome
    func undoClockIn() async -> WatchOutcome                    // .cancelShift(displayed.shiftId), 2 min window
    func refresh() async
    func addObserver(_ observer: @escaping @MainActor (WatchModelChange) -> Void)
}
struct WatchModelChange { let displayed: WatchState?; let waitingCount: Int; let workout: WorkoutInputs }
enum WatchSource { case button, doubleTap, crown, siri, actionButton }
enum WatchHaptics { static func play(_ event: WatchHapticEvent) }
enum WaterLockGate { static func isAvailable(rating: WKWaterResistanceRating, sessionActive: Bool, foreground: Bool) -> Bool }
```

**Slice b implements:**

```swift
public enum WorkoutPlan {                                         // TreeFarmKit/Watch/WorkoutPlan.swift
    public static let backdateLimit: TimeInterval = 5 * 60
    public static let minimumDuration: TimeInterval = 2 * 60
    public static let stoppedLimit: TimeInterval = 60 * 60
    public static func reconcile(inputs: WorkoutInputs, local: WorkoutLocal, now: Date) -> [WorkoutStep]
}
@MainActor protocol WorkoutDriver: AnyObject {                  // watch app Workout/
    var local: WorkoutLocal { get }
    var events: AsyncStream<WorkoutDriverEvent> { get }       // .phase(WorkoutLocal.Phase), .metrics(heartRate: Double?, kcal: Double?), .endedUnexpectedly(String)
    func authorizationStatus() -> HealthAccess
    func requestAuthorization() async -> HealthAccess
    func start(at: Date, shiftId: UUID?, origin: WorkoutLocal.Origin) async throws
    func tag(shiftId: UUID)
    func pause(); func resume()
    func stop(at: Date) async throws
    func finish(at: Date, timeZone: String) async throws -> WorkoutSummary?   // nil when discarded (< minimumDuration)
    func discard() async
    func recover() async -> Bool
}
enum WorkoutInput: Sendable { case inputs(WorkoutInputs), phoneLaunch, recover, recordAgain }
@MainActor final class ShiftWorkout {
    static let shared: ShiftWorkout
    private(set) var live: WorkoutLive                        // heartRate, kcal, recording status, waitingClockOut, lastSummary
    func reconcile(_ inputs: WorkoutInputs)                     // yields .inputs; never awaits
    func handleLaunch()                                         // from handle(workoutConfiguration:); yields .phoneLaunch
    func recoverIfNeeded()                                      // yields .recover; runs before everything else
    func recordAgain()                                          // yields .recordAgain
}
protocol WatchWorkoutLauncher: Sendable {                       // iOS app Watch/
    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult   // .started | .timedOut | .failed(String) | .unavailable
}
```

**Slice c implements:**
- `TimeCardWatchWidgetsBundle`
- `ShiftComplication` (kind `"timecard.watch.shift"`) with `ShiftComplicationEntry(state: WatchState?, waitingCount: Int, date: Date)`
- `enum ComplicationReload { static func needsReload(old: WatchStateFile.Contents?, new: WatchStateFile.Contents) -> Bool }` in `iOS/Watch/Shared/`
- after the prerequisite, the iOS `LiveActivitySmallView(state: LiveSnapshot)`

It reads only `WatchStateFile.read() -> WatchStateFile.Contents` (`displayed: WatchState?`, `waitingCount: Int`) and `WatchDisplay`.

**Slice d implements:**

```swift
@MainActor public final class WatchDesk {                      // TimeCardCore/Watch/
    public init(actions: FieldActions, store: any KeyValueStore,
                settings: @escaping @MainActor () -> WatchSettings, now: @escaping () -> Date = Date.init)
    public func handle(_ data: Data, receivedAt: Date) -> Data   // envelope in, envelope(.reply) out, always
    public func makeState() -> WatchState                        // next revision from watch.revision; epoch from watch.epoch
    public func save(_ summary: WorkoutSummary)
}
public struct WatchSettings { public var recordWorkouts: Bool /* default true, per person */ }
@MainActor final class PhoneWatchBridge {                      // iOS app Watch/
    init(model: AppModel, transport: any WatchTransport, launcher: any WatchWorkoutLauncher, desk: WatchDesk)
    func activate()
    func publish(reason: PublishReason)                          // coalesced 250 ms; uses desk.makeState()
    private(set) var status: WatchLinkStatus                     // .noWatch | .appNotInstalled | .inReach | .outOfReach
}
```

The intents (names in 4.1 and 4.2) call only `WatchShiftModel.shared` and `ShiftWorkout.shared`.

**Wiring fixed by slice 0:**
- `WatchAppDelegate`, owned by slice a:
  - In `applicationDidFinishLaunching`: activate the transport, then `ShiftWorkout.shared.recoverIfNeeded()`.
  - In `handleActiveWorkoutRecovery()`: `ShiftWorkout.shared.recoverIfNeeded()`.
  - In `handle(_ workoutConfiguration:)`: `ShiftWorkout.shared.handleLaunch()`.
- `WatchShiftModel` registers these observers at launch: `ShiftWorkout.shared.reconcile(change.workout)`, `ActionButtonDonor.shared.update(change.displayed)`, `ShortcutParameterRefresher.shared.update(change.displayed)` (refreshes the App Shortcut parameters only when the first chip changes), and `WatchStateFile.write` followed by `ComplicationReload.reload()` (`reloadTimelines` + `invalidateRelevance`) when `ComplicationReload.needsReload` is true. It also sets `ShiftWorkout.shared.sendSummary` (a `.workoutSummary` post; false when out of reach), calls `ShiftWorkout.shared.sendPendingSummary()` after every flush, and names an Action button clock-in's minted shift to `ShiftWorkout.shared.noteActionButtonClockIn(shiftId:)` before it is sent.
- `AppModel.liveSnapshotChanged` calls `watch.publish(reason: .fieldAction)`.

### 8.4 What slice 0 landed (read this before starting a slice)

Everything in 8.3 compiles on the `watch` branch, the TreeFarmKit and TimeCardCore parts with tests, and every type another slice owns is a stub marked `// STUB: slice X replaces` with its final signature. Replace a stub in place, in its own file; keep its name and signature, because other slices call it.

**Building and testing**
- Apple tools always run with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, with `-derivedDataPath` inside your worktree (`iOS/DerivedData` and `iOS/build` are git-ignored).
- **Every new watch and iPhone-watch folder is an Xcode synced folder** (`type: syncedFolder` in `project.yml`): `iOS/Watch/App/**`, `iOS/Watch/Shared`, `iOS/Watch/Widgets`, `iOS/WatchLink`, `iOS/WatchTests/**`, `iOS/WatchUITests`, `iOS/App/Watch` and `iOS/Tests/Watch`. **Add files there and they build; never run `xcodegen` or commit `TimeCard.xcodeproj`** (slice 0 owns it). A new file anywhere else in the iPhone targets needs the lead.
- Files that sit in ordinary groups were made for you as stubs: `iOS/App/Views/Settings/WatchSettingsSection.swift` (d), `iOS/Widgets/LiveActivitySmall.swift` (c; it is also built into the app, so `TimeCardTests` can render it) and `iOS/Tests/LiveActivity/LiveActivitySmallTests.swift` (c).
- Watch tests: **boot the watch simulator first** (`xcrun simctl boot <id>; xcrun simctl bootstatus <id> -b`), then `xcodebuild test -project iOS/TimeCard.xcodeproj -scheme TimeCardWatch -only-testing:TimeCardWatchTests -destination 'platform=watchOS Simulator,id=<id>'`. On a watch that is still booting, the run fails with "Unknown application display identifier".
- The iPhone scheme `TimeCard` builds the watch app too (it is embedded), so an iPhone build catches watch compile errors.
- Xcode builds TreeFarmKit as a dynamic framework when the app and a test bundle both link it, so `FakeWatchTransport` and the app share one copy of every type.

**Contract details settled here**
- Every `Data` on the transport is a `WatchEnvelope`, also in the application context and the complication user info (a `.state` envelope under `"tc.state"`, with `"v": 1`). `WCSessionTransport` (`iOS/WatchLink`) does the mapping, delivers `receivedApplicationContext` once after activation, reports `needsUnlock` on the watch, and re-announces `.activated` on the iPhone's `sessionWatchStateDidChange`.
- `WatchTransportError` (`notActivated`, `notReachable`, `timedOut`, `failed`), `WatchEventLedger` (the `drained()` counter) and `DisconnectedWatchTransport` (no watch: the iPhone app uses it in UI-test mode and in test hosts) are in `WatchTransport.swift`.
- `WatchDisplay` holds every string and glyph in sections 3 and 4, including the complication lines (`rectangularTitle`, `rectangularDetail`, `inlineDetail`, `circularHours`, `rowNumber`, `cornerRow`) and the small Live Activity lines (`smallTitle`, `smallDetail`). `WatchPhase` (`noData`, `signedOut`, `offClock`, `working`, `lunch`, `onBreak`) and `WatchDisplay.Primary` (what the big button does, and `command(for:)`, which always sends `markRow` for the shown chip) live there too. `PhoneReach` is `WatchDisplay.Reach`. A string a slice needs that isn't there: ask the lead.
- `WatchOptimism.displayed(confirmed:pending:)` sorts by `issuedAt`, counts each id once, skips `appliedRequestIds`, and aliases a pending clock-in that the open shift will refuse, as the desk does.
- `WatchStateFile.Contents` has `displayed`, `waitingCount` and `clockOutWaiting` (for "Clock-out waiting for iPhone" on the rectangular complication).
- `WatchState`'s new fields have defaults (`epoch: WatchState.noEpoch`, `revision: 0`, …), so tests can build states by hand; the phone always sets real ones. `WatchState.signedOut` sends `recordWorkouts: true`.
- `CourierResult`, `CourierEvent` (slice a); `WorkoutLive`, `WorkoutInput`, `HealthAccess`, `WorkoutDriverEvent` (slice b); `PublishReason`, `WatchLinkStatus`, `WatchSettings.load(from:userId:)` and `save(_:to:userId:)` (slice d); `WatchLaunchResult`, `HealthKitWatchLauncher` and `UnavailableWatchLauncher` (slice b) are declared in the stubs. `AppModel` builds the launcher types and calls `WatchSettings.load`, so keep those names.
- `WatchShiftModel` has an `activate()` (the app delegate calls it first). `WatchToast` and `WatchHapticEvent` are in the stubs.
- `AppModel` makes the bridge in `init` (`watch`), awaits one `startTask`, and calls `watch.publish(reason:)` on field actions, after starting, on scene activation, and when the session's records or signed-in person change (`.sync`, `.signIn`, `.signOut`). `AppEnvironment.makeModel(mode:watchTransport:)` takes a fake transport for tests.
- `FieldActions.perform(_:at:newShiftId:)` stamps records with its own clock (`now()`, the receive time) and keeps undo pointing at the new stamps; it never asks `confirmation(for:)`.
- `FieldEngine.cancelShift` refuses a shift that isn't the open one with "That shift isn’t the one on the clock, so nothing was cancelled."; success says "Cancelled the clock-in at 7:02." with the last action "Clock-in cancelled".
- The watch app cannot link `TreeFarmKitTestSupport`, so the `-watchDemo` scripted phone (7.3) is the app's own transport (slice a).

**Signing:** simulator builds only so far. A device build wasn't attempted, so no App IDs were registered on the Personal Team (each new id and capability counts toward its weekly limit, 6).

### 8.5 Definition of done (per slice)

- Its tests are written first and are green: `swift test` in TreeFarmKit and TimeCardCore, and `xcodebuild test` for the `TimeCard` and `TimeCardWatch` schemes.
- No file outside its row was touched.
- No `// STUB` left in its own files.
- Its PR description lists its edge-case lines with test names, for the lead to merge into `docs/edge-cases.md`.
- It has small commits.

### 8.6 Integration (the lead, after slices a–d)

Slices a, b, c and d merged into `watch` without conflicts (no slice touched another's files, and every new folder is synced, so `TimeCard.xcodeproj` didn't change). What the merge settled:

- **Names that clashed:** slice b's `GloveButtonStyle` is now `WorkoutButtonStyle`; slice a's keeps the name.
- **One summary screen:** `ShiftDoneScreen` (slice a's layout, matching the other screens) worded by slice b's `WorkoutSummaryContent`, with its VoiceOver lines. Slice b's own summary view is gone; its screenshot test renders `ShiftDoneScreen` at every size.
- **One battery warning:** the workout's, when the session starts (2.8). **The Health card** (slice b) shows from `WatchRootView` before anything else while Health was never asked and recording is on; after a request that leaves Health undetermined (no entitlement, an error), it doesn't show again that launch.
- **Today's workout lines** are slice b's `WorkoutStatusLine` and `WorkoutHeartLine` ("Workout paused" on a break).
- **Words:** slice b's VoiceOver lines and "Workout paused" moved into `WatchDisplay`; the rectangular complication's waiting line is the count-free "Taps waiting for iPhone" (4.3); the small card's break title is just the phase (4.4).
- **Model wiring** (8.3): the observers, `ComplicationReload.reload()`, the summary sent after every flush, and the Action button origin. The courier's snapshot carries the newest reply state, so a flushed tap's answer and its state land in one change (1.4).
- **Queued marks count trees:** `RowChip.openTrees` (set by `WatchStateBuilder`) feeds `WatchOptimism`, so "Block 2 · N trees" moves with each waiting mark.
- **Toasts never take a tap.** On the 40 mm Controls page the workout's "Recording from 9:49" toast lay over Lunch and Break and swallowed the tap (found by the 40 mm UI flows); a glove's tap now goes through it.
- **Complication renders:** the family views and their colors moved to `Watch/Shared` (the widget keeps the family switch), so `ComplicationRenderTests` renders every family in every phase at 40 and 49 mm, and the Smart Stack card, to `$COMPLICATION_SNAPSHOTS`. The corner's curved label and tinted faces only draw on a real face (7.5).
- **Paired simulators:** `-UITestInMemory -UITestWatchLink` runs the iPhone app on the demo farm with the real watch link. `WatchPairedUITests` (watch) and `WatchLinkUITests` (iPhone) drive it, skipped unless `TEST_RUNNER_WATCH_PAIRED_PHONE=1` (7.4).
- **Linux CI:** slice a's courier tests used `async let`, which traps in `swift_task_dealloc` on Swift 6.2 for Linux; they use tasks now.
- **What the screenshots showed** (40 mm SE 3, 49 mm Ultra 3, Ultra 2): every screen fits without scrolling at the default and the largest text size; at the largest size on 40 mm the lunch header shortens to "LUNCH · SINCE…" and the button to "Back". In the renders, the inline complication on a break at 40 mm cuts "Lunch 12:40 · 3:…"; check the real inline slot on a face (7.5).
- **Largest text on the watch simulator:** `-UIPreferredContentSizeCategoryName` does nothing on watchOS, and `simctl ui content_size` is unsupported there. `xcrun simctl spawn <watch> defaults write com.apple.UIKit UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`, then relaunching the app, does change it.

---

## Key Apple sources

The full evidence, with forum threads, is in the four research reports.

- Double Tap: developer.apple.com/documentation/watchos-apps/enabling-double-tap · HIG Gestures, Workouts, Digital Crown, Action button, Live Activities
- WatchConnectivity: documentation/watchconnectivity/wcsession (isReachable, sendMessage, updateApplicationContext, transferCurrentComplicationUserInfo, session(_:didReceiveUserInfo:)) · WWDC21 10003
- Swift 6 and WatchConnectivity: developer.apple.com/forums/thread/771525, /849472
- Workouts: documentation/healthkit/running-workout-sessions · HKWorkoutSession (stopActivity, end) · HKLiveWorkoutBuilder · HKHealthStore startWatchApp · WKApplicationDelegate handleActiveWorkoutRecovery · WWDC21 10009, WWDC23 10023, WWDC25 322
- Action button: documentation/appintents/actionbuttonarticle · StartWorkoutIntent · PauseWorkoutIntent · ResumeWorkoutIntent
- Siri on the watch: WWDC23 10102 · AppShortcutsProvider · developer.apple.com/forums/thread/840647
- Always On: documentation/watchos-apps/designing-your-app-for-the-always-on-state
- Water Lock: documentation/watchkit/wkinterfacedevice/enablewaterlock() · WKWaterResistanceRating
- Live Activity on the watch: WWDC24 10068, 10098 · documentation/activitykit/creating-custom-views-for-live-activities · WKSupportsLiveActivityLaunchAttributeTypes
- Complications: documentation/widgetkit (displaying dynamic dates, accented rendering and Liquid Glass, keeping a widget up to date, widget suggestions in Smart Stacks)
- Personal Team limits: developer.apple.com/support/compare-memberships · supported capabilities (watchOS)
