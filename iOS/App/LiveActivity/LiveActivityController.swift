import Foundation
import TimeCardCore

/// Starts, updates and ends the lock-screen Live Activity from `LiveSnapshot`s.
/// (Stub: the Live Activity slice fills this in.)
@MainActor
final class LiveActivityController {
    /// Called after every field action, and when the app comes forward.
    /// `nil` means off the clock: end the activity.
    func update(_ snapshot: LiveSnapshot?, attributes: TimeCardActivityAttributes?) {}
}
