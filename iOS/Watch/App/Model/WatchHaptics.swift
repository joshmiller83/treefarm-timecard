import WatchKit

// STUB: slice a replaces
//
// Haptics mapped to meaning (docs/watch.md 3.11): one per reply, never one per second.

enum WatchHapticEvent: Sendable {
    /// Clock-in sent or workout started: `.start`.
    case started
    /// Clock-out, workout stopped: `.stop`.
    case stopped
    /// The phone confirmed a tap: `.success`.
    case confirmed
    /// The phone refused a tap: `.failure`.
    case refused
    /// Tap queued, phone out of reach: `.retry`.
    case queued
    /// Break started: `.directionDown`.
    case breakStarted
    /// Back to work: `.directionUp`.
    case backToWork
}

enum WatchHaptics {
    static func play(_ event: WatchHapticEvent) {}
}
