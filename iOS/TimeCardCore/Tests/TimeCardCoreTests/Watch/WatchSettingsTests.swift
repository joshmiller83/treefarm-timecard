import Foundation
import Testing
@testable import TimeCardCore

/// Settings › Apple Watch: "Record shifts as workouts" is on by default and saved per person
/// on this phone, so two people sharing a phone each keep their own choice (docs/watch.md 5.5).
@Suite("Watch settings")
struct WatchSettingsTests {
    let store: LocalStore
    let josh = UUID()
    let sam = UUID()

    init() throws {
        store = try LocalStore.inMemory()
    }

    @Test func recordingIsOnUntilSomeoneTurnsItOff() {
        #expect(WatchSettings.load(from: store, userId: josh).recordWorkouts)
        #expect(WatchSettings.load(from: store, userId: nil).recordWorkouts)
        #expect(WatchSettings() == WatchSettings(recordWorkouts: true))
    }

    @Test func aChoiceIsKeptForThatPersonOnly() {
        WatchSettings.save(WatchSettings(recordWorkouts: false), to: store, userId: josh)
        #expect(WatchSettings.load(from: store, userId: josh).recordWorkouts == false)
        #expect(WatchSettings.load(from: store, userId: sam).recordWorkouts)
    }

    @Test func turningItBackOnIsKept() {
        WatchSettings.save(WatchSettings(recordWorkouts: false), to: store, userId: josh)
        WatchSettings.save(WatchSettings(recordWorkouts: true), to: store, userId: josh)
        #expect(WatchSettings.load(from: store, userId: josh).recordWorkouts)
    }

    @Test func nobodySignedInSavesNothing() throws {
        WatchSettings.save(WatchSettings(recordWorkouts: false), to: store, userId: nil)
        #expect(WatchSettings.load(from: store, userId: nil).recordWorkouts)
        #expect(try store.value(forKey: WatchSettings.key(userId: josh)) == nil)
    }

    @Test func unreadableDataFallsBackToTheDefault() throws {
        try store.setValue(Data("not json".utf8), forKey: WatchSettings.key(userId: josh))
        #expect(WatchSettings.load(from: store, userId: josh).recordWorkouts)
    }

    @Test func theKeyNamesThePerson() {
        #expect(WatchSettings.key(userId: josh) == "watch.settings.\(josh.uuidString)")
    }
}
