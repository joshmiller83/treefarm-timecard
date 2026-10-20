import Foundation
import Testing
@testable import TimeCardCore

/// `perform(_:at:newShiftId:)`: a watch tap that waited out of reach runs at the time it was
/// made (the event time), under the shift id the watch minted, while every record it writes is
/// stamped with the time the phone got it, so "the newest updatedAt wins" isn't fooled.
@MainActor
@Suite("Field actions for the watch")
struct FieldActionsWatchTests {
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
        return session
    }

    func spoken(_ date: Date) -> String { Fmt.spokenTime(date, FarmCalendar(farm: f.farm)) }

    @Test func aQueuedClockInStartsAtItsTapUnderTheMintedId() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        let tapped = clock.now
        clock.advance(minutes: 20)
        let minted = UUID()
        let reply = actions.perform(.clockIn(fieldId: nil), at: tapped, newShiftId: minted)
        #expect(reply.succeeded)
        #expect(reply.speech == "Clocked in at \(spoken(tapped)). You’re on block 1, row 1.")
        let shift = try #require(session.snapshot.openShift(for: f.userId))
        #expect(shift.id == minted)
        #expect(shift.start == tapped.roundedToMillisecond)
        #expect(shift.updatedAt == clock.now.roundedToMillisecond)
    }

    @Test func marksKeepTheirTapTimeAndAreStampedWhenReceived() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        actions.perform(.clockIn(fieldId: nil))
        clock.advance(minutes: 10)
        let tapped = clock.now
        clock.advance(minutes: 30)
        let reply = actions.perform(.markRow(RowRef(blockId: f.blockId, row: 0)), at: tapped)
        #expect(reply.speech == "Row 1 marked, 10 trees. Next is row 2.")
        let marks = session.snapshot.marks.values.filter { $0.row == 0 }
        #expect(marks.count == 10)
        #expect(marks.allSatisfy { $0.markedAt == tapped.roundedToMillisecond })
        #expect(marks.allSatisfy { $0.updatedAt == clock.now.roundedToMillisecond })
    }

    @Test func aBackdatedBreakEndKeepsTheShiftValid() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        actions.perform(.clockIn(fieldId: nil))
        clock.advance(minutes: 60)
        actions.perform(.startBreak(.lunch, reason: ""))
        clock.advance(minutes: 20)
        let tapped = clock.now
        clock.advance(minutes: 15)
        let reply = actions.perform(.endBreak, at: tapped)
        #expect(reply.succeeded)
        let shift = try #require(session.snapshot.openShift(for: f.userId))
        #expect(shift.breaks.first?.end == tapped.roundedToMillisecond)
        #expect(shift.updatedAt == clock.now.roundedToMillisecond)
    }

    @Test func undoStillWorksAfterABackdatedTap() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        actions.perform(.clockIn(fieldId: nil))
        clock.advance(minutes: 10)
        let tapped = clock.now
        clock.advance(minutes: 5)
        actions.perform(.markRow(RowRef(blockId: f.blockId, row: 0)), at: tapped)
        clock.advance(minutes: 1)
        #expect(actions.perform(.undo).speech == "Undid row 1.")
        #expect(session.snapshot.marks.values.filter { $0.row == 0 && $0.isLive }.isEmpty)
    }

    @Test func aWatchClockInCanBeCancelledWithinFiveMinutes() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        let minted = UUID()
        actions.perform(.clockIn(fieldId: nil), at: clock.now, newShiftId: minted)
        clock.advance(minutes: 2)
        let reply = actions.perform(.cancelShift(minted), at: clock.now)
        #expect(reply.succeeded)
        #expect(reply.lastAction == "Clock-in cancelled")
        #expect(session.snapshot.openShift(for: f.userId) == nil)
        // Deleted: the store keeps no live copy, and the delete waits to sync.
        #expect(session.snapshot.shifts[minted]?.isLive != true)
        #expect(try store.pendingCount(farmId: f.farmId) >= 1)
    }

    @Test func refusalsChangeNothing() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        let reply = actions.perform(.endBreak, at: clock.now.addingTimeInterval(-60))
        #expect(!reply.succeeded)
        #expect(reply.speech == Speech.notClockedIn)
        #expect(session.snapshot.shifts.isEmpty)
    }

    @Test func signedOutAsksToOpenTheApp() {
        let session = TimeCardSession(store: store, api: StubAPIClient(), tokens: tokens, deviceName: "Test iPhone")
        let actions = FieldActions(session: session, now: clock.read)
        #expect(actions.perform(.clockIn(fieldId: nil), at: clock.now, newShiftId: UUID()).speech == Speech.signedOut)
    }

    @Test func theAppsOwnTapsAreUnchanged() async throws {
        let session = try await signedInSession()
        let actions = FieldActions(session: session, now: clock.read)
        actions.perform(.clockIn(fieldId: nil))
        let shift = try #require(session.snapshot.openShift(for: f.userId))
        #expect(shift.start == clock.now.roundedToMillisecond)
        #expect(shift.updatedAt == clock.now.roundedToMillisecond)
    }
}
