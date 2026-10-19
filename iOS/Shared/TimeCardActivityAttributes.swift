import ActivityKit
import Foundation

/// What the lock-screen Live Activity knows. Compiled into the app (which starts and
/// updates the activity) and the widget extension (which draws it).
///
/// This is a placeholder shape; the Live Activity slice fills in rows, trees and undo.
struct TimeCardActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        enum Phase: String, Codable, Hashable, Sendable {
            case working
            case lunch
            case onBreak
        }

        var phase: Phase
        /// Worked time banked before `segmentStart`, so the timer can tick on its own.
        var workedBefore: TimeInterval
        /// When the current stretch (work or break) began.
        var segmentStart: Date

        init(phase: Phase, workedBefore: TimeInterval = 0, segmentStart: Date) {
            self.phase = phase
            self.workedBefore = workedBefore
            self.segmentStart = segmentStart
        }
    }

    var farmName: String
    var userName: String
}
