import Foundation

/// How Siri behaves on this phone, set in Settings. Both default to off: quick and private.
public struct VoicePreferences: Codable, Equatable, Sendable {
    /// Ask "What's the break for?" when a break starts by voice.
    public var askBreakReason: Bool
    /// Answer pay questions out loud while the phone is locked, where others may hear.
    public var sayPayWhenLocked: Bool

    public init(askBreakReason: Bool = false, sayPayWhenLocked: Bool = false) {
        self.askBreakReason = askBreakReason
        self.sayPayWhenLocked = sayPayWhenLocked
    }

    public static let key = "voice.preferences"

    public static func load(from store: LocalStore) -> VoicePreferences {
        guard let data = try? store.value(forKey: key) else { return VoicePreferences() }
        return (try? JSONDecoder().decode(VoicePreferences.self, from: data)) ?? VoicePreferences()
    }

    public func save(to store: LocalStore) throws {
        try store.setValue(try JSONEncoder().encode(self), forKey: Self.key)
    }
}
