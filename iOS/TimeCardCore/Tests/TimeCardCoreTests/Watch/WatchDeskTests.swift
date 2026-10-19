import Foundation
import Testing
@testable import TimeCardCore

/// The phone's side of the watch link (docs/watch.md 1.3): one reply per request, retries
/// answered from the inbox, taps for someone else or for a closed shift refused, the rest run
/// at their tap time and stamped when received, and every state from one revision counter.
@MainActor
@Suite("Watch desk")
struct WatchDeskTests {
    let f = Fixtures()
    let tokens = InMemoryTokenStore()
    let store: LocalStore
    let clock = TestClock(Fixtures.t0)
    let settings = SettingsBox()

    init() throws {
        store = try LocalStore.inMemory()
    }

    // MARK: Setup

    final class SettingsBox {
        var value = WatchSettings()
    }

    var me: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    var sam: Member {
        Member(userId: f.otherUserId, farmId: f.farmId, displayName: "Sam", email: "sam@example.com", role: .worker, rateCents: 1500, updatedAt: Fixtures.t0)
    }

    func makeSession(signIn: Bool = true) async throws -> TimeCardSession {
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, f.layout + [.member(sam)])
        await stub.addAccount(email: "josh@example.com", password: "pw", me: me)
        var config = SyncEngine.Configuration()
        config.debounce = .milliseconds(20)
        let session = TimeCardSession(store: store, api: stub, tokens: tokens, deviceName: "Test iPhone", engineConfiguration: config)
        if signIn {
            try await session.signIn(email: "josh@example.com", password: "pw")
            _ = await session.syncNow()
        } else {
            await session.start()
        }
        return session
    }

    func makeDesk(_ session: TimeCardSession) -> (FieldActions, WatchDesk) {
        let actions = FieldActions(session: session, now: clock.read)
        let box = settings
        let desk = WatchDesk(actions: actions, store: store, settings: { box.value }, now: clock.read)
        return (actions, desk)
    }

    func request(_ command: FieldCommand, at issuedAt: Date? = nil, id: UUID = UUID(), userId: UUID?? = .none, shiftId: UUID? = nil) -> WatchRequest {
        WatchRequest(id: id, body: .command(command), issuedAt: issuedAt ?? clock.now,
                     userId: userId ?? f.userId, shiftId: shiftId)
    }

    func envelope(_ request: WatchRequest) throws -> Data {
        try WatchEnvelope(.request(request)).data()
    }

    func send(_ request: WatchRequest, to desk: WatchDesk) throws -> WatchReply {
        try reply(desk.handle(try envelope(request), receivedAt: clock.now))
    }

    func reply(_ data: Data) throws -> WatchReply {
        guard case .reply(let reply) = try WatchEnvelope.decode(data).message else {
            Issue.record("not a reply")
            throw CancellationError()
        }
        return reply
    }

    func spoken(_ date: Date) -> String { Fmt.spokenTime(date, FarmCalendar(farm: f.farm)) }

    var row0: RowRef { RowRef(blockId: f.blockId, row: 0) }
    var row1: RowRef { RowRef(blockId: f.blockId, row: 1) }

    func shift(_ id: UUID, in session: TimeCardSession) -> Shift? { session.snapshot.shifts[id] }

    /// The watch clocks in under a minted id, as a live tap.
    @discardableResult
    func watchClockIn(_ desk: WatchDesk, minted: UUID = UUID()) throws -> UUID {
        let r = try send(request(.clockIn(fieldId: nil), shiftId: minted), to: desk)
        #expect(r.succeeded, "\(r.speech)")
        return minted
    }

    // MARK: Running taps

    @Test func aClockInCreatesTheShiftWithTheMintedId() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let minted = UUID()
        let r = try send(request(.clockIn(fieldId: nil), shiftId: minted), to: desk)
        #expect(r.succeeded)
        #expect(r.speech == "Clocked in at \(spoken(clock.now)). You’re on block 1, row 1.")
        #expect(r.lastAction == "Clocked in")
        #expect(session.snapshot.openShift(for: f.userId)?.id == minted)
        #expect(r.state?.shiftId == minted)
        #expect(r.appliedAt == clock.now.roundedToMillisecond || r.appliedAt == clock.now)
    }

    @Test func theEventTimeIsTheTapAndUpdatedAtIsWhenItArrived() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let tappedIn = clock.now
        let minted = UUID()
        clock.advance(minutes: 20)
        #expect(try send(request(.clockIn(fieldId: nil), at: tappedIn, shiftId: minted), to: desk).succeeded)
        let opened = try #require(shift(minted, in: session))
        #expect(opened.start == tappedIn.roundedToMillisecond)
        #expect(opened.updatedAt == clock.now.roundedToMillisecond)

        let tappedRow = clock.now.addingTimeInterval(5 * 60)
        clock.advance(minutes: 30)
        let marked = try send(request(.markRow(row0), at: tappedRow, shiftId: minted), to: desk)
        #expect(marked.succeeded)
        #expect(marked.appliedAt == tappedRow)
        let marks = session.snapshot.marks.values.filter { $0.row == 0 && $0.isLive }
        #expect(marks.count == 10)
        #expect(marks.allSatisfy { $0.markedAt == tappedRow.roundedToMillisecond && $0.updatedAt == clock.now.roundedToMillisecond })

        let tappedLunch = clock.now.addingTimeInterval(-10 * 60)
        clock.advance(minutes: 1)
        #expect(try send(request(.startBreak(.lunch, reason: ""), at: tappedLunch, shiftId: minted), to: desk).succeeded)
        let onLunch = try #require(shift(minted, in: session))
        #expect(onLunch.breaks.first?.start == tappedLunch.roundedToMillisecond)
        #expect(onLunch.updatedAt == clock.now.roundedToMillisecond)
    }

    @Test func aTapFromTheFutureCountsWhenItArrived() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let minted = UUID()
        // The watch's clock runs two minutes ahead.
        _ = try send(request(.clockIn(fieldId: nil), at: clock.now.addingTimeInterval(120), shiftId: minted), to: desk)
        #expect(shift(minted, in: session)?.start == clock.now.roundedToMillisecond)
    }

    @Test func aDuplicateRunsOnceAndTheRetryGetsAFreshState() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let minted = try watchClockIn(desk)
        let mark = request(.markRow(row0), shiftId: minted)
        let first = try send(mark, to: desk)
        clock.advance(minutes: 1)
        let retry = try send(mark, to: desk)
        #expect(first.succeeded && retry.succeeded)
        #expect(retry.speech == first.speech)
        #expect(session.snapshot.marks.values.filter { $0.row == 0 && $0.isLive }.count == 10)
        // Row 2 is next, not row 3: the retry didn't mark again.
        #expect(retry.state?.nextRows.first?.row == 1)
        let firstRevision = try #require(first.state?.revision)
        #expect(try #require(retry.state?.revision) > firstRevision)
        #expect(retry.state?.appliedRequestIds.last == mark.id)
    }

    @Test func aReplyAlwaysCarriesStateWithTheAnsweredId() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let tap = request(.clockIn(fieldId: nil), shiftId: UUID())
        let r = try send(tap, to: desk)
        #expect(r.requestId == tap.id)
        #expect(r.state?.appliedRequestIds.contains(tap.id) == true)
        #expect(r.state?.signedIn == true)
        #expect(r.keepQueued == false)
    }

    @Test func undoClockInCancelsTheShift() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let minted = try watchClockIn(desk)
        clock.advance(minutes: 1)
        let r = try send(request(.cancelShift(minted), shiftId: minted), to: desk)
        #expect(r.succeeded)
        #expect(r.lastAction == "Clock-in cancelled")
        #expect(session.snapshot.openShift(for: f.userId) == nil)
        #expect(r.state?.isClockedIn == false)
    }

    // MARK: The right shift

    @Test func aQueuedClockOutAfterANewPhoneClockInIsRefused() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let started = clock.now
        let minted = try watchClockIn(desk)
        clock.advance(minutes: 50)
        let tappedOut = clock.now
        // The watch's clock-out waits out of reach; the phone clocks out and in again.
        clock.advance(minutes: 10)
        #expect(actions.perform(.clockOut).succeeded)
        clock.advance(minutes: 60)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        let today = try #require(session.snapshot.openShift(for: f.userId))
        clock.advance(minutes: 5)
        let r = try send(request(.clockOut, at: tappedOut, shiftId: minted), to: desk)
        #expect(!r.succeeded)
        #expect(r.keepQueued == false)
        #expect(r.speech == "That clock-out was for the shift that started at \(spoken(started)), which is already closed, so it wasn’t applied.")
        #expect(session.snapshot.openShift(for: f.userId)?.id == today.id)
        #expect(r.state?.shiftId == today.id)
    }

    @Test func marksFromAClosedShiftAreRefused() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let started = clock.now
        let minted = try watchClockIn(desk)
        clock.advance(minutes: 30)
        let tapped = clock.now
        clock.advance(minutes: 30)
        #expect(actions.perform(.clockOut).succeeded)
        clock.advance(minutes: 5)
        let r = try send(request(.markRow(RowRef(blockId: f.blockId, row: 13)), at: tapped, shiftId: minted), to: desk)
        #expect(!r.succeeded)
        #expect(r.speech == "Row 14 was marked during the shift that started at \(spoken(started)), which is already closed, so it wasn’t applied. Fix it in the Log.")
        #expect(session.snapshot.marks.values.filter(\.isLive).isEmpty)
    }

    @Test func aTapForAShiftWhenNoneIsOpenSaysSo() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let r = try send(request(.startBreak(.lunch, reason: ""), shiftId: UUID()), to: desk)
        #expect(!r.succeeded)
        #expect(r.keepQueued == false)
        #expect(r.speech == "You’re not clocked in, so that lunch wasn’t applied.")
    }

    @Test func aClockInOlderThanTheLastShiftsEndIsRefused() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        clock.advance(minutes: 60)
        let tapped = clock.now
        clock.advance(minutes: 30)
        let ended = clock.now
        #expect(actions.perform(.clockOut).succeeded)
        clock.advance(minutes: 5)
        let r = try send(request(.clockIn(fieldId: nil), at: tapped, shiftId: UUID()), to: desk)
        #expect(!r.succeeded)
        #expect(r.speech == "That clock-in at \(spoken(tapped)) was before your last shift ended at \(spoken(ended)), so it wasn’t applied.")
        #expect(session.snapshot.openShift(for: f.userId) == nil)
    }

    @Test func aRefusedClockInAliasesItsIdSoLaterMarksApply() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let phoneStart = clock.now
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        let open = try #require(session.snapshot.openShift(for: f.userId))
        clock.advance(minutes: 2)
        let minted = UUID()
        let refused = try send(request(.clockIn(fieldId: nil), shiftId: minted), to: desk)
        #expect(!refused.succeeded)
        #expect(refused.keepQueued == false)
        #expect(refused.speech == "You’re already clocked in since \(spoken(phoneStart)).")
        clock.advance(minutes: 3)
        let marked = try send(request(.markRow(row0), shiftId: minted), to: desk)
        #expect(marked.succeeded, "\(marked.speech)")
        #expect(session.snapshot.marks.values.filter { $0.row == 0 && $0.isLive }.allSatisfy { $0.shiftId == open.id })
    }

    @Test func theAliasSurvivesANewDeskOnTheSameStore() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        let minted = UUID()
        _ = try send(request(.clockIn(fieldId: nil), shiftId: minted), to: desk)
        let (_, relaunched) = makeDesk(session)
        clock.advance(minutes: 1)
        #expect(try send(request(.markRow(row0), shiftId: minted), to: relaunched).succeeded)
    }

    @Test func aQueuedEndOfBreakNeverLandsBeforeTheBreakStarted() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let minted = try watchClockIn(desk)
        clock.advance(minutes: 60)
        let watchTap = clock.now
        clock.advance(minutes: 2)
        let breakStart = clock.now
        #expect(actions.perform(.startBreak(.break, reason: "")).succeeded)
        clock.advance(minutes: 10)
        let r = try send(request(.endBreak, at: watchTap, shiftId: minted), to: desk)
        #expect(r.succeeded, "\(r.speech)")
        #expect(r.appliedAt == breakStart.roundedToMillisecond)
        // Ended the moment it began, so the engine leaves no zero-length break behind.
        let after = try #require(shift(minted, in: session))
        #expect(after.openBreak == nil)
        #expect(after.breaks.isEmpty)
    }

    @Test func aQueuedTapThePhoneMovedPastGetsTheEnginesSentence() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let minted = try watchClockIn(desk)
        clock.advance(minutes: 120)
        let lunchStart = clock.now
        #expect(actions.perform(.startBreak(.lunch, reason: "")).succeeded)
        clock.advance(minutes: 1)
        let r = try send(request(.startBreak(.lunch, reason: ""), shiftId: minted), to: desk)
        #expect(!r.succeeded)
        #expect(r.keepQueued == false)
        #expect(r.speech.hasPrefix("You’re already on lunch since \(spoken(lunchStart))."))
    }

    @Test func aShiftTapWithoutAShiftIdCountsOnlyIfMadeDuringTheOpenShift() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let before = clock.now
        clock.advance(minutes: 5)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        clock.advance(minutes: 5)
        let early = try send(request(.markRow(row0), at: before, shiftId: nil), to: desk)
        #expect(!early.succeeded)
        #expect(early.speech == "Row 1 was marked during an earlier shift, which is already closed, so it wasn’t applied. Fix it in the Log.")
        let during = try send(request(.markRow(row0), shiftId: nil), to: desk)
        #expect(during.succeeded)
    }

    // MARK: The right person

    @Test func tapsForSomeoneElseAreNotApplied() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let r = try send(request(.clockIn(fieldId: nil), userId: f.otherUserId, shiftId: UUID()), to: desk)
        #expect(!r.succeeded)
        #expect(r.keepQueued == false)
        #expect(r.speech == "These taps were for Sam, so they weren’t applied.")
        #expect(session.snapshot.openShift(for: f.userId) == nil)
    }

    @Test func tapsForSomeoneUnknownAreNotApplied() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let r = try send(request(.clockIn(fieldId: nil), userId: UUID(), shiftId: UUID()), to: desk)
        #expect(r.speech == "These taps were for someone else, so they weren’t applied.")
    }

    @Test func tapsWithNoPersonCountAsSomeoneElse() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let r = try send(request(.clockIn(fieldId: nil), userId: .some(nil), shiftId: UUID()), to: desk)
        #expect(!r.succeeded)
        #expect(r.keepQueued == false)
        #expect(r.speech == "These taps were made before you signed in, so they weren’t applied.")
        #expect(session.snapshot.openShift(for: f.userId) == nil)
    }

    @Test func signedOutKeepsTheTapQueuedAndItAppliesAfterSigningIn() async throws {
        let session = try await makeSession(signIn: false)
        let (_, desk) = makeDesk(session)
        let tap = request(.clockIn(fieldId: nil), shiftId: UUID())
        let first = try send(tap, to: desk)
        #expect(!first.succeeded)
        #expect(first.keepQueued)
        #expect(first.speech == FieldActions.signedOut)
        #expect(first.state?.signedIn == false)
        // Not remembered: once the same person signs in, the retry runs.
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        clock.advance(minutes: 1)
        let retry = try send(tap, to: desk)
        #expect(retry.succeeded, "\(retry.speech)")
        #expect(session.snapshot.openShift(for: f.userId)?.id == tap.shiftId)
    }

    // MARK: Unreadable envelopes

    @Test func anUndecodableEnvelopeGetsAnUnreadableReplyWithState() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let r = try reply(desk.handle(Data("garbage".utf8), receivedAt: clock.now))
        #expect(r.requestId == WatchReply.unreadableId)
        #expect(r.keepQueued)
        #expect(!r.succeeded)
        #expect(r.speech == "Update Time Card on your iPhone.")
        #expect(r.state?.signedIn == true)
    }

    @Test func aNewerEnvelopeGetsTheSameAnswer() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let newer = Data(#"{"v":99,"message":{"somethingNew":{}}}"#.utf8)
        let r = try reply(desk.handle(newer, receivedAt: clock.now))
        #expect(r.requestId == WatchReply.unreadableId)
        #expect(r.keepQueued)
        #expect(r.state != nil)
    }

    @Test func aPhoneThatCantReadItsDataKeepsTheTapQueuedWithNoState() throws {
        let tap = request(.clockIn(fieldId: nil), shiftId: UUID())
        let r = try reply(WatchDesk.unavailable(try envelope(tap), speech: Speech.unlockOnce))
        #expect(r.requestId == tap.id)
        #expect(r.keepQueued)
        #expect(!r.succeeded)
        #expect(r.speech == Speech.unlockOnce)
        #expect(r.state == nil)
        let garbled = try reply(WatchDesk.unavailable(Data("x".utf8), speech: Speech.unlockOnce))
        #expect(garbled.requestId == WatchReply.unreadableId)
    }

    // MARK: Questions

    @Test func questionsAreAnsweredWithState() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let ask = WatchRequest(body: .question(.hours), issuedAt: clock.now, userId: f.userId)
        let r = try send(ask, to: desk)
        #expect(r.succeeded)
        #expect(r.speech == actions.answer(.hours))
        #expect(r.state != nil)
    }

    @Test func payIsNeverSaidOnTheWatch() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let ask = WatchRequest(body: .question(.pay(locked: false, sayWhenLocked: true)), issuedAt: clock.now, userId: f.userId)
        let r = try send(ask, to: desk)
        #expect(r.speech == "Unlock your phone to hear your pay.")
        #expect(!r.speech.contains("$"))
    }

    @Test func aRefreshChangesNothingAndCarriesState() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let before = session.snapshot.revision
        let r = try send(WatchRequest(body: .refresh, issuedAt: clock.now, userId: f.userId), to: desk)
        #expect(r.succeeded)
        #expect(r.state?.signedIn == true)
        #expect(session.snapshot.revision == before)
    }

    // MARK: One counter

    @Test func replyAndPublishedStatesShareTheCounter() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let published = desk.makeState()
        let r = try send(request(.clockIn(fieldId: nil), shiftId: UUID()), to: desk)
        let after = desk.makeState()
        let replied = try #require(r.state)
        #expect(replied.revision > published.revision)
        #expect(after.revision > replied.revision)
        #expect(Set([published.epoch, replied.epoch, after.epoch]).count == 1)
        #expect(published.epoch != WatchState.noEpoch)
    }

    @Test func theRevisionAndEpochPersistAcrossANewDesk() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let one = desk.makeState()
        let two = desk.makeState()
        let (_, relaunched) = makeDesk(session)
        let three = relaunched.makeState()
        #expect(two.revision == one.revision + 1)
        #expect(three.revision == two.revision + 1)
        #expect(three.epoch == one.epoch)
    }

    @Test func anEmptyStoreStartsANewEpoch() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let old = desk.makeState()
        let freshStore = try LocalStore.inMemory()
        let fresh = WatchDesk(actions: FieldActions(session: session, now: clock.read), store: freshStore, settings: { WatchSettings() }, now: clock.read)
        let first = fresh.makeState()
        #expect(first.revision == 1)
        #expect(first.epoch != old.epoch)
        #expect(first.supersedes(old))
    }

    /// Reads go through, writes fail: a suspended database (WAL reads still work) or a full disk.
    final class RefusingWrites: KeyValueStore, @unchecked Sendable {
        struct Refused: Error {}
        let base: any KeyValueStore
        private let lock = NSLock()
        private var _refusing = true
        var refusing: Bool {
            get { lock.withLock { _refusing } }
            set { lock.withLock { _refusing = newValue } }
        }

        init(_ base: any KeyValueStore) { self.base = base }

        func value(forKey key: String) throws -> Data? { try base.value(forKey: key) }

        func setValue(_ value: Data?, forKey key: String) throws {
            if refusing { throw Refused() }
            try base.setValue(value, forKey: key)
        }
    }

    func makeDesk(_ session: TimeCardSession, store: any KeyValueStore) -> WatchDesk {
        WatchDesk(actions: FieldActions(session: session, now: clock.read), store: store, settings: { WatchSettings() }, now: clock.read)
    }

    @Test func aCounterThatCantBeSavedNeverRepeatsARevision() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let saved = desk.makeState()
        let refusing = RefusingWrites(store)
        let stuck = makeDesk(session, store: refusing)
        let r = try reply(stuck.handle(try envelope(request(.clockIn(fieldId: nil), shiftId: UUID())), receivedAt: clock.now))
        let replied = try #require(r.state)
        let next = stuck.makeState()
        let after = stuck.makeState()
        // Two states that tie would leave the watch on the older one.
        #expect(replied.revision > saved.revision)
        #expect(next.revision > replied.revision)
        #expect(after.revision > next.revision)
        #expect(Set([saved.epoch, replied.epoch, next.epoch, after.epoch]).count == 1)
    }

    @Test func anEmptyStoreThatCantBeWrittenKeepsOneEpoch() async throws {
        let session = try await makeSession()
        let refusing = RefusingWrites(try LocalStore.inMemory())
        let desk = makeDesk(session, store: refusing)
        let states = (0..<3).map { _ in desk.makeState() }
        // A new epoch per state would make the watch take every one, in any order.
        #expect(Set(states.map(\.epoch)).count == 1)
        #expect(states.map(\.revision) == [1, 2, 3])
    }

    @Test func theCounterCarriesOnOnceItCanBeSavedAgain() async throws {
        let session = try await makeSession()
        let refusing = RefusingWrites(try LocalStore.inMemory())
        let desk = makeDesk(session, store: refusing)
        let early = desk.makeState()
        _ = desk.makeState()
        refusing.refusing = false
        let saved = desk.makeState()
        #expect(saved.revision == 3)
        #expect(saved.epoch == early.epoch)
        // The next launch follows on from what was handed out, in the same epoch.
        let relaunched = makeDesk(session, store: refusing).makeState()
        #expect(relaunched.epoch == early.epoch)
        #expect(relaunched.revision == 4)
    }

    @Test func twoDesksOnOneStoreShareTheCounter() async throws {
        let session = try await makeSession()
        let (_, first) = makeDesk(session)
        let (_, second) = makeDesk(session)
        let a = first.makeState()
        let b = second.makeState()
        let c = first.makeState()
        #expect(b.revision > a.revision)
        #expect(c.revision > b.revision)
        #expect(Set([a.epoch, b.epoch, c.epoch]).count == 1)
    }

    @Test func aSettingsChangeShowsInTheNextState() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let on = try send(WatchRequest(body: .refresh, issuedAt: clock.now, userId: f.userId), to: desk)
        settings.value.recordWorkouts = false
        let off = try send(WatchRequest(body: .refresh, issuedAt: clock.now, userId: f.userId), to: desk)
        #expect(on.state?.recordWorkouts == true)
        #expect(off.state?.recordWorkouts == false)
    }

    @Test func theSignedOutStateUsesTheCounterToo() async throws {
        let session = try await makeSession(signIn: false)
        let (_, desk) = makeDesk(session)
        let a = desk.makeState()
        let b = desk.makeState()
        #expect(!a.signedIn && !b.signedIn)
        #expect(b.revision == a.revision + 1)
        #expect(a.epoch == b.epoch)
    }

    @Test func theDeskRemembersThePhaseOfTheLastStateItMade() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        #expect(desk.lastPhase == nil)
        _ = desk.makeState()
        #expect(desk.lastPhase == .offClock)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        _ = desk.makeState()
        #expect(desk.lastPhase == .working)
        let (_, relaunched) = makeDesk(session)
        #expect(relaunched.lastPhase == .working)
    }

    @Test func theDeskKnowsWhichShiftsTheWatchOpened() async throws {
        let session = try await makeSession()
        let (actions, desk) = makeDesk(session)
        let minted = try watchClockIn(desk)
        #expect(desk.openedByWatch(minted))
        clock.advance(minutes: 3)
        _ = try send(request(.cancelShift(minted), shiftId: minted), to: desk)
        #expect(actions.perform(.clockIn(fieldId: nil)).succeeded)
        let phone = try #require(session.snapshot.openShift(for: f.userId))
        #expect(!desk.openedByWatch(phone.id))
    }

    // MARK: Workout summaries

    @Test func aWorkoutSummaryIsKeptOnThePhoneOnly() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let pending = try store.pendingCount()
        let summary = WorkoutSummary(shiftId: UUID(), start: clock.now, end: clock.now.addingTimeInterval(3600),
                                     activeDuration: 3500, activeKcal: 320, avgHeartRate: 104, maxHeartRate: 151)
        desk.save(summary)
        #expect(desk.summary(for: try #require(summary.shiftId)) == summary)
        #expect(try store.pendingCount() == pending)
    }

    @Test func aPostedSummaryEnvelopeIsSaved() async throws {
        let session = try await makeSession()
        let (_, desk) = makeDesk(session)
        let summary = WorkoutSummary(shiftId: UUID(), start: clock.now, end: clock.now.addingTimeInterval(600), activeDuration: 590)
        desk.receive(try WatchEnvelope(.workoutSummary(summary)).data())
        #expect(desk.summary(for: try #require(summary.shiftId)) == summary)
    }
}
