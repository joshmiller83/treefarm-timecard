import HealthKit
import WatchKit

// STUB: slice a replaces
//
// The wiring slice 0 fixed (docs/watch.md 8.3):
// - `applicationDidFinishLaunching`: activate the transport, then `ShiftWorkout.shared.recoverIfNeeded()`.
// - `handleActiveWorkoutRecovery()`: `ShiftWorkout.shared.recoverIfNeeded()`.
// - `handle(_ workoutConfiguration:)`: `ShiftWorkout.shared.handleLaunch()`.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            WatchShiftModel.shared.activate()
            ShiftWorkout.shared.recoverIfNeeded()
        }
    }

    func handleActiveWorkoutRecovery() {
        Task { @MainActor in ShiftWorkout.shared.recoverIfNeeded() }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in ShiftWorkout.shared.handleLaunch() }
    }
}
