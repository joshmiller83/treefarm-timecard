import Foundation
import Observation
import TreeFarmKit
import WatchKit

// The shift's workout session (docs/watch.md 2, docs/health.md). Every shift records as an Apple
// Watch workout: clock-in starts an outdoor Tree care workout (Other in Health), lunch and breaks
// pause it, clock-out ends it, and the running session keeps Time Card on the wrist for the whole
// shift. With Record route on, GPS feeds the workout's route while it runs.
//
// It never decides on its own. On each input it asks `WorkoutPlan` and does exactly that, from
// one serial queue consumed by one main-actor loop: `.recover` always runs first, `.inputs`
// coalesce to the newest, and the other inputs keep their order. The entry points only enqueue,
// so two quick changes can't start two sessions and a phone launch can't race recovery. [HK-P10]

/// What the Today page, the banners and the summary show about the workout.
struct WorkoutLive: Equatable, Sendable {
    enum Recording: Equatable, Sendable {
        /// "Record shifts as workouts" is off on the phone.
        case off
        /// Health access was denied or never asked.
        case notAuthorized
        /// No session (off the clock).
        case idle
        case recording
        case paused
        /// Stopped at a watch clock-out, waiting for the phone ("Clock-out waiting for iPhone").
        case waitingForClockOut
        /// Ended from outside the app: "Recording stopped [Record again]".
        case stoppedUnexpectedly
    }

    var heartRate: Double?
    var kcal: Double?
    var steps: Double?
    var meters: Double?
    var recording: Recording = .idle
    /// Record route is on, but the watch may not use location: "Route off · Allow Location…".
    var routeOff = false
    var waitingClockOut = false
    var lastSummary: WorkoutSummary?
}

enum WorkoutInput: Equatable, Sendable {
    case inputs(WorkoutInputs)
    /// `handle(_ workoutConfiguration:)`: a phone clock-in launched the app.
    case phoneLaunch
    case recover
    case recordAgain
    /// The driver saw the session end from outside the app.
    case endedUnexpectedly(String)
}

/// The serial queue's order: recovery first, inputs coalesced to the newest, the rest in order.
struct WorkoutInputQueue: Sendable {
    private var items: [WorkoutInput] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func push(_ input: WorkoutInput) {
        switch input {
        case .inputs: items.removeAll { if case .inputs = $0 { true } else { false } }
        case .recover: if items.contains(.recover) { return }
        default: break
        }
        items.append(input)
    }

    mutating func pop() -> WorkoutInput? {
        if let index = items.firstIndex(of: .recover) { return items.remove(at: index) }
        return items.isEmpty ? nil : items.removeFirst()
    }

    mutating func removeRecovery() {
        items.removeAll { $0 == .recover }
    }
}

@MainActor
@Observable
final class ShiftWorkout {
    static let shared = ShiftWorkout.makeShared()

    /// Everything the workout needs from the watch around it, replaceable in tests.
    struct Hooks {
        var now: @MainActor () -> Date = { Date() }
        /// A session starts only in the foreground, except from a phone launch. [HK-F5, HK-P1]
        var isForeground: @MainActor () -> Bool = { WKApplication.shared().applicationState != .background }
        /// 0...1, or negative when unknown.
        var battery: @MainActor () -> Double = {
            let device = WKInterfaceDevice.current()
            device.isBatteryMonitoringEnabled = true
            return Double(device.batteryLevel)
        }
        /// A short line for the toast: "Recording from 7:14", the battery warning.
        var notice: @MainActor (String) -> Void = { WatchShiftModel.shared.toast = WatchToast(text: $0, kind: .info) }
        var haptic: @MainActor (WatchHapticEvent) -> Void = { WatchHaptics.play($0) }
        var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    }

    private(set) var live = WorkoutLive()
    /// Whether Health lets the watch record workouts.
    private(set) var access: HealthAccess
    /// Health was allowed before steps and distance: the card asks once more.
    private(set) var asksForMore: Bool
    /// Whether the watch may use GPS for the route.
    private(set) var location: LocationAccess
    private var askingStep: HealthOnboardingStep?
    /// The card was answered this launch. A request that failed (Health still "not determined")
    /// asks again at the next launch, never in a loop now.
    private var askedThisLaunch = false
    /// The same for the location card.
    private var askedLocationThisLaunch = false

    /// Sends a closed field log to the phone (`transferFile`, which waits out of reach).
    @ObservationIgnored var sendFieldLog: (@MainActor (URL) -> Void)?

    /// Delivers a finished shift's summary to the phone (`.workoutSummary`, no reply). False when
    /// the phone is out of reach: the summary waits in its one slot for `sendPendingSummary()`.
    @ObservationIgnored var sendSummary: (@MainActor (WorkoutSummary) async -> Bool)?

    @ObservationIgnored private let driver: any WorkoutDriver
    @ObservationIgnored private let notifier: any ShiftNotifier
    @ObservationIgnored private let store: WorkoutStore
    @ObservationIgnored private let hooks: Hooks
    @ObservationIgnored private var queue = WorkoutInputQueue()
    @ObservationIgnored private var inputs = WorkoutInputs()
    /// No decision is made before the model reported its state and outbox once: a recovered,
    /// stopped session must see its waiting clock-out.
    @ObservationIgnored private var hasInputs = false
    @ObservationIgnored private var recovered = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var deadline: (stoppedAt: Date, task: Task<Void, Never>)?
    /// A stuck clock-out reminder may be waiting with the system. Unknown at launch (one may
    /// have outlived the app), so the first look with no clock-out waiting takes it back.
    @ObservationIgnored private var reminderArmed = true
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var actionButtonShifts: [UUID] = []
    /// Observed: the summary screen comes and goes with it.
    private var summaries: WorkoutStore.Summaries

    init(driver: any WorkoutDriver, notifier: any ShiftNotifier, store: WorkoutStore, hooks: Hooks = Hooks()) {
        self.driver = driver
        self.notifier = notifier
        self.store = store
        self.hooks = hooks
        self.access = driver.authorizationStatus()
        self.asksForMore = driver.asksForMore
        self.location = driver.locationStatus()
        self.summaries = store.summaries()
        live.lastSummary = summaries.last
        let events = driver.events
        eventsTask = Task { [weak self] in
            for await event in events { self?.handle(event) }
        }
        refreshLive()
    }

    private static func makeShared() -> ShiftWorkout {
        let store = WorkoutStore()
        let demo = ProcessInfo.processInfo.arguments.contains("-watchDemo")
        let driver: any WorkoutDriver = demo ? DemoWorkoutDriver() : HealthKitWorkoutDriver(store: store)
        let workout = ShiftWorkout(driver: driver, notifier: UserNotificationShiftNotifier(), store: store)
        // Starting a session needs the foreground: a state that arrived in the background starts
        // its workout when the app comes forward.
        NotificationCenter.default.addObserver(forName: WKApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ShiftWorkout.shared.recheck() }
        }
        return workout
    }

    // MARK: Entry points (they only enqueue)

    /// The model's newest confirmed state, outbox, in-flight taps and refused clock-ins.
    func reconcile(_ inputs: WorkoutInputs) {
        self.inputs = inputs
        hasInputs = true
        refreshLive()
        enqueue(.inputs(inputs))
    }

    /// From `handle(_ workoutConfiguration:)` (a phone clock-in's `startWatchApp`).
    func handleLaunch() {
        enqueue(.phoneLaunch)
    }

    /// Runs before everything else: at launch and from `handleActiveWorkoutRecovery()`.
    func recoverIfNeeded() {
        enqueue(.recover)
    }

    /// The "Record again" button.
    func recordAgain() {
        enqueue(.recordAgain)
    }

    /// Looks again with the same inputs: the app came forward, or a deadline passed.
    func recheck() {
        guard hasInputs else { return }
        enqueue(.inputs(inputs))
    }

    /// The Action button's first press clocks in under this minted id: its workout's origin is
    /// the Action button.
    func noteActionButtonClockIn(shiftId: UUID) {
        actionButtonShifts = Array((actionButtonShifts + [shiftId]).suffix(10))
    }

    // MARK: Health access and the first-launch card

    /// The card's step (docs/watch.md 2.4, docs/health.md 2 and 3), nil when there's no card:
    /// - `.health` while recording is on (or nothing's known yet) and Health was never asked. It
    ///   stays up through the notification question. The Action button only launches the app
    ///   until Health was asked once, so it comes early.
    /// - `.healthMore` once after an update that reads more from Health (steps and distance).
    /// - `.location` once Record route is on and location was never asked.
    var onboardingStep: HealthOnboardingStep? {
        if let askingStep { return askingStep }
        let state = inputs.confirmed
        if !askedThisLaunch, state?.recordWorkouts ?? true {
            if access == .notDetermined { return .health }
            if access == .authorized, asksForMore { return .healthMore }
        }
        if !askedLocationThisLaunch, access == .authorized, location == .notDetermined, state?.recordRoute == true {
            return .location
        }
        return nil
    }

    var needsHealthOnboarding: Bool { onboardingStep != nil }

    /// "Allow Health", then (the first time) "Remind me if a clock-out gets stuck."
    func allowHealth() async {
        let first = onboardingStep != .healthMore
        askingStep = first ? .health : .healthMore
        access = await driver.requestAuthorization()
        asksForMore = driver.asksForMore
        if first {
            askingStep = .reminder
            _ = await notifier.requestAuthorization()
        }
        askedThisLaunch = true
        askingStep = nil
        refreshLive()
        recheck()
    }

    /// "Allow Location", for the route.
    func allowLocation() async {
        askingStep = .location
        location = await driver.requestLocation()
        askedLocationThisLaunch = true
        askingStep = nil
        applyRoute()
        refreshLive()
    }

    // MARK: The shift summary

    /// The summary to show: after a finish the watch ran at once, after a phone clock-out the next
    /// time the app opens, within an hour of the shift's end. Nil once Done was tapped.
    func summaryToShow(now: Date) -> WorkoutSummary? {
        guard let last = summaries.last, !summaries.dismissed, now < last.end.addingTimeInterval(3600) else { return nil }
        return last
    }

    func dismissSummary() {
        summaries.dismissed = true
        store.save(summaries)
    }

    /// Sends the summary waiting in its slot (call after every outbox flush).
    func sendPendingSummary() async {
        guard let pending = summaries.pending, let sendSummary else { return }
        guard await sendSummary(pending), summaries.pending == pending else { return }
        summaries.pending = nil
        store.save(summaries)
    }

    /// For tests: waits until the queue is empty.
    func settled() async {
        while let loop {
            await loop.value
        }
    }

    // MARK: The queue

    private func enqueue(_ input: WorkoutInput) {
        queue.push(input)
        guard loop == nil else { return }
        loop = Task { await drain() }
    }

    private func drain() async {
        while let input = next() {
            await process(input)
            refreshLive()
        }
        loop = nil
    }

    private func next() -> WorkoutInput? {
        guard recovered else {
            recovered = true
            queue.removeRecovery()
            return .recover
        }
        return queue.pop()
    }

    private func process(_ input: WorkoutInput) async {
        access = driver.authorizationStatus()
        asksForMore = driver.asksForMore
        location = driver.locationStatus()
        switch input {
        case .recover:
            _ = await driver.recover()
            recovered = true
            await settle()
        case .inputs:
            await settle()
        case .phoneLaunch:
            await run(WorkoutPlan.phoneLaunch(inputs: inputs, local: driver.local, now: hooks.now()), inBackground: true)
            await settle()
        case .recordAgain:
            await run(WorkoutPlan.recordAgain(inputs: inputs, local: driver.local, now: hooks.now()), inBackground: true)
            await settle()
        case .endedUnexpectedly:
            await salvage()
        }
        scheduleDeadline()
        takeBackReminderIfAnswered()
        applyRoute()
    }

    /// GPS for the route only with Record route on and location allowed; the driver runs it only
    /// while the session runs. The field log follows its own switch (docs/gis.md 10).
    private func applyRoute() {
        driver.recordRoute(inputs.confirmed?.recordRoute == true && location == .authorized)
        driver.recordFieldLog(inputs.confirmed?.fieldLog == true)
    }

    /// Reconciles until nothing is left to do (a finish can be followed by a start), at most a
    /// few passes, stopping at the first step that fails.
    private func settle() async {
        guard hasInputs else { return }
        for _ in 0..<4 {
            let steps = WorkoutPlan.reconcile(inputs: inputs, local: driver.local, now: hooks.now())
            guard !steps.isEmpty, await run(steps, inBackground: false) else { return }
        }
    }

    /// Does the steps in order. False when one couldn't be done (the next input tries again).
    @discardableResult
    /// `inBackground`: a phone launch (`handle(_ workoutConfiguration:)`) may start a session
    /// without the app on screen, and Record again is the person's own tap; a start that only a
    /// state change asked for waits for the foreground.
    private func run(_ steps: [WorkoutStep], inBackground: Bool) async -> Bool {
        for step in steps {
            switch step {
            case .start(let date, let shiftId, let origin):
                guard await start(at: date, shiftId: shiftId, origin: origin, inBackground: inBackground) else { return false }
            case .tag(let shiftId):
                driver.tag(shiftId: shiftId)
            case .pause:
                driver.pause()
            case .resume:
                driver.resume()
            case .stop(let date):
                guard (try? await driver.stop(at: date)) != nil else { return false }
                // Left with the system, so it still comes if the session ends from outside or
                // the app is gone by then.
                let stoppedAt = driver.local.stoppedAt ?? date
                reminderArmed = true
                await notifier.scheduleStuckClockOut(at: stoppedAt.addingTimeInterval(WorkoutPlan.stoppedLimit))
            case .finish(let date):
                let summary = try? await driver.finish(at: date, timeZone: timeZone)
                if let summary = summary ?? nil { deliver(summary) }
            case .discard:
                await driver.discard()
            case .notifyStuckClockOut:
                await notifier.notifyStuckClockOut()
            }
        }
        return true
    }

    private func start(at date: Date, shiftId: UUID?, origin: WorkoutLocal.Origin, inBackground: Bool) async -> Bool {
        guard access == .authorized, inBackground || hooks.isForeground() else { return false }
        let origin = origin == .watchTap && shiftId.map(actionButtonShifts.contains) == true ? .actionButton : origin
        do {
            try await driver.start(at: date, shiftId: shiftId, origin: origin)
        } catch {
            return false
        }
        live.heartRate = nil
        live.kcal = nil
        live.steps = nil
        live.meters = nil
        // A watch tap already played its own haptic; a workout the phone or a recovery started didn't.
        if origin == .phoneLaunch || origin == .recovered { hooks.haptic(.started) }
        if let warning = WatchDisplay.batteryWarning(level: hooks.battery()) {
            hooks.notice(warning)
        } else if let shiftStart = shiftStart(of: shiftId), date.timeIntervalSince(shiftStart) > 60 {
            hooks.notice(WatchDisplay.recordingFrom(date, state: inputs.confirmed))
        }
        return true
    }

    /// The session ended from outside: save what was collected, keep the shift on the clock and
    /// offer "Record again". Never a clock-out. [HK-F11, HK-P11]
    ///
    /// A stopped session is different: the person already clocked out on the watch and the
    /// clock-out only waits for the phone. That's a finished shift, ending at the stop, with its
    /// summary; the stuck clock-out reminder stays with the system.
    private func salvage() async {
        let local = driver.local
        guard local.hasSession else { return }
        if local.phase == .stopped {
            let summary = try? await driver.finish(at: local.stoppedAt ?? hooks.now(), timeZone: timeZone)
            if let summary = summary ?? nil { deliver(summary) }
            return
        }
        _ = await driver.salvage(at: hooks.now(), timeZone: timeZone)
        hooks.haptic(.stopped)
    }

    /// Takes the stuck clock-out reminder back once no watch clock-out waits (the phone answered).
    /// A clock-out that's still waiting keeps it, session or not.
    private func takeBackReminderIfAnswered() {
        guard hasInputs, reminderArmed, driver.local.phase != .stopped, WorkoutPlan.waitingClockOuts(inputs).isEmpty else { return }
        reminderArmed = false
        notifier.cancelStuckClockOut()
    }

    private func handle(_ event: WorkoutDriverEvent) {
        switch event {
        case .metrics(let heartRate, let kcal, let steps, let meters):
            guard driver.local.hasSession else { return }
            if let heartRate { live.heartRate = heartRate }
            if let kcal { live.kcal = kcal }
            if let steps { live.steps = steps }
            if let meters { live.meters = meters }
        case .phase:
            refreshLive()
        case .endedUnexpectedly(let reason):
            enqueue(.endedUnexpectedly(reason))
        case .fieldLog(let file):
            sendFieldLog?(file)
        }
    }

    /// A finished shift: show it, keep it, and send it to the phone (or wait for the next flush).
    private func deliver(_ summary: WorkoutSummary) {
        summaries = WorkoutStore.Summaries(last: summary, dismissed: false, pending: summary)
        store.save(summaries)
        live.lastSummary = summary
        Task { await sendPendingSummary() }
    }

    /// While a clock-out waits, look again when its hour is up (the stuck-clock-out notification).
    private func scheduleDeadline() {
        let local = driver.local
        guard local.phase == .stopped, let stoppedAt = local.stoppedAt else {
            deadline?.task.cancel()
            deadline = nil
            return
        }
        guard deadline?.stoppedAt != stoppedAt else { return }
        deadline?.task.cancel()
        let wait = max(0, stoppedAt.addingTimeInterval(WorkoutPlan.stoppedLimit).timeIntervalSince(hooks.now())) + 1
        let sleep = hooks.sleep
        let task = Task { [weak self] in
            guard (try? await sleep(.seconds(wait))) != nil else { return }
            self?.deadline = nil
            self?.recheck()
        }
        deadline = (stoppedAt, task)
    }

    private func refreshLive() {
        let local = driver.local
        let state = inputs.confirmed
        // The session's clock-out (or the open shift's) still waits for the phone, even after a
        // stopped session finished: the person is clocking out, never "Recording stopped".
        let clockingOut = [local.shiftId, state?.shiftId].contains { WorkoutPlan.waitingClockOut(for: $0, inputs) != nil }
        live.waitingClockOut = local.phase == .stopped || clockingOut
        live.recording = switch local.phase {
        case .running: .recording
        case .paused: .paused
        case .stopped: .waitingForClockOut
        case .none, .ended:
            if state?.recordWorkouts == false {
                .off
            } else if access != .authorized {
                .notAuthorized
            } else if local.stoppedUnexpectedly, !clockingOut, let state, state.signedIn, state.isClockedIn,
                      local.shiftId == nil || local.shiftId == state.shiftId {
                .stoppedUnexpectedly
            } else {
                .idle
            }
        }
        if !local.hasSession {
            live.heartRate = nil
            live.kcal = nil
            live.steps = nil
            live.meters = nil
        }
        live.routeOff = state?.recordRoute == true && location == .denied
    }

    private var timeZone: String {
        inputs.confirmed?.farmTimeZone ?? TimeZone.current.identifier
    }

    /// The shift's start when the state shows that shift on the clock.
    private func shiftStart(of shiftId: UUID?) -> Date? {
        guard let state = inputs.confirmed, let shiftId, state.shiftId == shiftId else { return nil }
        return state.shiftStart
    }
}
