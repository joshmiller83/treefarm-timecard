import Foundation
import HealthKit

/// The real `ShiftHealthReader` (docs/health.md 4): one statistics query per type over an OR of
/// the shift's worked spans. Statistics queries merge sources, so steps from the iPhone and the
/// watch count once; a sample that straddles a span's edge counts whole, which moves a total by
/// a few seconds' worth.
@MainActor
final class HealthKitShiftHealthReader: ShiftHealthReader {
    private let healthStore = HKHealthStore()

    private static let sums: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning, .flightsClimbed, .activeEnergyBurned]
    private static var readTypes: Set<HKObjectType> {
        Set((sums + [.heartRate]).map { HKQuantityType($0) })
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func needsPermission() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await healthStore.statusForAuthorizationRequest(toShare: [], read: Self.readTypes)
        return status == .shouldRequest
    }

    func requestPermission() async {
        guard isAvailable else { return }
        try? await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    func read(_ spans: [DateInterval]) async -> ShiftHealth {
        guard isAvailable, !spans.isEmpty else { return ShiftHealth() }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = await statistics(.heartRate, [.discreteAverage, .discreteMax], spans)
        return ShiftHealth(steps: await sum(.stepCount, .count(), spans),
                           distanceMeters: await sum(.distanceWalkingRunning, .meter(), spans),
                           flights: await sum(.flightsClimbed, .count(), spans),
                           activeKcal: await sum(.activeEnergyBurned, .kilocalorie(), spans),
                           avgHeartRate: heart?.averageQuantity()?.doubleValue(for: bpm),
                           maxHeartRate: heart?.maximumQuantity()?.doubleValue(for: bpm))
    }

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ spans: [DateInterval]) async -> Double? {
        await statistics(id, .cumulativeSum, spans)?.sumQuantity()?.doubleValue(for: unit)
    }

    /// One query over an OR of the spans.
    private func statistics(_ id: HKQuantityTypeIdentifier, _ options: HKStatisticsOptions,
                            _ spans: [DateInterval]) async -> HKStatistics? {
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: spans.map {
            HKQuery.predicateForSamples(withStart: $0.start, end: $0.end)
        })
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate,
                                          options: options) { _, statistics, _ in
                continuation.resume(returning: statistics)
            }
            healthStore.execute(query)
        }
    }
}
