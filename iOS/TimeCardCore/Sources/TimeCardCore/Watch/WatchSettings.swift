import Foundation

/// The iPhone's Apple Watch settings, saved per person on this phone (two people can share a
/// phone) and read by `WatchDesk` on every call, so a change shows in the very next state the
/// watch gets (docs/watch.md 5.5).
public struct WatchSettings: Codable, Equatable, Sendable {
    /// "Record shifts as workouts", on by default. Travels as `WatchState.recordWorkouts`.
    public var recordWorkouts: Bool

    public init(recordWorkouts: Bool = true) {
        self.recordWorkouts = recordWorkouts
    }

    /// Where one person's settings live in the phone's store.
    public static func key(userId: UUID) -> String {
        "watch.settings.\(userId.uuidString)"
    }

    /// The person's settings on this phone: the defaults for nobody, or with nothing (or
    /// nothing readable) saved yet.
    public static func load(from store: any KeyValueStore, userId: UUID?) -> WatchSettings {
        guard let userId, let data = try? store.value(forKey: key(userId: userId)),
              let saved = try? JSONCoding.decoder().decode(WatchSettings.self, from: data) else { return WatchSettings() }
        return saved
    }

    /// Saves the person's settings. With nobody signed in there is no one to save them for.
    public static func save(_ settings: WatchSettings, to store: any KeyValueStore, userId: UUID?) {
        guard let userId, let data = try? JSONCoding.encoder().encode(settings) else { return }
        try? store.setValue(data, forKey: key(userId: userId))
    }
}
