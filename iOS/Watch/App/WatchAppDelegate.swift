import HealthKit
import WatchKit

/// The watch app's delegate (docs/watch.md 8.3). WatchKit calls it on the main actor.
///
/// - At launch: activate the model (and its transport) first, then let the workout recover a
///   session a crash left behind, which runs before any other workout input.
/// - `handleActiveWorkoutRecovery()`: the same recovery.
/// - `handle(_ workoutConfiguration:)`: the iPhone's `startWatchApp` after a phone clock-in.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchShiftModel.shared.activate()
        ShiftWorkout.shared.recoverIfNeeded()
    }

    func handleActiveWorkoutRecovery() {
        ShiftWorkout.shared.recoverIfNeeded()
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        ShiftWorkout.shared.handleLaunch()
    }
}
