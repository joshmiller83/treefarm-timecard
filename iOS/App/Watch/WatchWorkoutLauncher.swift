import Foundation

// STUB: slice b replaces
//
// Starts the watch's shift workout after a phone clock-in (`HKHealthStore.startWatchApp`), with
// a timeout because its completion can hang when the watch is off (docs/watch.md 1.3 step 7).
// Slice 0 fixed the protocol and the two types `AppModel` builds; slice b writes them, test-first.

enum WatchLaunchResult: Equatable, Sendable {
    case started
    case timedOut
    case failed(String)
    /// No paired watch, HealthKit unavailable, or a test host.
    case unavailable
}

protocol WatchWorkoutLauncher: Sendable {
    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult
}

/// The real one: `HKHealthStore.startWatchApp(toHandle:)` with an outdoor `.other` configuration.
struct HealthKitWatchLauncher: WatchWorkoutLauncher {
    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult {
        .unavailable
    }
}

/// For UI-test mode and test hosts: there is never a watch to start.
struct UnavailableWatchLauncher: WatchWorkoutLauncher {
    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult {
        .unavailable
    }
}
