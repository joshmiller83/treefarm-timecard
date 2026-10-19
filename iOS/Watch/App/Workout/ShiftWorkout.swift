import Foundation
import Observation
import TreeFarmKit

// STUB: slice b replaces
//
// The shift's workout session (docs/watch.md 2). It never decides on its own: on each input it
// asks `WorkoutPlan.reconcile` and does exactly that, from one serial input queue
// (`AsyncStream<WorkoutInput>`, one main-actor loop, `.recover` first, `.inputs` coalesced to
// the newest). The four entry points below only yield to that queue. Slice 0 fixed the
// signatures; slice b writes it, test-first, keeping them.

/// What the Today page and the summary show about the workout.
struct WorkoutLive: Equatable, Sendable {
    enum Recording: Equatable, Sendable {
        /// "Record shifts as workouts" is off on the phone.
        case off
        /// Health access was denied or never asked.
        case notAuthorized
        /// No session (off the clock).
        case idle
        case recording
        case paused
        /// Stopped at a watch clock-out, waiting for the phone ("Clock-out waiting for iPhone").
        case waitingForClockOut
        /// Ended from outside the app: "Recording stopped [Record again]".
        case stoppedUnexpectedly
    }

    var heartRate: Double?
    var kcal: Double?
    var recording: Recording = .idle
    var waitingClockOut = false
    var lastSummary: WorkoutSummary?
}

enum WorkoutInput: Sendable {
    case inputs(WorkoutInputs)
    case phoneLaunch
    case recover
    case recordAgain
}

@MainActor
@Observable
final class ShiftWorkout {
    static let shared = ShiftWorkout()

    private(set) var live = WorkoutLive()

    /// Yields `.inputs`; never awaits.
    func reconcile(_ inputs: WorkoutInputs) {}

    /// From `handle(_ workoutConfiguration:)` (a phone clock-in's `startWatchApp`): yields `.phoneLaunch`.
    func handleLaunch() {}

    /// Yields `.recover`, which runs before everything else.
    func recoverIfNeeded() {}

    /// The "Record again" button: yields `.recordAgain`.
    func recordAgain() {}
}
