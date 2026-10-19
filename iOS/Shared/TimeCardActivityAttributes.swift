import ActivityKit
import Foundation
import TimeCardCore

/// What the lock-screen Live Activity knows. Compiled into the app (which starts and
/// updates the activity) and the widget extension (which draws it).
///
/// The changing part is TreeFarmKit's `LiveSnapshot`, built by the same tested code that
/// answers Siri: the phase, a timer that ticks on its own, the next three rows, trees this
/// shift, field progress and the last action for Undo.
///
/// The fixed part says whose activity it is, so a different person signing in on the same
/// phone gets a fresh one instead of inheriting the last person's.
struct TimeCardActivityAttributes: ActivityAttributes, Hashable {
    typealias ContentState = LiveSnapshot

    var farmName: String
    var userName: String
}
