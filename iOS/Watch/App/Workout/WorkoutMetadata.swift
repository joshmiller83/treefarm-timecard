import Foundation
import HealthKit
import TreeFarmKit

/// What a shift workout looks like in Health (docs/watch.md 2.1 and 2.3).
///
/// Health data never leaves the person's devices: heart rate and calories aren't in any sync
/// record and never reach the farm's server, so an employer never sees a worker's health.
enum WorkoutMetadata {
    static let brandName = "Time Card shift"
    /// The shift's id, so a workout can be matched to its shift on this person's devices.
    static let shiftIdKey = "TimeCardShiftID"

    /// There's no gardening or occupational type, and Other is Apple's catch-all. Outdoor, with
    /// no CoreLocation and no route.
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
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyTimeZone: timeZone,
            HKMetadataKeyIndoorWorkout: false,
        ]
        if let shiftId = local.shiftId { metadata[shiftIdKey] = shiftId.uuidString }
        metadata[HKMetadataKeySyncIdentifier] = (local.syncIdentifier ?? UUID()).uuidString
        return metadata
    }
}
