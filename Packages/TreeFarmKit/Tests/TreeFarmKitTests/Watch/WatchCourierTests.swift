import Foundation
import Testing
@testable import TreeFarmKit
import TreeFarmKitTestSupport

/// The watch's courier: the persistent outbox, one request in flight at a time, oldest first,
/// and every way a reply can go missing (docs/watch.md 1.4).
@Suite("Watch courier")
struct WatchCourierTests {
    let t0 = Date(timeIntervalSince1970: 1_792_400_000)
    let block = UUID()
    let shift = UUID()

    func mark(_ row: Int, at minute: Double = 0) -> WatchRequest {
        WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: row - 1))), issuedAt: t0.addingTimeInterval(minute * 60),
                     userId: nil, shiftId: shift)
    }

    func command(_ command: FieldCommand, at minute: Double = 0) -> WatchRequest {
        WatchRequest(body: .command(command), issuedAt: t0.addingTimeInterval(minute * 60), shiftId: shift)
    }

    func courier(_ transport: FakeWatchTransport, store: InMemoryOutboxStore = InMemoryOutboxStore(),
                 timeout: Duration = .seconds(2)) -> WatchCourier {
        WatchCourier(transport: transport, store: store, replyTimeout: timeout, now: { [t0] in t0 })
    }

    /// A phone that answers with a state of the given revision, listing the request as applied.
    func answer(_ data: Data, revision: Int) -> Data {
        let r = ScriptedPhone.request(data)!
        let state = WatchState(signedIn: true, farmName: "", fieldName: "", snapshot: nil, nextRows: [], todayWorked: 0, todayTrees: 0,
                               canUndo: false, recordWorkouts: true, updatedAt: t0, epoch: shift, revision: revision,
                               appliedRequestIds: [r.id])
        return FakeWatchTransport.envelope(.reply(WatchReply(requestId: r.id, speech: "Done.", succeeded: true, state: state)))
    }

    // MARK: Sending

    @Test func theSnapshotThatDropsATapCarriesItsReplysState() async {
        // The model reads both at once, so the workout never sees a flushed clock-in gone while the
        // state it holds is still the old one (docs/watch.md 2.2, rule 6).
        let fake = FakeWatchTransport(reachable: false)
        let c = courier(fake)
        _ = await c.submit(mark(14, at: 0), durable: true)
        _ = await c.submit(mark(15, at: 1), durable: true)
        #expect(await c.snapshot.replyState == nil)
        fake.enqueue(.respond { [self] in answer($0, revision: 7) }, .respond { [self] in answer($0, revision: 6) })

        fake.setReachable(true)
        await c.flush()

        let snapshot = await c.snapshot
        #expect(snapshot.outbox.isEmpty)
        #expect(snapshot.replyState?.revision == 7, "the newest state, never an older one that came after it")
    }

    @Test func aLiveReplysStateTravelsWithTheSnapshotToo() async {
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { [self] in answer($0, revision: 9) }
        let c = courier(fake)

        _ = await c.submit(WatchRequest(body: .refresh, issuedAt: t0), durable: false)

        #expect(await c.snapshot.replyState?.revision == 9)
    }

    @Test func aReachablePhoneAnswersADurableTap() async {
        let phone = ScriptedPhone()
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { phone.answer($0) }
        let c = courier(fake)
        let r = mark(14)

        let result = await c.submit(r, durable: true)

        guard case .replied(let reply) = result else { Issue.record("expected a reply, got \(result)"); return }
        #expect(reply.requestId == r.id && reply.succeeded)
        #expect(await c.outbox.isEmpty)
        #expect(await c.inFlight.isEmpty)
        #expect(phone.runs == [r.id])
    }

    @Test func oneRequestInFlightAtATimeInOrder() async {
        let phone = ScriptedPhone()
        let gauge = Gauge()
        let fake = FakeWatchTransport(reachable: false)
        fake.defaultAnswer = .respond { data in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(15))
            await gauge.leave()
            return phone.answer(data)
        }
        let c = courier(fake)
        let taps = [mark(14, at: 0), mark(15, at: 1), mark(16, at: 2)]
        for tap in taps { _ = await c.submit(tap, durable: true) }

        fake.setReachable(true)
        await c.flush()

        #expect(phone.runs == taps.map(\.id))
        #expect(fake.sentRequests.map(\.id) == taps.map(\.id))
        #expect(await gauge.most == 1)
        #expect(await c.outbox.isEmpty)
    }

    @Test func tapsMadeAtOnceStillGoOneAtATime() async {
        let phone = ScriptedPhone()
        let gauge = Gauge()
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { data in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(10))
            await gauge.leave()
            return phone.answer(data)
        }
        let c = courier(fake)
        async let a = c.submit(mark(14, at: 0), durable: true)
        async let b = c.submit(mark(15, at: 1), durable: true)
        async let d = c.submit(mark(16, at: 2), durable: true)
        let results = await [a, b, d]

        for result in results {
            guard case .replied(let reply) = result else { Issue.record("expected a reply, got \(result)"); continue }
            #expect(reply.succeeded)
        }
        #expect(await gauge.most == 1)
        #expect(phone.runs.count == 3)
        #expect(await c.outbox.isEmpty)
    }

    @Test func unreachableQueuesAndSendsNothing() async {
        let fake = FakeWatchTransport(reachable: false)
        let store = InMemoryOutboxStore()
        let c = courier(fake, store: store)

        let first = await c.submit(mark(14), durable: true)
        let second = await c.submit(mark(15, at: 1), durable: true)

        #expect(first == .queued(count: 1))
        #expect(second == .queued(count: 2))
        #expect(fake.sent.isEmpty)
        #expect(store.load()?.pending.count == 2)
    }

    @Test func theOutboxIsSavedAfterEveryChangeAndLoadedAgain() async {
        let fake = FakeWatchTransport(reachable: false)
        let store = InMemoryOutboxStore()
        let c = courier(fake, store: store)
        _ = await c.submit(mark(14), durable: true)
        _ = await c.submit(mark(15, at: 1), durable: true)
        _ = await c.takeBackLastQueued()
        #expect(store.saves == 3)

        let again = courier(fake, store: store)
        #expect(await again.outbox.pending.map(\.id) == store.load()?.pending.map(\.id))
        #expect(await again.outbox.count == 1)
    }

    @Test func aTimeoutKeepsTheTapQueuedAndSaysWaiting() async {
        let fake = FakeWatchTransport()
        fake.enqueue(.lost)
        let c = courier(fake, timeout: .milliseconds(40))
        let events = EventLog(c.updates)
        let r = mark(14)

        let result = await c.submit(r, durable: true)

        #expect(result == .queued(count: 1))
        #expect(await c.outbox.pending.map(\.id) == [r.id])
        #expect(await c.inFlight.isEmpty)
        #expect(await events.waitFor { $0.contains(.waiting(r.id)) })
    }

    @Test func aLateReplyAfterTheTimeoutIsIgnoredAndTheRetryIsDeduped() async throws {
        let phone = ScriptedPhone()
        let fake = FakeWatchTransport()
        // The first answer arrives after the watch gave up waiting; the phone ran it then.
        fake.enqueue(.after(.milliseconds(150), .respond { phone.answer($0) }))
        fake.defaultAnswer = .respond { phone.answer($0) }
        let c = courier(fake, timeout: .milliseconds(30))
        let r = mark(14)

        #expect(await c.submit(r, durable: true) == .queued(count: 1))
        try await Task.sleep(for: .milliseconds(300))
        #expect(fake.lateReplies == 1)
        #expect(phone.runs == [r.id])

        await c.flush()

        #expect(await c.outbox.isEmpty)
        #expect(phone.runs == [r.id], "the retry got the saved reply and didn't run again")
        #expect(phone.answered == [r.id, r.id])
    }

    @Test func keepQueuedStaysInTheOutbox() async {
        let fake = FakeWatchTransport()
        let r = mark(14)
        let signedOut = WatchReply(requestId: r.id, speech: "Open Time Card to sign in.", succeeded: false, keepQueued: true)
        fake.enqueue(.reply(FakeWatchTransport.envelope(.reply(signedOut))))
        let c = courier(fake)

        let result = await c.submit(r, durable: true)

        #expect(result == .replied(signedOut))
        #expect(await c.outbox.pending.map(\.id) == [r.id])
    }

    @Test func keepQueuedStopsTheFlushUntilLater() async {
        let fake = FakeWatchTransport(reachable: false)
        let c = courier(fake)
        let a = mark(14), b = mark(15, at: 1)
        _ = await c.submit(a, durable: true)
        _ = await c.submit(b, durable: true)
        fake.defaultAnswer = .respond { data in
            let r = ScriptedPhone.request(data)!
            return FakeWatchTransport.envelope(.reply(WatchReply(requestId: r.id, speech: "Not now.", succeeded: false, keepQueued: true)))
        }
        fake.setReachable(true)

        await c.flush()

        #expect(fake.sentRequests.map(\.id) == [a.id])
        #expect(await c.outbox.count == 2)
    }

    @Test func aRefusalStillLeavesTheOutbox() async {
        let fake = FakeWatchTransport()
        let r = mark(14)
        let refused = WatchReply(requestId: r.id, speech: "Row 14 is already marked.", succeeded: false)
        fake.enqueue(.reply(FakeWatchTransport.envelope(.reply(refused))))
        let c = courier(fake)

        let result = await c.submit(r, durable: true)

        #expect(result == .replied(refused))
        #expect(await c.outbox.isEmpty)
    }

    @Test func aReplyTheWatchCantReadKeepsTheTapAndSaysUpdate() async {
        let fake = FakeWatchTransport()
        // A newer phone app: version 2 envelopes.
        fake.enqueue(.reply(Data(#"{"v":2,"message":{"future":{}}}"#.utf8)))
        let c = courier(fake)
        let r = mark(14)

        let result = await c.submit(r, durable: true)

        guard case .replied(let reply) = result else { Issue.record("expected a reply, got \(result)"); return }
        #expect(reply.speech == WatchDisplay.updateWatch)
        #expect(reply.keepQueued)
        #expect(await c.outbox.pending.map(\.id) == [r.id])
    }

    @Test func aDurableTapSurvivesALostReplyAndAStateWithItsIdClearsIt() async {
        let fake = FakeWatchTransport()
        fake.enqueue(.lost)
        let c = courier(fake, timeout: .milliseconds(30))
        let r = mark(14)

        #expect(await c.submit(r, durable: true) == .queued(count: 1))
        #expect(await c.outbox.count == 1)

        var state = WatchState.signedOut(epoch: UUID(), revision: 3, now: t0)
        state.appliedRequestIds = [UUID(), r.id]
        await c.acknowledge(state)

        #expect(await c.outbox.isEmpty)
    }

    @Test func aReplysStateClearsOtherAppliedTaps() async {
        let fake = FakeWatchTransport(reachable: false)
        let c = courier(fake)
        let a = mark(14), b = mark(15, at: 1)
        _ = await c.submit(a, durable: true)
        _ = await c.submit(b, durable: true)
        // The phone had already applied b (its reply was lost earlier) when it answers a.
        var state = WatchState.signedOut(epoch: UUID(), revision: 9, now: t0)
        state.appliedRequestIds = [b.id, a.id]
        fake.enqueue(.reply(FakeWatchTransport.envelope(.reply(WatchReply(requestId: a.id, speech: "Row 14 marked.", succeeded: true, state: state)))))
        fake.setReachable(true)

        await c.flush()

        #expect(await c.outbox.isEmpty)
        #expect(fake.sentRequests.map(\.id) == [a.id])
    }

    // MARK: Live-only requests

    @Test func undoWhileReachableBypassesTheOutbox() async {
        let phone = ScriptedPhone()
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { phone.answer($0) }
        let store = InMemoryOutboxStore()
        let c = courier(fake, store: store)
        let undo = WatchRequest(body: .command(.undo), issuedAt: t0)

        let result = await c.submit(undo, durable: false)

        guard case .replied(let reply) = result else { Issue.record("expected a reply, got \(result)"); return }
        #expect(reply.requestId == undo.id)
        #expect(store.saves == 0)
        #expect(await c.outbox.isEmpty)
    }

    @Test func undoWhileUnreachableIsNotSentOrSaved() async {
        let fake = FakeWatchTransport(reachable: false)
        let store = InMemoryOutboxStore()
        let c = courier(fake, store: store)

        let result = await c.submit(WatchRequest(body: .command(.undo), issuedAt: t0), durable: false)

        #expect(result == .notSent(WatchDisplay.undoNeedsPhone))
        #expect(store.saves == 0)
        #expect(fake.sent.isEmpty)
    }

    @Test func aQuestionWhileUnreachableNeedsThePhone() async {
        let c = courier(FakeWatchTransport(reachable: false))
        let result = await c.submit(WatchRequest(body: .question(.trees), issuedAt: t0), durable: false)
        #expect(result == .notSent(WatchDisplay.askNeedsPhone))
    }

    @Test func undoAndNextRowAreNeverQueuedEvenIfAskedTo() async {
        let fake = FakeWatchTransport(reachable: false)
        let c = courier(fake)
        #expect(await c.submit(WatchRequest(body: .command(.undo), issuedAt: t0), durable: true) == .notSent(WatchDisplay.undoNeedsPhone))
        #expect(await c.submit(WatchRequest(body: .command(.markNextRow), issuedAt: t0), durable: true) == .notSent(WatchDisplay.askNeedsPhone))
        #expect(await c.outbox.isEmpty)
    }

    @Test func aLiveRequestWaitsForTheTapInFlight() async {
        let phone = ScriptedPhone()
        let gauge = Gauge()
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { data in
            await gauge.enter()
            try? await Task.sleep(for: .milliseconds(60))
            await gauge.leave()
            return phone.answer(data)
        }
        let c = courier(fake)
        let tap = mark(14)
        let undo = WatchRequest(body: .command(.undo), issuedAt: t0.addingTimeInterval(1))
        async let first = c.submit(tap, durable: true)
        try? await Task.sleep(for: .milliseconds(20))
        async let second = c.submit(undo, durable: false)
        _ = await (first, second)

        #expect(await gauge.most == 1)
        #expect(phone.runs == [tap.id, undo.id])
    }

    // MARK: In flight and waiting

    @Test func inFlightIsExposedAndTheWaitingCountLeavesItOut() async throws {
        let phone = ScriptedPhone()
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { data in
            try? await Task.sleep(for: .milliseconds(150))
            return phone.answer(data)
        }
        let c = courier(fake)
        let r = mark(14)
        let events = EventLog(c.updates)

        async let result = c.submit(r, durable: true)
        #expect(await events.waitFor { $0.contains(.sending(r.id)) })

        #expect(await c.inFlight.map(\.id) == [r.id])
        #expect(await c.snapshot.waiting.isEmpty)
        #expect(await c.snapshot.outbox.pending.map(\.id) == [r.id], "durable: written to the outbox first")

        guard case .replied = await result else { Issue.record("expected a reply"); return }
        #expect(await c.inFlight.isEmpty)
    }

    @Test func takingBackTheLastQueuedTap() async {
        let fake = FakeWatchTransport(reachable: false)
        let c = courier(fake)
        let a = mark(14), b = mark(15, at: 1)
        _ = await c.submit(a, durable: true)
        _ = await c.submit(b, durable: true)

        #expect(await c.takeBackLastQueued()?.id == b.id)
        #expect(await c.outbox.pending.map(\.id) == [a.id])
        #expect(await c.takeBackLastQueued()?.id == a.id)
        #expect(await c.takeBackLastQueued() == nil)
    }

    @Test func aTapInFlightCantBeTakenBack() async {
        let phone = ScriptedPhone()
        let fake = FakeWatchTransport()
        fake.defaultAnswer = .respond { data in
            try? await Task.sleep(for: .milliseconds(150))
            return phone.answer(data)
        }
        let c = courier(fake)
        let r = mark(14)
        let events = EventLog(c.updates)
        async let result = c.submit(r, durable: true)
        #expect(await events.waitFor { $0.contains(.sending(r.id)) })

        #expect(await c.takeBackLastQueued() == nil)

        _ = await result
        #expect(phone.runs == [r.id])
    }

    @Test func pastTheLimitTheOldestRowTapsAreDroppedAndCounted() async {
        let fake = FakeWatchTransport(reachable: false)
        let store = InMemoryOutboxStore(WatchOutbox(limit: 2))
        let c = courier(fake, store: store)
        let events = EventLog(c.updates)
        let clockOut = command(.clockOut, at: 0)
        _ = await c.submit(clockOut, durable: true)
        _ = await c.submit(mark(14, at: 1), durable: true)
        let result = await c.submit(mark(15, at: 2), durable: true)

        #expect(result == .queued(count: 2))
        #expect(await c.outbox.dropped == 1)
        #expect(await c.outbox.pending.first?.id == clockOut.id)
        #expect(await events.waitFor { $0.contains(.dropped(1)) })
    }

    @Test func aFlushWithNothingToSendReturns() async {
        let c = courier(FakeWatchTransport())
        await c.flush()
        #expect(await c.outbox.isEmpty)
    }

    @Test func theSameTapSubmittedTwiceIsQueuedOnce() async {
        let fake = FakeWatchTransport(reachable: false)
        let c = courier(fake)
        let r = mark(14)
        _ = await c.submit(r, durable: true)
        #expect(await c.submit(r, durable: true) == .queued(count: 1))
    }
}

// MARK: - Helpers

/// A phone that answers from a `WatchInbox`, like `WatchDesk`: a retried request gets the
/// saved reply back and doesn't run again.
final class ScriptedPhone: @unchecked Sendable {
    private let lock = NSLock()
    private var inbox = WatchInbox()
    private var _runs: [UUID] = []
    private var _answered: [UUID] = []

    /// Requests that actually ran, in order.
    var runs: [UUID] { lock.withLock { _runs } }
    /// Every request answered, retries included.
    var answered: [UUID] { lock.withLock { _answered } }

    static func request(_ data: Data) -> WatchRequest? {
        guard case .request(let r)? = try? WatchEnvelope.decode(data).message else { return nil }
        return r
    }

    func answer(_ data: Data) -> Data {
        guard let r = Self.request(data) else {
            return FakeWatchTransport.envelope(.reply(.unreadable(WatchDisplay.updatePhone)))
        }
        let reply: WatchReply = lock.withLock {
            _answered.append(r.id)
            if let saved = inbox.reply(for: r.id) { return saved }
            _runs.append(r.id)
            let reply = WatchReply(requestId: r.id, speech: "Done.", succeeded: true, lastAction: "Done")
            inbox.record(reply, at: Date())
            return reply
        }
        return FakeWatchTransport.envelope(.reply(reply))
    }
}

/// Counts how many sends are answered at once.
actor Gauge {
    private var now = 0
    private(set) var most = 0

    func enter() {
        now += 1
        most = max(most, now)
    }

    func leave() {
        now -= 1
    }
}

/// Collects a courier's events so a test can wait for one.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [CourierEventKind] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<CourierEvent>) {
        task = Task { [weak self] in
            for await event in stream {
                self?.append(CourierEventKind(event))
            }
        }
    }

    deinit { task?.cancel() }

    private func append(_ event: CourierEventKind) {
        lock.withLock { events.append(event) }
    }

    var all: [CourierEventKind] { lock.withLock { events } }

    /// Polls for up to 2 s.
    func waitFor(_ condition: ([CourierEventKind]) -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition(all) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition(all)
    }
}

/// `CourierEvent` without its payloads' replies, so tests can compare.
enum CourierEventKind: Equatable {
    case replied(UUID), queued, sending(UUID), waiting(UUID), flushed, dropped(Int)

    init(_ event: CourierEvent) {
        switch event {
        case .replied(let r, _): self = .replied(r.id)
        case .queued: self = .queued
        case .sending(let id): self = .sending(id)
        case .waiting(let id): self = .waiting(id)
        case .flushed: self = .flushed
        case .dropped(let n): self = .dropped(n)
        }
    }
}
