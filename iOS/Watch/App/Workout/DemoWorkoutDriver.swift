import Foundation
import TreeFarmKit

/// The workout under `-watchDemo` (docs/watch.md 7.3): no HealthKit and no prompts, so UI tests
/// and screenshots run the whole shift, summary included, with steady made-up numbers.
@MainActor
final class DemoWorkoutDriver: WorkoutDriver {
    private(set) var local = WorkoutLocal()
    let events: AsyncStream<WorkoutDriverEvent>
    private let continuation: AsyncStream<WorkoutDriverEvent>.Continuation
    private var pausedSince: Date?
    private var pausedTotal: TimeInterval = 0

    /// Roughly what a steady day of shaping looks like.
    static let heartRate = (avg: 104.0, max: 151.0)
    static let kcalPerMinute = 2.4
    static let stepsPerMinute = 18.0
    static let metersPerMinute = 12.0

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func authorizationStatus() -> HealthAccess { .authorized }
    func requestAuthorization() async -> HealthAccess { .authorized }
    var asksForMore: Bool { false }
    func locationStatus() -> LocationAccess { .authorized }
    func requestLocation() async -> LocationAccess { .authorized }
    func recordRoute(_ on: Bool) {}
    func recordFieldLog(_ on: Bool) {}

    func start(at date: Date, shiftId: UUID?, origin: WorkoutLocal.Origin) async throws {
        pausedSince = nil
        pausedTotal = 0
        local = local.started(at: date, shiftId: shiftId, origin: origin, syncIdentifier: UUID())
        let minutes = activeMinutes(at: Date())
        continuation.yield(.metrics(heartRate: Self.heartRate.avg, kcal: minutes * Self.kcalPerMinute,
                                    steps: minutes * Self.stepsPerMinute, meters: minutes * Self.metersPerMinute))
    }

    func tag(shiftId: UUID) { local = local.tagged(shiftId) }

    func pause() {
        pausedSince = Date()
        local = local.with(phase: .paused)
    }

    func resume() {
        if let pausedSince { pausedTotal += Date().timeIntervalSince(pausedSince) }
        pausedSince = nil
        local = local.with(phase: .running)
    }

    func stop(at date: Date) async throws { local = local.stopped(at: date) }

    func finish(at date: Date, timeZone: String) async throws -> WorkoutSummary? {
        let start = local.startedAt ?? date
        let active = max(0, date.timeIntervalSince(start) - pausedTotal)
        let shiftId = local.shiftId
        local = local.ended()
        guard active >= WorkoutPlan.minimumDuration else { return nil }
        return WorkoutSummary(shiftId: shiftId, start: start, end: date, activeDuration: active,
                              activeKcal: active / 60 * Self.kcalPerMinute,
                              avgHeartRate: Self.heartRate.avg, maxHeartRate: Self.heartRate.max,
                              steps: active / 60 * Self.stepsPerMinute, distanceMeters: active / 60 * Self.metersPerMinute)
    }

    func salvage(at date: Date, timeZone: String) async -> WorkoutSummary? {
        let summary = try? await finish(at: date, timeZone: timeZone)
        local = local.endedUnexpectedly()
        return summary ?? nil
    }

    func discard() async { local = local.ended() }

    func recover() async -> Bool {
        local = local.lost()
        return false
    }

    private func activeMinutes(at date: Date) -> Double {
        guard let start = local.startedAt else { return 0 }
        return max(0, date.timeIntervalSince(start) - pausedTotal) / 60
    }
}
