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
    /// Everything in order, with the background-task hold: "hold", "start A1", "release".
    var timeline: [String] = []
    private var nextId = 1

    func activities() -> [LiveActivityRecord] { records }

    func start(_ attributes: TimeCardActivityAttributes, _ state: LiveSnapshot, staleDate: Date?) throws -> String {
        if failStarts { throw CocoaError(.featureUnsupported) }
        let id = "A\(nextId)"
        nextId += 1
        records.append(LiveActivityRecord(id: id, attributes: attributes, state: .active))
        states[id] = state
        calls.append(.start(id, staleDate: staleDate))
        timeline.append("start \(id)")
        return id
    }

    func update(id: String, _ state: LiveSnapshot, staleDate: Date?) async {
        await Task.yield() // ActivityKit takes a moment
        states[id] = state
        calls.append(.update(id, staleDate: staleDate))
        timeline.append("update \(id)")
    }

    func end(id: String, _ state: LiveSnapshot?) async {
        records.removeAll { $0.id == id }
        calls.append(.end(id))
        timeline.append("end \(id)")
    }

    func holdAwake() -> @MainActor () -> Void {
        timeline.append("hold")
        return { [weak self] in self?.timeline.append("release") }
    }

    /// The person swipes the activity away: it's gone.
    func dismissAll() {
        records = records.map { LiveActivityRecord(id: $0.id, attributes: $0.attributes, state: .dismissed) }
    }

    /// iOS ends it after eight hours: it stays on the lock screen, frozen, until taken down.
    func endAll() {
        records = records.map { LiveActivityRecord(id: $0.id, attributes: $0.attributes, state: .ended) }
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

    func controller(waitsForSession: Bool = false) -> LiveActivityController {
        let clock = self.clock
        return LiveActivityController(host: host, reminders: reminders, ledger: ledger, now: { clock.now }, waitsForSession: waitsForSession)
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
        #expect(!host.calls.contains(.end("A1")), "a swiped-away card is already gone")
    }

    @Test func aCardIOSEndedAtEightHoursIsTakenDownBeforeTheNewOne() async {
        // iOS leaves an ended activity on the lock screen, frozen, for hours: without this
        // there'd be two Time Card cards, one with old rows and buttons.
        let c = controller()
        await send(c, F.working())
        clock.advance(8 * 3600 + 5 * 60)
        host.endAll()
        await send(c, F.working(lastAction: "Row 20 marked", canUndo: true))
        let newExpiry = clock.now.addingTimeInterval(7 * 3600 + 50 * 60)
        #expect(Array(host.calls.suffix(2)) == [.end("A1"), .start("A2", staleDate: newExpiry)])
        #expect(reminders.calls.last == .schedule(newExpiry, askPermission: true))
        #expect(host.records.map(\.id) == ["A2"])
    }

    @Test func theEightHourPlanIsEndThenStartThenRemind() {
        let ended = LiveActivityRecord(id: "old", attributes: F.attributes, state: .ended)
        let steps = LiveActivityPlan.steps(clockedIn: true, attributes: F.attributes, enabled: true, running: [ended],
                                           startedAt: ["old": F.now.addingTimeInterval(-8 * 3600)], appIsActive: true, now: F.now)
        #expect(steps == [.end(id: "old"), .start(staleDate: expires), .scheduleReminder(at: expires)])
        // From the lock screen too: the frozen card can't be updated, only taken down.
        let background = LiveActivityPlan.steps(clockedIn: true, attributes: F.attributes, enabled: true, running: [ended],
                                                startedAt: [:], appIsActive: false, now: F.now)
        #expect(background == [.end(id: "old"), .start(staleDate: expires), .scheduleReminder(at: expires)])
    }

    @Test func offTheClockAnEndedCardComesDownToo() async {
        host.records = [LiveActivityRecord(id: "old", attributes: F.attributes, state: .ended),
                        LiveActivityRecord(id: "gone", attributes: F.attributes, state: .dismissed)]
        await send(controller(), nil)
        #expect(host.calls == [.end("old")])
        #expect(reminders.calls == [.cancel])
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
        await send(c, F.working(lastAction: "Row 14 marked", canUndo: true))
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
        host.records = [LiveActivityRecord(id: "old", attributes: F.attributes, state: .active)]
        let c = controller()
        await send(c, F.working())
        #expect(Array(host.calls.prefix(2)) == [.end("old"), .start("A1", staleDate: expires)])
    }

    @Test func anActivityOfUnknownAgeIsUpdatedInTheBackground() async {
        host.records = [LiveActivityRecord(id: "old", attributes: F.attributes, state: .active)]
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
        host.records = [LiveActivityRecord(id: "one", attributes: F.attributes, state: .active),
                        LiveActivityRecord(id: "two", attributes: F.attributes, state: .stale)]
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

    // MARK: A cold launch

    @Test func whileTheSessionOpensANilSnapshotEndsNothing() async {
        // The app comes forward while it's still opening its store: FieldActions has no farm
        // yet, so the snapshot is nil. That's "not known yet", not "clocked out".
        host.records = [LiveActivityRecord(id: "A0", attributes: F.attributes, state: .active)]
        ledger.starts = ["A0": F.now.addingTimeInterval(-3600)]
        let c = controller(waitsForSession: true)
        c.update(nil, attributes: nil)
        await c.waitUntilIdle()
        #expect(host.calls.isEmpty)
        #expect(reminders.calls.isEmpty)
        #expect(!c.isSessionLoaded)

        // The session opens, still clocked in: exactly one update, to the same card.
        c.update(F.working(), attributes: F.attributes, sessionLoaded: true)
        await c.waitUntilIdle()
        #expect(host.calls == [.update("A0", staleDate: F.now.addingTimeInterval(-3600 + 7 * 3600 + 50 * 60))])
        #expect(c.isSessionLoaded)
    }

    @Test func aSnapshotShowsTheSessionHasOpened() async {
        // A field action before the feed has caught up (Siri woke the app) goes straight through.
        let c = controller(waitsForSession: true)
        await send(c, F.working())
        #expect(host.calls == [.start("A1", staleDate: expires)])
    }

    @Test func onceTheSessionHasOpenedNilMeansOffTheClock() async {
        host.records = [LiveActivityRecord(id: "A0", attributes: F.attributes, state: .active)]
        let c = controller(waitsForSession: true)
        c.update(nil, attributes: nil, sessionLoaded: true)
        await c.waitUntilIdle()
        #expect(host.calls == [.end("A0")])
        #expect(reminders.calls == [.cancel])
    }

    @Test func aHeldRequestGivesWayToTheNextOne() async {
        let c = controller(waitsForSession: true)
        c.update(nil, attributes: nil)
        c.update(F.working(lastAction: "Row 14 marked", canUndo: true), attributes: F.attributes)
        await c.waitUntilIdle()
        #expect(host.calls == [.start("A1", staleDate: expires)])
        #expect(host.states["A1"]?.lastAction == "Row 14 marked")
    }

    // MARK: Staying awake

    @Test func theAppStaysAwakeUntilTheUpdateHasLanded() async {
        // A lock-screen tap's intent may be suspended as soon as it returns.
        let c = controller()
        await send(c, F.working())
        await send(c, F.working(lastAction: "Row 14 marked", canUndo: true))
        #expect(host.timeline == ["hold", "start A1", "release", "hold", "update A1", "release"])
    }

    @Test func waitingUntilIdleWaitsForTheUpdate() async {
        let c = controller()
        await send(c, F.working())
        c.update(F.working(lastAction: "Row 14 marked", canUndo: true), attributes: F.attributes)
        #expect(host.states["A1"]?.lastAction == nil, "not there yet")
        await c.waitUntilIdle()
        #expect(host.states["A1"]?.lastAction == "Row 14 marked")
    }

    @Test func aCardThatWouldLookTheSameIsNotSentAgain() async {
        // The feed reads again after every sync; most of those change nothing on screen.
        let c = controller()
        await send(c, F.working())
        clock.advance(60)
        await send(c, F.working(now: F.now.addingTimeInterval(0.4)))
        await send(c, F.working())
        #expect(host.calls == [.start("A1", staleDate: expires)])
        await send(c, F.working(trees: 213))
        #expect(host.calls.last == .update("A1", staleDate: expires))
        await send(c, F.working(trees: 213))
        #expect(host.calls.count == 2)
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
