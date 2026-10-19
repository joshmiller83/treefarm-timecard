import Foundation

// STUB: slice d replaces
//
// The iPhone's Apple Watch settings, saved per person on this phone and read by `WatchDesk`
// on every call (docs/watch.md 5.5). Slice 0 fixed the shape `AppModel` uses; slice d
// writes the persistence, test-first (WatchSettingsTests).
public struct WatchSettings: Equatable, Sendable {
    /// "Record shifts as workouts", on by default. Travels as `WatchState.recordWorkouts`.
    public var recordWorkouts: Bool

    public init(recordWorkouts: Bool = true) {
        self.recordWorkouts = recordWorkouts
    }

    /// The person's settings on this phone (the defaults for nobody, or nothing saved yet).
    public static func load(from store: any KeyValueStore, userId: UUID?) -> WatchSettings {
        WatchSettings()
    }

    public static func save(_ settings: WatchSettings, to store: any KeyValueStore, userId: UUID?) {}
}
