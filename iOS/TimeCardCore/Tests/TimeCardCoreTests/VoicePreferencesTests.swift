import Foundation
import Testing
@testable import TimeCardCore

@Suite("Voice preferences")
struct VoicePreferencesTests {
    @Test func defaultsAreQuietAndPrivate() throws {
        let store = try LocalStore.inMemory()
        let prefs = VoicePreferences.load(from: store)
        #expect(prefs == VoicePreferences())
        #expect(!prefs.askBreakReason)
        #expect(!prefs.sayPayWhenLocked)
    }

    @Test func choicesAreKept() throws {
        let store = try LocalStore.inMemory()
        try VoicePreferences(askBreakReason: true, sayPayWhenLocked: true).save(to: store)
        #expect(VoicePreferences.load(from: store) == VoicePreferences(askBreakReason: true, sayPayWhenLocked: true))
    }

    @Test func aWipeKeepsThem() throws {
        let store = try LocalStore.inMemory()
        try VoicePreferences(askBreakReason: true).save(to: store)
        try store.wipe(keeping: [VoicePreferences.key])
        #expect(VoicePreferences.load(from: store).askBreakReason)
    }
}
