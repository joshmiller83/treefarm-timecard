import Foundation
import Observation
import Testing
import TimeCardCore
import UIKit
@testable import TimeCard

/// Stands in for the session: whatever the test sets, the feed reads.
@MainActor
@Observable
final class FakeLiveSource {
    var reading = LiveActivityReading(loaded: false, snapshot: nil, attributes: nil)
    @ObservationIgnored var reads = 0

    func read() -> LiveActivityReading {
        reads += 1
        return reading
    }
}

/// The demo farm on a phone: a stub server, an in-memory store and a token. A second
/// `session()` on the same phone is the app launched again.
@MainActor
struct DemoPhone {
    let demo = DemoFarm.makeServer(signedIn: true)
    let store = try! LocalStore.inMemory()
    let tokens = InMemoryTokenStore(token: "ui-test-token")

    init() {
        if let me = try? JSONCoding.encoder().encode(demo.me) {
            try? store.setValue(me, forKey: AuthService.meKey)
        }
    }

    /// A model whose field actions tell no Live Activity directly, so only the feed does.
    func model() -> AppModel {
        let session = TimeCardSession(store: store, api: demo.server, tokens: tokens, deviceName: "Test iPhone")
        let model = AppModel(session: session, mode: .uiTest(signedIn: true))
        model.actions.onLiveSnapshot = nil
        return model
    }
}

@MainActor
@Suite("Live Activity feed")
struct LiveActivityFeedTests {
    typealias F = LiveFixtures

    let host = FakeActivityHost()
    let reminders = FakeReminders()
    let ledger = MemoryLedger()
    static let settle: Duration = .milliseconds(20)

    func controller() -> LiveActivityController {
        LiveActivityController(host: host, reminders: reminders, ledger: ledger, waitsForSession: true)
    }

    /// Waits (up to 5 s) for the feed to settle and the controller to pass something on.
    func eventually(_ condition: @MainActor () -> Bool, _ c: LiveActivityController) async {
        for _ in 0..<500 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
            await c.waitUntilIdle()
        }
    }

    /// Long enough for a settled feed to have spoken, if it was going to.
    func quietPeriod(_ c: LiveActivityController) async {
        try? await Task.sleep(for: .milliseconds(150))
        await c.waitUntilIdle()
    }

    var updates: Int { host.calls.filter { if case .update = $0 { true } else { false } }.count }

    // MARK: With a stand-in

    @Test func itFollowsChangesAndOneBurstMakesOneUpdate() async {
        let source = FakeLiveSource()
        let c = controller()
        c.follow(settle: Self.settle) { source.reading }
        await quietPeriod(c)
        #expect(host.calls.isEmpty, "nothing known yet")

        source.reading = LiveActivityReading(loaded: true, snapshot: F.working(), attributes: F.attributes)
        await eventually({ !host.calls.isEmpty }, c)
        #expect(host.calls.first.map { if case .start = $0 { true } else { false } } == true)

        // A sync applies many records at once.
        for row in 14...18 {
            source.reading.snapshot = F.working(rows: [F.chip(row), F.chip(row + 1), F.chip(row + 2)])
        }
        await eventually({ updates > 0 }, c)
        await quietPeriod(c)
        #expect(updates == 1)
        #expect(host.states["A1"]?.nextRows.first == F.chip(18))
    }

    @Test func notLoadedYetEndsNothingAndOnceLoadedOffTheClockEnds() async {
        host.records = [LiveActivityRecord(id: "A0", attributes: F.attributes, state: .active)]
        let source = FakeLiveSource()
        let c = controller()
        c.follow(settle: Self.settle) { source.reading }
        // Scene active while still loading: AppModel hands over a nil snapshot.
        c.update(nil, attributes: nil)
        await quietPeriod(c)
        #expect(host.calls.isEmpty)

        source.reading = LiveActivityReading(loaded: true, snapshot: nil, attributes: nil)
        await eventually({ !host.calls.isEmpty }, c)
        #expect(host.calls == [.end("A0")])
    }

    @Test func comingForwardReadsAgain() async {
        let source = FakeLiveSource()
        source.reading = LiveActivityReading(loaded: true, snapshot: F.working(), attributes: F.attributes)
        let c = controller()
        c.follow(settle: Self.settle) { source.read() }
        await eventually({ !host.calls.isEmpty }, c)
        let before = source.reads
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await eventually({ source.reads > before }, c)
        #expect(source.reads == before + 1)
    }

    // MARK: With the demo farm's session

    @Test func aColdLaunchWhileClockedInKeepsTheCardAndUpdatesItOnce() async throws {
        let phone = DemoPhone()
        // Yesterday's launch: clocked in, and the card went up an hour ago.
        let first = phone.model()
        await first.start()
        _ = await first.session.syncNow()
        #expect(first.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await first.session.stop()
        host.records = [LiveActivityRecord(id: "A0", attributes: try #require(first.activityAttributes), state: .active)]
        ledger.starts = ["A0": Date().addingTimeInterval(-3600)]

        // iOS killed the app; the person opens it.
        let relaunched = phone.model()
        let c = controller()
        c.follow(settle: Self.settle) { relaunched.liveActivityReading }
        // The scene comes forward before the store has opened, as `sceneBecameActive` does.
        c.update(relaunched.actions.liveSnapshot(), attributes: relaunched.activityAttributes)
        await quietPeriod(c)
        #expect(host.calls.isEmpty, "a session still opening isn't a clock-out")

        await relaunched.start()
        await eventually({ !host.calls.isEmpty }, c)
        await quietPeriod(c)
        #expect(!host.calls.contains(.end("A0")))
        #expect(updates == 1)
        #expect(host.calls.allSatisfy { if case .update("A0", _) = $0 { true } else { false } })
        #expect(host.states["A0"]?.phase == .working)
        await relaunched.session.stop()
    }

    /// Clocked in on the demo farm, with the feed following the session.
    func clockedIn(_ phone: DemoPhone) async throws -> (AppModel, LiveActivityController) {
        let model = phone.model()
        await model.start()
        _ = await model.session.syncNow()
        let c = controller()
        c.follow(settle: Self.settle) { model.liveActivityReading }
        #expect(model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        await eventually({ !host.calls.isEmpty }, c)
        await quietPeriod(c)
        #expect(host.records.count == 1)
        return (model, c)
    }

    @Test func aRowSomeoneElseShapedLeavesTheButtons() async throws {
        // Sam shapes the row the lock screen offers first, and the pull lands.
        let phone = DemoPhone()
        let (model, c) = try await clockedIn(phone)
        let id = try #require(host.records.first?.id)
        let offered = try #require(host.states[id]?.nextRows.first)

        let state = try #require(model.actions.state())
        let sam = try #require(state.members.first { $0.email == DemoFarm.workerEmail })
        let season = try #require(state.season)
        let samShift = Shift(userId: sam.userId, farmId: state.farm.id, start: Date().addingTimeInterval(-3600), rateCents: 0)
        let block = try #require(state.blocks.first { $0.id == offered.blockId })
        let marks = (0..<block.treesPerRow).map { position in
            SyncRecord.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: offered.blockId, row: offered.row, position: position),
                                         shiftId: samShift.id, userId: sam.userId, markedAt: Date().roundedToMillisecond))
        }
        await phone.demo.server.seed(farmId: state.farm.id, [.shift(samShift)] + marks)
        _ = await model.session.syncNow()

        await eventually({ host.states[id]?.nextRows.first != offered }, c)
        #expect(host.states[id]?.nextRows.contains(offered) == false)
        await model.session.stop()
    }

    @Test func anEditInTheAppMovesTheTimer() async throws {
        let phone = DemoPhone()
        let (model, c) = try await clockedIn(phone)
        let id = try #require(host.records.first?.id)
        let open = try #require(model.actions.state()?.openShift)
        var edited = open
        edited.start = Date().addingTimeInterval(-2 * 3600).roundedToMillisecond
        edited.updatedAt = Date().roundedToMillisecond
        try model.session.save([.shift(edited)])

        await eventually({ (host.states[id]?.workedSoFar ?? 0) > 3600 }, c)
        let worked = try #require(host.states[id]?.workedSoFar)
        #expect(abs(worked - 2 * 3600) < 60)
        await model.session.stop()
    }

    @Test func signingOutInTheAppEndsTheCard() async throws {
        let phone = DemoPhone()
        let (model, c) = try await clockedIn(phone)
        let id = try #require(host.records.first?.id)
        await model.session.signOut()
        await eventually({ host.calls.contains(.end(id)) }, c)
        #expect(host.records.isEmpty)
        #expect(reminders.calls.last == .cancel)
    }
}
