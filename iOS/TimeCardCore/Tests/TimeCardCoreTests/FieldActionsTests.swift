import Foundation
import Testing
@testable import TimeCardCore

@MainActor
@Suite("Field actions")
struct FieldActionsTests {
    let f = Fixtures()
    let tokens = InMemoryTokenStore()
    let store: LocalStore
    let clock = TestClock(Fixtures.t0.addingTimeInterval(0.000_4))

    init() throws {
        store = try LocalStore.inMemory()
    }

    var me: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    func signedInSession() async throws -> TimeCardSession {
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, f.layout)
        await stub.addAccount(email: "josh@example.com", password: "pw", me: me)
        var config = SyncEngine.Configuration()
        config.debounce = .milliseconds(20)
        let session = TimeCardSession(store: store, api: stub, tokens: tokens, deviceName: "Test iPhone", engineConfiguration: config)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        #expect(session.snapshot.blocks[f.blockId] != nil)
        return session
    }

    func spoken(_ date: Date) -> String { Fmt.spokenTime(date, FarmCalendar(farm: f.farm)) }

    @Test func signedOutAsksToOpenTheApp() throws {
        let session = TimeCardSession(store: store, api: StubAPIClient(), tokens: tokens, deviceName: "Test iPhone")
        let actions = FieldActions(session: session, now: clock.read)
        let reply = actions.perform(.clockIn(fieldId: nil))
        #expect(!reply.succeeded)
        #expect(reply.speech == "Open Time Card to sign in.")
        #expect(actions.answer(.hours) == "Open Time Card to sign in.")
    }

    @Test func clockingInSavesAShiftThatWaitsToSync() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        let reply = actions.perform(.clockIn(fieldId: nil))
        #expect(reply.succeeded)
        #expect(reply.speech == "Clocked in at \(spoken(clock.now)). You’re on block 1, row 1.")
        let shift = try #require(session.snapshot.openShift(for: f.userId))
        #expect(shift.start == clock.now.roundedToMillisecond)
        #expect(shift.rateCents == 1800)
        #expect(try store.pendingCount(farmId: f.farmId) >= 1)
    }

    @Test func positionAndUndoSurviveARelaunch() async throws {
        let session = try await signedInSession()
        let first = FieldActions(session: session, now: clock.read)
        first.perform(.clockIn(fieldId: nil))
        clock.advance(minutes: 10)
        #expect(first.perform(.markNextRow).speech == "Row 1 marked, 10 trees. Next is row 2.")

        // Siri may run the next command in a fresh process.
        let second = FieldActions(session: session, now: clock.read)
        clock.advance(minutes: 10)
        #expect(second.perform(.markNextRow).speech == "Row 2 marked, 10 trees. Next is row 3.")
        #expect(second.canUndo)

        let third = FieldActions(session: session, now: clock.read)
        clock.advance(minutes: 1)
        #expect(third.perform(.undo).speech == "Undid row 2.")
        #expect(session.snapshot.marks.values.filter { $0.row == 1 }.isEmpty)
        #expect(third.perform(.undo).speech == "Undid row 1.")
        #expect(third.perform(.undo).speech == "There’s nothing to undo.")
    }

    @Test func undoBelongsToOnePerson() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        actions.perform(.clockIn(fieldId: nil))
        actions.perform(.markNextRow)
        #expect(try store.value(forKey: FieldActions.key("undo", farm: f.farmId, user: f.userId)) != nil)
        #expect(try store.value(forKey: FieldActions.key("undo", farm: f.farmId, user: f.otherUserId)) == nil)
    }

    @Test func theLockScreenHearsAboutEveryChange() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        var seen: [LiveSnapshot?] = []
        actions.onLiveSnapshot = { seen.append($0) }

        actions.perform(.clockIn(fieldId: nil))
        clock.advance(minutes: 15)
        actions.perform(.markNextRow)
        let live = try #require(seen.last ?? nil)
        #expect(live.phase == .working)
        #expect(live.shiftTrees == 10)
        #expect(live.nextRows.map(\.title) == ["Row 2", "Row 3", "Row 4"])
        #expect(live.lastAction == "Row 1 marked")
        #expect(live.canUndo)

        actions.perform(.startBreak(.lunch, reason: ""))
        #expect((seen.last ?? nil)?.phase == .lunch)
        actions.perform(.clockOut)
        #expect(seen.last == .some(nil))
    }

    @Test func failuresChangeNothing() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        let before = try store.pendingCount(farmId: f.farmId)
        let reply = actions.perform(.markNextRow)
        #expect(!reply.succeeded)
        #expect(reply.speech == "You’re not clocked in. Say \"clock in with Time Card\" first.")
        #expect(try store.pendingCount(farmId: f.farmId) == before)
    }

    @Test func questionsAndConfirmations() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        actions.perform(.clockIn(fieldId: nil))
        clock.advance(minutes: 90)
        #expect(actions.answer(.hours).hasPrefix("1 hour 30 minutes today"))
        #expect(actions.confirmation(for: .clockOut) == "You’ve worked 1 hour 30 minutes today. Clock out?")
        #expect(actions.confirmation(for: .markNextRow) == nil)
    }

    @Test func theStateUsesOnlyMyShifts() async throws {
        let session = try await signedInSession()
        let theirs = Shift(userId: f.otherUserId, farmId: f.farmId, start: Fixtures.t0, rateCents: 0, updatedAt: Fixtures.t0)
        try session.save([.shift(theirs)])
        let actions = FieldActions(session: session, now: clock.read)
        let state = try #require(actions.state())
        #expect(state.myShifts.isEmpty)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
    }
}

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    private(set) var now: Date
    init(_ start: Date) { now = start }
    func advance(minutes: Double) { now = now.addingTimeInterval(minutes * 60) }
    var read: () -> Date { { [unowned self] in self.now } }
}
