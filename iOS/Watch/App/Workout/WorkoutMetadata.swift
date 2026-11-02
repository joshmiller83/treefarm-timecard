import Foundation
import HealthKit
import TreeFarmKit

/// What a shift workout looks like in Health (docs/watch.md 2.1 and 2.3, docs/health.md 1).
///
/// Health data never leaves the person's devices: heart rate, calories, steps, distance and any
/// route aren't in any sync record and never reach the farm's server, so an employer never
/// sees a worker's health or whereabouts.
enum WorkoutMetadata {
    /// Every shift records as Tree care for now.
    static let type = ShiftWorkoutType.treeCare
    /// "Tree care": Time Card's name for the workout. Health files it under Other.
    static var brandName: String { type.name }
    /// The shift's id, so a workout can be matched to its shift on this person's devices.
    static let shiftIdKey = "TimeCardShiftID"
    /// Which kind of work: "treeCare".
    static let typeKey = "TimeCardWorkoutType"

    /// Apple's workout types are a fixed list with no gardening, farming or occupational type,
    /// and Other is the catch-all: it counts calories from heart rate, which suits arm-heavy
    /// shaping. Outdoor; a GPS route only when the person turns on Record route.
    static func configuration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .outdoor
        return configuration
    }

    /// The metadata saved with the workout. The sync identifier is made when the session starts
    /// and saved with it, so a recovered session can't be saved twice.
    static func make(local: WorkoutLocal, timeZone: String) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: brandName,
            typeKey: type.key,
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyTimeZone: timeZone,
            HKMetadataKeyIndoorWorkout: false,
        ]
        if let shiftId = local.shiftId { metadata[shiftIdKey] = shiftId.uuidString }
        metadata[HKMetadataKeySyncIdentifier] = (local.syncIdentifier ?? UUID()).uuidString
        return metadata
    }
}
