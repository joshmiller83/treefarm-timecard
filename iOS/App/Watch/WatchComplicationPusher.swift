import Foundation
import TimeCardCore

/// What a publish does besides updating the application context (docs/watch.md 1.3 steps 6
/// and 7), decided from the phase the watch last heard about and the state being sent.
///
/// - **Complication push:** a phase change made on the phone while the watch app can't be
///   messaged goes as the current complication user info too, so the face catches up. Only
///   phase changes, never rows: iOS allows a handful a day (the transport says no once the
///   budget is spent, and the context still carries the change).
/// - **Starting the watch workout:** a phone clock-in (off the clock → on the clock that
///   didn't come through the desk) with "Record shifts as workouts" on and the watch app
///   installed launches the watch's workout, after the context went out.
enum WatchComplicationPusher {
    /// The phases the phone sends that are on the clock.
    static func isOnTheClock(_ phase: WatchPhase?) -> Bool {
        phase == .working || phase == .lunch || phase == .onBreak
    }

    /// Push the complication: the phase changed (from one the watch knew) while the watch app
    /// isn't reachable and the complication is on a face.
    static func shouldPush(before: WatchPhase?, after: WatchPhase, reachable: Bool, complicationEnabled: Bool) -> Bool {
        guard let before, before != after else { return false }
        return !reachable && complicationEnabled
    }

    /// Start the watch's workout: a clock-in made on the phone, from off the clock (or just
    /// signed in), with recording on and the watch app there to start.
    static func shouldLaunchWorkout(before: WatchPhase?, state: WatchState, openedByWatch: Bool, watchAppInstalled: Bool) -> Bool {
        guard watchAppInstalled, state.recordWorkouts, !openedByWatch else { return false }
        guard before == .offClock || before == .signedOut else { return false }
        return isOnTheClock(WatchDisplay.phase(state))
    }
}
