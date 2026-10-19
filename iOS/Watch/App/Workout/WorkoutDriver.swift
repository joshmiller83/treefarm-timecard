import Foundation
import TreeFarmKit

// The seam over HKWorkoutSession and HKLiveWorkoutBuilder (docs/watch.md 7.1), so `ShiftWorkout`
// is tested with a fake. `HealthKitWorkoutDriver` is the real one; the tests' `FakeWorkoutDriver`
// records every call with its dates.

/// Whether the watch may record workouts in Health.
enum HealthAccess: Equatable, Sendable {
    /// Never asked: the first-launch card asks.
    case notDetermined
    case authorized
    /// Shifts work normally with no workout; the Today page says how to allow it.
    case denied
    /// No HealthKit on this device.
    case unavailable
}

enum WorkoutDriverEvent: Sendable {
    /// The session's state changed (HKWorkoutSessionDelegate).
    case phase(WorkoutLocal.Phase)
    /// Live numbers from the builder: the latest heart rate (bpm) and the active kcal so far.
    case metrics(heartRate: Double?, kcal: Double?)
    /// The session ended from outside the app: another workout started, an error, the system.
    case endedUnexpectedly(String)
}

/// One workout session at a time. Every method updates `local` and saves it, so a recovered
/// session picks up where it was. The driver never decides anything: `ShiftWorkout` does what
/// `WorkoutPlan` says.
@MainActor
protocol WorkoutDriver: AnyObject {
    var local: WorkoutLocal { get }
    var events: AsyncStream<WorkoutDriverEvent> { get }
    func authorizationStatus() -> HealthAccess
    func requestAuthorization() async -> HealthAccess
    /// `startActivity(with:)` and `beginCollection(at:)` at `date`, with a new sync identifier.
    func start(at: Date, shiftId: UUID?, origin: WorkoutLocal.Origin) async throws
    func tag(shiftId: UUID)
    func pause()
    func resume()
    /// `stopActivity(with:)`, waiting for `.stopped`. The session stays (stopped) until it finishes.
    func stop(at: Date) async throws
    /// Apple's order: stop, end collection, then save with metadata (or discard when shorter
    /// than `WorkoutPlan.minimumDuration`), then end the session. Nil when discarded.
    func finish(at: Date, timeZone: String) async throws -> WorkoutSummary?
    /// After an unexpected end: saves what was collected if the builder still can, and
    /// remembers the end (`WorkoutLocal.stoppedUnexpectedly`). The shift stays on the clock.
    func salvage(at: Date, timeZone: String) async -> WorkoutSummary?
    func discard() async
    /// Reattaches a session that outlived the app (a crash), with a new data source and both
    /// delegates. False when there was none to recover.
    func recover() async -> Bool
}

/// The workout's files in the App Group container: the session's record (for recovery) and the
/// last summary, with the one slot it waits in while the phone is out of reach.
struct WorkoutStore: Sendable {
    struct Summaries: Codable, Equatable, Sendable {
        /// The newest shift summary, shown for an hour after its end.
        var last: WorkoutSummary?
        /// The summary screen was closed with Done.
        var dismissed = false
        /// Not yet delivered to the phone; goes with the next flush.
        var pending: WorkoutSummary?
    }

    static let localFile = "workout-local.json"
    static let summaryFile = "workout-summary.json"

    let directory: URL

    init(directory: URL = WatchStateFile.directory) {
        self.directory = directory
    }

    func local() -> WorkoutLocal { read(Self.localFile) ?? WorkoutLocal() }
    func save(_ local: WorkoutLocal) { write(local, Self.localFile) }

    func summaries() -> Summaries { read(Self.summaryFile) ?? Summaries() }
    func save(_ summaries: Summaries) { write(summaries, Self.summaryFile) }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
        return try? JSONCoding.decoder().decode(T.self, from: data)
    }

    private func write(_ value: some Encodable, _ name: String) {
        guard let data = try? JSONCoding.encoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: name), options: [.atomic])
    }
}
