import Foundation
import OSLog
import TimeCardCore

/// Starts, updates and ends the lock-screen Live Activity from `LiveSnapshot`s.
///
/// Two things feed it. `FieldActions` hands it a snapshot right after every field action
/// (Siri, lock-screen buttons, controls, the app), so a tap shows at once. And the app's
/// shared controller follows the session through `LiveActivityFeed`, so everything else
/// reaches the lock screen too: rows other people marked and blocks changed in a sync, shifts
/// edited in the app, signing out, switching farms, and the app coming forward. The rules:
///
/// - On the clock: keep exactly one activity for the signed-in person, updated in place.
/// - Off the clock or signed out: end it right away, and cancel the eight-hour reminder.
/// - Still opening: while the app is loading its store and session (a cold launch), a missing
///   snapshot means "not known yet", not "off the clock", so nothing is ended or started.
/// - Swiped away, or ended by iOS: start a new one on the next action or foreground. An activity
///   iOS ended stays on the lock screen, frozen, for hours; it's taken down first.
/// - iOS ends Live Activities after eight hours. Each activity is marked stale at 7 h 50 min,
///   when a local notification says "Open Time Card to keep your lock-screen timer". Opening
///   the app restarts any activity four hours old or older, so the clock starts over.
///   From the lock screen an old activity is only updated, never swapped under a thumb.
/// - Live Activities turned off in Settings: nothing starts.
///
/// The decisions are in `LiveActivityPlan` (pure), the ActivityKit calls behind
/// `LiveActivityHosting`, so all of it is tested without ActivityKit.
@MainActor
final class LiveActivityController {
    private static let log = Logger(subsystem: "TimeCard", category: "LiveActivity")

    private let host: LiveActivityHosting
    private let reminders: LiveActivityReminding
    private var ledger: LiveActivityLedger
    private let now: () -> Date

    /// The newest request not yet applied. Quick updates collapse into the latest one.
    private var pending: Request?
    private var worker: Task<Void, Never>?
    /// False until the session has opened. Until then a request with no snapshot is held.
    private(set) var isSessionLoaded: Bool
    /// The shared controller follows the session through this.
    private var feed: LiveActivityFeed?

    private struct Request {
        var snapshot: LiveSnapshot?
        var attributes: TimeCardActivityAttributes?
    }

    /// What each activity was last given, so a reading that would draw the same card (the
    /// feed reads again after every sync) isn't sent to ActivityKit again.
    private var shown: [String: Shown] = [:]

    private struct Shown {
        var snapshot: LiveSnapshot
        var staleDate: Date?
    }

    /// - Parameter waitsForSession: hold requests with no snapshot until the session has
    ///   opened (`update(_:attributes:sessionLoaded:)` says so). The app's controller does;
    ///   tests that only exercise the rules don't need to.
    init(host: LiveActivityHosting, reminders: LiveActivityReminding, ledger: LiveActivityLedger,
         now: @escaping () -> Date = Date.init, waitsForSession: Bool = false) {
        self.host = host
        self.reminders = reminders
        self.ledger = ledger
        self.now = now
        self.isSessionLoaded = !waitsForSession
    }

    /// The real thing: ActivityKit, local notifications, and start times kept in UserDefaults.
    /// UI-test launches never ask for notification permission, so no alert covers the app.
    ///
    /// The shared model's controller also follows that model's session (`LiveActivityFeed`).
    convenience init() {
        self.init(host: ActivityKitHost(), reminders: NotificationReminders(asksPermission: LaunchMode.current() == .live),
                  ledger: DefaultsLedger(), now: Date.init, waitsForSession: true)
        LiveActivityLaunchScript.runIfRequested()
        // AppModel makes this while `AppModel.shared` is being made, so it waits a turn.
        // Other models (tests make their own) don't get a feed.
        Task { @MainActor [weak self] in
            let model = AppModel.shared
            guard let self, model.liveActivity === self else { return }
            self.follow { model.liveActivityReading }
        }
    }

    /// Keeps the activity in step with whatever `read` reads, from now on.
    func follow(settle: Duration = LiveActivityFeed.settle, _ read: @escaping @MainActor () -> LiveActivityReading) {
        feed?.stop()
        feed = LiveActivityFeed(controller: self, settle: settle, read: read)
        feed?.start()
    }

    /// Called after every field action, by the feed, and when the app comes forward.
    /// `nil` means off the clock, once the session has loaded: end the activity.
    ///
    /// - Parameter sessionLoaded: the session has opened (or no one is signed in), so a
    ///   missing snapshot really means off the clock. A snapshot proves it too.
    func update(_ snapshot: LiveSnapshot?, attributes: TimeCardActivityAttributes?, sessionLoaded: Bool = false) {
        if sessionLoaded || (snapshot != nil && attributes != nil) { isSessionLoaded = true }
        pending = Request(snapshot: snapshot, attributes: attributes)
        guard isSessionLoaded else {
            Self.log.info("Live Activity: waiting for the session to open")
            return
        }
        guard worker == nil else { return }
        // A lock-screen button's intent may be suspended as soon as it returns; keep running
        // until ActivityKit has the update.
        let release = host.holdAwake()
        worker = Task { [weak self] in
            await self?.drain()
            release()
        }
    }

    /// Waits until every update so far has reached ActivityKit. `IntentRunner.afterChange`
    /// waits for it inside a background task, so iOS doesn't suspend the app between saving a
    /// row and showing it.
    func waitUntilIdle() async {
        while let worker {
            await worker.value
        }
    }

    private func drain() async {
        while let request = pending {
            pending = nil
            await apply(request)
        }
        worker = nil
    }

    private func apply(_ request: Request) async {
        let at = now()
        let running = host.activities()
        // Forget start times of activities that are gone.
        ledger.starts = ledger.starts.filter { id, _ in running.contains { $0.id == id && $0.isLive } }

        let steps = LiveActivityPlan.steps(
            clockedIn: request.snapshot != nil,
            attributes: request.attributes,
            enabled: host.areActivitiesEnabled,
            running: running,
            startedAt: ledger.starts,
            appIsActive: host.isAppActive,
            now: at)

        Self.log.info("Live Activity plan: \(String(describing: steps), privacy: .public)")
        var started = true
        for step in steps {
            switch step {
            case .start(let staleDate):
                guard let snapshot = request.snapshot, let attributes = request.attributes else { continue }
                do {
                    let id = try host.start(attributes, snapshot, staleDate: staleDate)
                    ledger.starts[id] = at
                    shown[id] = Shown(snapshot: snapshot, staleDate: staleDate)
                    started = true
                } catch {
                    // Not allowed right now (say, from the background); the next action or foreground tries again.
                    Self.log.error("Live Activity didn’t start: \(String(describing: error), privacy: .public)")
                    started = false
                }
            case .update(let id, let staleDate):
                guard let snapshot = request.snapshot else { continue }
                if let last = shown[id], last.staleDate == staleDate, LiveActivityDisplay.sameOnScreen(last.snapshot, snapshot) { continue }
                await host.update(id: id, snapshot, staleDate: staleDate)
                shown[id] = Shown(snapshot: snapshot, staleDate: staleDate)
            case .end(let id):
                await host.end(id: id, request.snapshot)
                ledger.starts[id] = nil
                shown[id] = nil
            case .scheduleReminder(let date):
                guard started else { continue }
                await reminders.schedule(at: date, askPermission: host.isAppActive)
            case .cancelReminder:
                await reminders.cancel()
            }
        }
    }
}

/// A Live Activity as the controller sees it.
struct LiveActivityRecord: Equatable {
    enum State: Equatable {
        case active, stale
        /// Ended (by iOS at eight hours, say) but still on the lock screen, frozen, for up to
        /// four more hours, with buttons that no longer match the field.
        case ended
        /// Swiped away or taken down: gone.
        case dismissed
    }

    var id: String
    var attributes: TimeCardActivityAttributes
    var state: State

    /// Active or stale: it can still be updated.
    var isLive: Bool { state == .active || state == .stale }
}

enum LiveActivityStep: Equatable {
    /// Request a new activity showing the snapshot.
    case start(staleDate: Date?)
    case update(id: String, staleDate: Date?)
    /// End it and take it off the lock screen now (also one iOS has already ended).
    case end(id: String)
    case scheduleReminder(at: Date)
    case cancelReminder
}

/// What to do with the running activities for one snapshot. Pure, so every rule is tested.
enum LiveActivityPlan {
    /// iOS ends a Live Activity this long after it starts.
    static let lifetime: TimeInterval = 8 * 3600
    /// The reminder (and the stale mark) come this long after the start: 7 h 50 min.
    static let reminderAfter: TimeInterval = lifetime - 10 * 60
    /// With the app open, an activity at least this old is swapped for a fresh one.
    static let refreshAge: TimeInterval = 4 * 3600

    static func steps(clockedIn: Bool, attributes: TimeCardActivityAttributes?, enabled: Bool, running: [LiveActivityRecord],
                      startedAt: [String: Date], appIsActive: Bool, now: Date) -> [LiveActivityStep] {
        let live = running.filter(\.isLive)
        // Ended ones still showing old rows and buttons come down first, so there's never a
        // frozen card beside the real one.
        let leftOver: [LiveActivityStep] = running.filter { $0.state == .ended }.map { .end(id: $0.id) }
        guard clockedIn, let attributes else {
            return leftOver + live.map { .end(id: $0.id) } + [.cancelReminder]
        }
        guard enabled else { return leftOver + [.cancelReminder] }

        // Keep the newest activity that belongs to this person; end any others.
        let mine = live.filter { $0.attributes == attributes }
            .sorted { (startedAt[$0.id] ?? .distantPast) > (startedAt[$1.id] ?? .distantPast) }
        let keep = mine.first
        var steps: [LiveActivityStep] = leftOver + live.filter { $0.id != keep?.id }.map { .end(id: $0.id) }
        let fresh: [LiveActivityStep] = [.start(staleDate: now + reminderAfter), .scheduleReminder(at: now + reminderAfter)]

        guard let keep else { return steps + fresh }
        let started = startedAt[keep.id]
        let old = started.map { now.timeIntervalSince($0) >= refreshAge } ?? true
        if appIsActive && old {
            steps.append(.end(id: keep.id))
            return steps + fresh
        }
        steps.append(.update(id: keep.id, staleDate: started.map { $0 + reminderAfter }))
        return steps
    }
}
