import Foundation
import TreeFarmKit

// STUB: slice b replaces
//
// The seam over HKWorkoutSession and HKLiveWorkoutBuilder, so `ShiftWorkout` is tested with a
// fake driver (docs/watch.md 7.1). Slice 0 fixed the signatures; slice b writes
// `HealthKitWorkoutDriver` and `FakeWorkoutDriver` against them.

enum HealthAccess: Equatable, Sendable {
    case notDetermined, authorized, denied, unavailable
}

enum WorkoutDriverEvent: Sendable {
    case phase(WorkoutLocal.Phase)
    case metrics(heartRate: Double?, kcal: Double?)
    case endedUnexpectedly(String)
}

@MainActor
protocol WorkoutDriver: AnyObject {
    var local: WorkoutLocal { get }
    var events: AsyncStream<WorkoutDriverEvent> { get }
    func authorizationStatus() -> HealthAccess
    func requestAuthorization() async -> HealthAccess
    func start(at: Date, shiftId: UUID?, origin: WorkoutLocal.Origin) async throws
    func tag(shiftId: UUID)
    func pause()
    func resume()
    func stop(at: Date) async throws
    /// Nil when discarded (shorter than `WorkoutPlan.minimumDuration`).
    func finish(at: Date, timeZone: String) async throws -> WorkoutSummary?
    func discard() async
    func recover() async -> Bool
}
