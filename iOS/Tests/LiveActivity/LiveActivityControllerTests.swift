import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// ActivityKit, played by a fake that remembers what it was asked to do.
@MainActor
final class FakeActivityHost: LiveActivityHosting {
    enum Call: Equatable {
        case start(String, staleDate: Date?)
        case update(String, staleDate: Date?)
        case end(String)
    }

    var areActivitiesEnabled = true
    var isAppActive = true
    var records: [LiveActivityRecord] = []
    var calls: [Call] = []
    var states: [String: LiveSnapshot] = [:]
    var failStarts = false
    private var nextId = 1

    func activities() -> [LiveActivityRecord] { records }

    func start(_ attributes: TimeCardActivityAttributes, _ state: LiveSnapshot, staleDate: Date?) throws -> String {
        if failStarts { throw CocoaError(.featureUnsupported) }
        let id = "A\(nextId)"
        nextId += 1
        records.append(LiveActivityRecord(id: id, attributes: attributes, isLive: true))
        states[id] = state
        calls.append(.start(id, staleDate: staleDate))
        return id
    }

    func update(id: String, _ state: LiveSnapshot, staleDate: Date?) async {
        states[id] = state
        calls.append(.update(id, staleDate: staleDate))
    }

    func end(id: String, _ state: LiveSnapshot?) async {
        records.removeAll { $0.id == id }
        calls.append(.end(id))
    }

    /// The person swipes the activity away, or iOS ends it after eight hours.
    func dismissAll() {
        records = records.map { LiveActivityRecord(id: $0.id, attributes: $0.attributes, isLive: false) }
    }
}

@MainActor
final class FakeReminders: LiveActivityReminding {
    enum Call: Equatable {
        case schedule(Date, askPermission: Bool)
        case cancel
    }

    var calls: [Call] = []

    func schedule(at date: Date, askPermission: Bool) async {
        calls.append(.schedule(date, askPermission: askPermission))
    }

    func cancel() async {
        calls.append(.cancel)
    }
}

final class MemoryLedger: LiveActivityLedger, @unchecked Sendable {
    var starts: [String: Date] = [:]
}

@MainActor
@Suite("Live Activity controller")
struct LiveActivityControllerTests {
    typealias F = LiveFixtures

    let host = FakeActivityHost()
    let reminders = FakeReminders()
    let ledger = MemoryLedger()
    let clock = TestClock(F.now)

    func controller() -> LiveActivityController {
        let clock = self.clock
        return LiveActivityController(host: host, reminders: reminders, ledger: ledger, now: { clock.now })
    }

    func send(_ c: LiveActivityController, _ snapshot: LiveSnapshot?, attributes: TimeCardActivityAttributes? = F.attributes) async {
        c.update(snapshot, attributes: attributes)
        await c.waitUntilIdle()
    }

    let expires = F.now.addingTimeInterval(7 * 3600 + 50 * 60)

    @Test func clockingInStartsTheActivityAndTheEightHourReminder() async {
        let c = controller()
        await send(c, F.working())
        #expect(host.calls == [.start("A1", staleDate: expires)])
        #expect(host.states["A1"] == F.working())
        #expect(reminders.calls == [.schedule(expires, askPermission: true)])
        #expect(ledger.starts == ["A1": F.now])
    }

    @Test func laterActionsUpdateTheSameActivity() async {
        let c = controller()
        await send(c, F.working())
        clock.advance(20 * 60)
        await send(c, F.working(lastAction: "Row 14 marked", canUndo: true))
        #expect(host.calls == [.start("A1", staleDate: expires), .update("A1", staleDate: expires)])
        #expect(host.states["A1"]?.lastAction == "Row 14 marked")
        #expect(reminders.calls.count == 1, "the reminder stays where it was")
    }

    @Test func clockingOutEndsItAndCancelsTheReminder() async {
        let c = controller()
        await send(c, F.working())
        await send(c, nil)
        #expect(host.calls.last == .end("A1"))
        #expect(host.records.isEmpty)
        #expect(reminders.calls.last == .cancel)
        #expect(ledger.starts.isEmpty)
    }

    @Test func signingOutEndsItToo() async {
        let c = controller()
        await send(c, F.working())
        await send(c, F.working(), attributes: nil)
        #expect(host.calls.last == .end("A1"))
        #expect(reminders.calls.last == .cancel)
    }

    @Test func turnedOffInSettingsStartsNothing() async {
        host.areActivitiesEnabled = false
        let c = controller()
        await send(c, F.working())
        #expect(host.calls.isEmpty)
        #expect(reminders.calls == [.cancel])
    }

    @Test func aDismissedActivityComesBackOnTheNextAction() async {
        let c = controller()
        await send(c, F.working())
        host.dismissAll()
        clock.advance(60)
        host.isAppActive = false // say, a Siri command with the phone in a pocket
        await send(c, F.working(lastAction: "Row 14 marked", canUndo: true))
        let newExpiry = clock.now.addingTimeInterval(7 * 3600 + 50 * 60)
        #expect(host.calls.last == .start("A2", staleDate: newExpiry))
        #expect(reminders.calls.last == .schedule(newExpiry, askPermission: false), "no permission prompt from the background")
        #expect(ledger.starts["A1"] == nil, "forgotten once it's gone")
    }

    @Test func anOldActivityIsRestartedWhenTheAppComesForward() async {
        let c = controller()
        await send(c, F.working())
        clock.advance(7 * 3600 + 51 * 60) // the reminder said "open Time Card"
        await send(c, F.working())
        let newExpiry = clock.now.addingTimeInterval(7 * 3600 + 50 * 60)
        #expect(Array(host.calls.suffix(2)) == [.end("A1"), .start("A2", staleDate: newExpiry)])
        #expect(reminders.calls.last == .schedule(newExpiry, askPermission: true))
        #expect(ledger.starts == ["A2": clock.now])
    }

    @Test func itIsRefreshedEarlyWheneverTheAppIsOpenAfterFourHours() async {
        let c = controller()
        await send(c, F.working())
        clock.advance(3 * 3600 + 59 * 60)
        await send(c, F.working())
        #expect(host.calls.last == .update("A1", staleDate: expires))
        clock.advance(60)
        await send(c, F.working())
        #expect(host.calls.last == .start("A2", staleDate: clock.now.addingTimeInterval(7 * 3600 + 50 * 60)))
    }

    @Test func anOldActivityIsOnlyUpdatedFromTheLockScreen() async {
        // Ending and restarting under a gloved thumb would make the buttons jump.
        let c = controller()
        await send(c, F.working())
        clock.advance(6 * 3600)
        host.isAppActive = false
        await send(c, F.working(lastAction: "Row 15 marked", canUndo: true))
        #expect(host.calls.last == .update("A1", staleDate: expires))
        #expect(host.records.count == 1)
    }

    @Test func aRelaunchedAppRemembersWhenItStarted() async {
        await send(controller(), F.working())
        clock.advance(3600)
        let relaunched = controller()
        await send(relaunched, F.working())
        #expect(host.calls.last == .update("A1", staleDate: expires))
    }

    @Test func anActivityOfUnknownAgeIsRestartedInTheForeground() async {
        host.records = [LiveActivityRecord(id: "old", attributes: F.attributes, isLive: true)]
        let c = controller()
        await send(c, F.working())
        #expect(Array(host.calls.prefix(2)) == [.end("old"), .start("A1", staleDate: expires)])
    }

    @Test func anActivityOfUnknownAgeIsUpdatedInTheBackground() async {
        host.records = [LiveActivityRecord(id: "old", attributes: F.attributes, isLive: true)]
        host.isAppActive = false
        let c = controller()
        await send(c, F.working())
        #expect(host.calls == [.update("old", staleDate: nil)])
    }

    @Test func someoneElsesActivityIsReplaced() async {
        let c = controller()
        await send(c, F.working())
        let sam = TimeCardActivityAttributes(farmName: "Pine Hollow Tree Farm", userName: "Sam Ortiz")
        await send(c, F.working(), attributes: sam)
        #expect(Array(host.calls.suffix(2)) == [.end("A1"), .start("A2", staleDate: expires)])
        #expect(host.records.map(\.attributes) == [sam])
    }

    @Test func extraCopiesAreEnded() async {
        ledger.starts = ["one": F.now.addingTimeInterval(-600), "two": F.now.addingTimeInterval(-60)]
        host.records = [LiveActivityRecord(id: "one", attributes: F.attributes, isLive: true),
                        LiveActivityRecord(id: "two", attributes: F.attributes, isLive: true)]
        let c = controller()
        await send(c, F.working())
        #expect(host.calls.contains(.end("one")))
        #expect(host.calls.contains(.update("two", staleDate: F.now.addingTimeInterval(-60 + 7 * 3600 + 50 * 60))))
        #expect(host.records.map(\.id) == ["two"])
    }

    @Test func aRefusedStartSchedulesNoReminderAndIsTriedAgain() async {
        host.failStarts = true
        let c = controller()
        await send(c, F.working())
        #expect(host.calls.isEmpty)
        #expect(reminders.calls.isEmpty)
        host.failStarts = false
        await send(c, F.working())
        #expect(host.calls == [.start("A1", staleDate: expires)])
    }

    @Test func quickUpdatesLandInOrderAndEndOnTheLatest() async {
        let c = controller()
        c.update(F.working(lastAction: "Row 13 marked", canUndo: true), attributes: F.attributes)
        c.update(F.working(lastAction: "Row 14 marked", canUndo: true), attributes: F.attributes)
        c.update(F.onBreak(.lunch), attributes: F.attributes)
        await c.waitUntilIdle()
        #expect(host.records.count == 1)
        #expect(host.states[host.records[0].id] == F.onBreak(.lunch))
    }

    @Test func offTheClockWithNothingRunningIsQuiet() async {
        let c = controller()
        await send(c, nil)
        #expect(host.calls.isEmpty)
        #expect(reminders.calls == [.cancel])
    }
}

/// A clock the tests move by hand.
final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
