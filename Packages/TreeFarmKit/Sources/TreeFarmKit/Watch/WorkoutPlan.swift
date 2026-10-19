import Foundation

// STUB: slice b replaces
//
// What the watch's workout session should do, decided purely from the phone's confirmed
// state, the waiting and in-flight requests and the session's own record. `ShiftWorkout`
// never decides on its own: it does exactly the steps returned here. The rules are in
// docs/watch.md 2.2 ("WorkoutPlan.reconcile rules, checked in order"). Slice b writes them,
// test-first, in this file (with WorkoutPlanTests).
public enum WorkoutPlan {
    /// A workout never starts more than this before now (a phone clock-in seen late starts now).
    public static let backdateLimit: TimeInterval = 5 * 60
    /// A finished workout shorter than this is discarded, not saved.
    public static let minimumDuration: TimeInterval = 2 * 60
    /// How long a stopped session waits for its clock-out to be answered.
    public static let stoppedLimit: TimeInterval = 60 * 60

    public static func reconcile(inputs: WorkoutInputs, local: WorkoutLocal, now: Date) -> [WorkoutStep] {
        []
    }
}
