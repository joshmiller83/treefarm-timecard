import Foundation
import TreeFarmKit
@testable import TimeCardWatch

/// A `WorkoutDriver` with no HealthKit behind it (docs/watch.md 7.1): records every call with its
/// dates, can be made slow, and emits state, metric and unexpected-end events on demand.
@MainActor
final class FakeWorkoutDriver: WorkoutDriver {
    enum Call: Equatable {
        case start(Date, UUID?, WorkoutLocal.Origin)
        case tag(UUID)
        case pause
        case resume
        case stop(Date)
        case finish(Date, String)
        case salvage(Date)
        case discard
        case recover
    }

    private(set) var calls: [Call] = []
    var local: WorkoutLocal
    let events: AsyncStream<WorkoutDriverEvent>
    private let continuation: AsyncStream<WorkoutDriverEvent>.Continuation

    var access: HealthAccess = .authorized
    /// What `requestAuthorization` grants.
    var granted: HealthAccess = .authorized
    private(set) var authorizationRequests = 0
    /// Makes `start` and `recover` slow, to race other inputs against them.
    var startDelay: Duration?
    var recoverDelay: Duration?
    /// The session recovery reattaches, or nil when there is none.
    var recoverable: WorkoutLocal?
    var failStart = false
    /// What the builder measured, for the summary.
    var kcal: Double? = 1_120
    var heartRate: (avg: Double, max: Double)? = (104, 151)
    /// Seconds paused, taken off the active duration.
    var pausedTime: TimeInterval = 0

    struct Failure: Error {}

    init(local: WorkoutLocal = WorkoutLocal()) {
        self.local = local
        (events, continuation) = AsyncStream.makeStream()
    }

    func emit(_ event: WorkoutDriverEvent) {
        continuation.yield(event)
    }

    var starts: [Call] { calls.filter { if case .start = $0 { true } else { false } } }

    func authorizationStatus() -> HealthAccess { access }

    func requestAuthorization() async -> HealthAccess {
        authorizationRequests += 1
        access = granted
        return access
    }

    func start(at date: Date, shiftId: UUID?, origin: WorkoutLocal.Origin) async throws {
        calls.append(.start(date, shiftId, origin))
        if let startDelay { try await Task.sleep(for: startDelay) }
        if failStart { throw Failure() }
        local = local.started(at: date, shiftId: shiftId, origin: origin, syncIdentifier: UUID())
    }

    func tag(shiftId: UUID) {
        calls.append(.tag(shiftId))
        local = local.tagged(shiftId)
    }

    func pause() {
        calls.append(.pause)
        local = local.with(phase: .paused)
    }

    func resume() {
        calls.append(.resume)
        local = local.with(phase: .running)
    }

    func stop(at date: Date) async throws {
        calls.append(.stop(date))
        local = local.stopped(at: date)
    }

    func finish(at date: Date, timeZone: String) async throws -> WorkoutSummary? {
        calls.append(.finish(date, timeZone))
        return end(at: date)
    }

    func salvage(at date: Date, timeZone: String) async -> WorkoutSummary? {
        calls.append(.salvage(date))
        let summary = end(at: date)
        local = local.endedUnexpectedly()
        return summary
    }

    func discard() async {
        calls.append(.discard)
        local = local.ended()
    }

    func recover() async -> Bool {
        calls.append(.recover)
        if let recoverDelay { try? await Task.sleep(for: recoverDelay) }
        guard let recoverable else {
            local = local.lost()
            return false
        }
        local = recoverable
        return true
    }

    private func end(at date: Date) -> WorkoutSummary? {
        let start = local.startedAt ?? date
        let active = max(0, date.timeIntervalSince(start) - pausedTime)
        let shiftId = local.shiftId
        local = local.ended()
        guard active >= WorkoutPlan.minimumDuration else { return nil }
        return WorkoutSummary(shiftId: shiftId, start: start, end: date, activeDuration: active, activeKcal: kcal,
                              avgHeartRate: heartRate?.avg, maxHeartRate: heartRate?.max)
    }
}

/// A `ShiftNotifier` that records what it was asked.
@MainActor
final class FakeShiftNotifier: ShiftNotifier {
    private(set) var authorizationRequests = 0
    private(set) var stuckClockOuts = 0
    /// When the system would post the stuck clock-out reminder; nil when none is waiting.
    private(set) var reminder: Date?

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func notifyStuckClockOut() async {
        stuckClockOuts += 1
    }

    func scheduleStuckClockOut(at date: Date) async {
        reminder = date
    }

    func cancelStuckClockOut() {
        reminder = nil
    }
}

/// A sleep the test wakes by hand, for the stopped session's 60-minute deadline.
final class ManualSleeper: Sendable {
    private let sleepers = ManualSleeperState()

    var sleep: @Sendable (Duration) async throws -> Void {
        { [sleepers] _ in try await sleepers.wait() }
    }

    var waiting: Int { get async { await sleepers.count } }

    func wakeAll() async { await sleepers.wakeAll() }
}

private actor ManualSleeperState {
    private var continuations: [CheckedContinuation<Void, any Error>] = []
    var count: Int { continuations.count }

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuations.append($0) }
    }

    func wakeAll() {
        let all = continuations
        continuations = []
        all.forEach { $0.resume() }
    }
}

/// A clock the test moves.
@MainActor
final class TestClock {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
