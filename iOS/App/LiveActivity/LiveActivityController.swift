import Foundation
import OSLog
import TimeCardCore

/// Starts, updates and ends the lock-screen Live Activity from `LiveSnapshot`s.
///
/// AppModel calls `update(_:attributes:)` after every field action (Siri, lock-screen
/// buttons, controls, the app) and whenever the app comes forward. The rules:
///
/// - On the clock: keep exactly one activity for the signed-in person, updated in place.
/// - Off the clock or signed out: end it right away, and cancel the eight-hour reminder.
/// - Swiped away, or ended by iOS: start a new one on the next action or foreground.
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

    private struct Request {
        var snapshot: LiveSnapshot?
        var attributes: TimeCardActivityAttributes?
    }

    init(host: LiveActivityHosting, reminders: LiveActivityReminding, ledger: LiveActivityLedger, now: @escaping () -> Date = Date.init) {
        self.host = host
        self.reminders = reminders
        self.ledger = ledger
        self.now = now
    }

    /// The real thing: ActivityKit, local notifications, and start times kept in UserDefaults.
    /// UI-test launches never ask for notification permission, so no alert covers the app.
    convenience init() {
        self.init(host: ActivityKitHost(), reminders: NotificationReminders(asksPermission: LaunchMode.current() == .live),
                  ledger: DefaultsLedger(), now: Date.init)
        LiveActivityLaunchScript.runIfRequested()
    }

    /// Called after every field action, and when the app comes forward.
    /// `nil` means off the clock: end the activity.
    func update(_ snapshot: LiveSnapshot?, attributes: TimeCardActivityAttributes?) {
        pending = Request(snapshot: snapshot, attributes: attributes)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    /// Waits until every update so far has reached ActivityKit. Intents call this before
    /// returning, so iOS doesn't suspend the app between saving a row and showing it.
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
                    started = true
                } catch {
                    // Not allowed right now (say, from the background); the next action or foreground tries again.
                    Self.log.error("Live Activity didn’t start: \(String(describing: error), privacy: .public)")
                    started = false
                }
            case .update(let id, let staleDate):
                guard let snapshot = request.snapshot else { continue }
                await host.update(id: id, snapshot, staleDate: staleDate)
            case .end(let id):
                await host.end(id: id, request.snapshot)
                ledger.starts[id] = nil
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
    var id: String
    var attributes: TimeCardActivityAttributes
    /// Active or stale. False once it's ended or the person swiped it away.
    var isLive: Bool
}

enum LiveActivityStep: Equatable {
    /// Request a new activity showing the snapshot.
    case start(staleDate: Date?)
    case update(id: String, staleDate: Date?)
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
        guard clockedIn, let attributes else {
            return live.map { .end(id: $0.id) } + [.cancelReminder]
        }
        guard enabled else { return [.cancelReminder] }

        // Keep the newest activity that belongs to this person; end any others.
        let mine = live.filter { $0.attributes == attributes }
            .sorted { (startedAt[$0.id] ?? .distantPast) > (startedAt[$1.id] ?? .distantPast) }
        let keep = mine.first
        var steps: [LiveActivityStep] = live.filter { $0.id != keep?.id }.map { .end(id: $0.id) }
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
