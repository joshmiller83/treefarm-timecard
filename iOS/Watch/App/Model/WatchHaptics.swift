import Foundation
import WatchKit

// Haptics mapped to meaning (docs/watch.md 3.11): one per reply, never one per second. Calls
// less than 100 ms apart cancel each other on the watch, so the second is skipped here, and a
// haptic pauses heart-rate sampling, which is one more reason to stay sparse.

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

/// Skips a haptic that would land within 100 ms of the last one.
struct HapticThrottle {
    static let gap: TimeInterval = 0.1
    private var last: Date?

    mutating func shouldPlay(at now: Date) -> Bool {
        if let last, now.timeIntervalSince(last) < Self.gap { return false }
        last = now
        return true
    }
}

@MainActor
enum WatchHaptics {
    private static var throttle = HapticThrottle()

    static func play(_ event: WatchHapticEvent) {
        guard throttle.shouldPlay(at: Date()) else { return }
        WKInterfaceDevice.current().play(type(for: event))
    }

    nonisolated static func type(for event: WatchHapticEvent) -> WKHapticType {
        switch event {
        case .started: .start
        case .stopped: .stop
        case .confirmed: .success
        case .refused: .failure
        case .queued: .retry
        case .breakStarted: .directionDown
        case .backToWork: .directionUp
        }
    }
}
