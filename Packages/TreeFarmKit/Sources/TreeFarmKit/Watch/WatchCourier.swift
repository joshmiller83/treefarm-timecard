import Foundation

// The watch's courier (docs/watch.md 1.4): it owns the persistent `WatchOutbox`, saved through a
// `WatchOutboxStore` after every change, and talks to the phone one request at a time, oldest
// first, waiting for each reply.
//
// - **Durable** requests (every command except `.undo`) are written to the outbox first, then
//   sent. A reply removes one, whatever it said, unless the phone asks to `keepQueued`. A lost
//   or late reply leaves it queued for a retry, which the phone's `WatchInbox` makes harmless.
// - **Live-only** requests (`.undo`, questions, `.refresh`) are sent directly and never stored.
//   With the phone away they come back `.notSent` with the sentence to show.
//
// One loop sends the outbox. Live requests share its lane, so only one request is ever in
// flight, and a live `undo` can't overtake the tap it means to undo.

/// What became of one submitted request.
public enum CourierResult: Equatable, Sendable {
    /// The phone answered (it may have refused: see `WatchReply.succeeded`, and
    /// `WatchReply.keepQueued` for "try again later", which leaves the tap queued).
    case replied(WatchReply)
    /// Saved on the watch; `count` taps now wait (not counting one in flight).
    case queued(count: Int)
    /// Live-only and the phone is away: nothing was stored. The sentence says so.
    case notSent(String)
}

/// What the courier tells the model as it works. Read by one loop.
public enum CourierEvent: Sendable {
    /// The phone answered a request (sent now, or flushed from the outbox).
    case replied(WatchRequest, WatchReply)
    /// A request was written to the outbox.
    case queued
    /// A request is now in flight: it no longer counts as waiting.
    case sending(UUID)
    /// No reply within the timeout: the request stays queued ("Waiting for phone…").
    case waiting(UUID)
    /// The send loop stopped: the outbox is empty, or the phone can't be reached right now.
    case flushed
    /// Row taps dropped past the outbox limit (the total so far).
    case dropped(Int)
}

/// The outbox and what's in flight, read together.
public struct CourierSnapshot: Equatable, Sendable {
    /// Every durable request not yet answered, oldest first, including the one in flight.
    public var outbox: WatchOutbox
    /// Sent and not yet answered.
    public var inFlight: [WatchRequest]

    public init(outbox: WatchOutbox = WatchOutbox(), inFlight: [WatchRequest] = []) {
        self.outbox = outbox
        self.inFlight = inFlight
    }

    /// Outbox items not in flight: what the badge and "2 waiting" count.
    public var waiting: [WatchRequest] {
        let sending = Set(inFlight.map(\.id))
        return outbox.pending.filter { !sending.contains($0.id) }
    }
}

public actor WatchCourier {
    private let transport: any WatchTransport
    private let store: any WatchOutboxStore
    private let replyTimeout: Duration
    private let now: @Sendable () -> Date
    private var box: WatchOutbox
    private var sending: [WatchRequest] = []
    private let continuation: AsyncStream<CourierEvent>.Continuation
    public nonisolated let updates: AsyncStream<CourierEvent>

    /// Submitters waiting for their durable request's answer while the loop runs.
    private var waiters: [UUID: [CheckedContinuation<CourierResult, Never>]] = [:]
    private var loop: Task<Void, Never>?
    /// One request on the wire at a time, loop or live.
    private var laneBusy = false
    private var lane: [CheckedContinuation<Void, Never>] = []

    public init(transport: any WatchTransport, store: any WatchOutboxStore,
                replyTimeout: Duration = .seconds(4), now: @escaping @Sendable () -> Date) {
        self.transport = transport
        self.store = store
        self.replyTimeout = replyTimeout
        self.now = now
        self.box = store.load() ?? WatchOutbox()
        (updates, continuation) = AsyncStream.makeStream()
    }

    public var outbox: WatchOutbox { box }
    public var inFlight: [WatchRequest] { sending }
    public var snapshot: CourierSnapshot { CourierSnapshot(outbox: box, inFlight: sending) }

    private var waitingCount: Int { snapshot.waiting.count }

    // MARK: Submitting

    public func submit(_ request: WatchRequest, durable: Bool) async -> CourierResult {
        guard durable, WatchOutbox.canQueue(request) else { return await sendLive(request) }

        if !box.pending.contains(where: { $0.id == request.id }) {
            let dropped = box.dropped
            let kept = box.add(request)
            store.save(box)
            continuation.yield(.queued)
            if box.dropped > dropped { continuation.yield(.dropped(box.dropped)) }
            guard kept else { return .queued(count: waitingCount) }
        }
        guard transport.isReachable else { return .queued(count: waitingCount) }

        return await withCheckedContinuation { waiter in
            waiters[request.id, default: []].append(waiter)
            startLoop()
        }
    }

    /// Sends what waits, oldest first, and returns once the loop stops: everything was
    /// answered, or the phone can't be reached right now.
    public func flush() async {
        if loop == nil {
            guard !box.isEmpty, transport.isReachable else { return }
            startLoop()
        }
        await loop?.value
    }

    /// The phone lists these requests as applied (a reply may have been lost on the way back).
    public func acknowledge(_ state: WatchState) {
        clear(state.appliedRequestIds)
    }

    /// Takes back the newest waiting tap (the watch's Undo while taps wait). Never one in flight.
    public func takeBackLastQueued() -> WatchRequest? {
        guard let last = box.pending.last, !sending.contains(where: { $0.id == last.id }) else { return nil }
        box.removeLast()
        store.save(box)
        resolve(last.id, .notSent(WatchDisplay.tookBack(last)))
        return last
    }

    // MARK: The send loop

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { await self.run() }
    }

    private func run() async {
        while let next = box.pending.first, transport.isReachable {
            await acquireLane()
            // Acknowledged or taken back while waiting for the lane: look again.
            guard let current = box.pending.first, current.id == next.id else {
                releaseLane()
                continue
            }
            sending = [current]
            continuation.yield(.sending(current.id))
            let answer = await exchange(current)
            sending = []
            releaseLane()

            switch answer {
            case .reply(let reply) where reply.keepQueued:
                // "Couldn't run this now": it stays, and so does everything after it.
                continuation.yield(.replied(current, reply))
                resolve(current.id, .replied(reply))
                return finishLoop()
            case .reply(let reply):
                box.delivered(current.id)
                if let state = reply.state { box.acknowledge(state.appliedRequestIds) }
                store.save(box)
                continuation.yield(.replied(current, reply))
                resolve(current.id, .replied(reply))
            case .failed(.timedOut):
                continuation.yield(.waiting(current.id))
                return finishLoop()
            case .failed:
                return finishLoop()
            }
        }
        finishLoop()
    }

    /// Answers every submitter still waiting (their taps stay queued) and says the loop stopped.
    private func finishLoop() {
        loop = nil
        let count = waitingCount
        let left = waiters
        waiters = [:]
        for waiter in left.values.flatMap({ $0 }) { waiter.resume(returning: .queued(count: count)) }
        continuation.yield(.flushed)
    }

    // MARK: Live requests

    private func sendLive(_ request: WatchRequest) async -> CourierResult {
        guard transport.isReachable else { return .notSent(Self.needsPhone(request)) }
        await acquireLane()
        let answer = await exchange(request)
        releaseLane()
        switch answer {
        case .reply(let reply):
            if let state = reply.state { clear(state.appliedRequestIds) }
            continuation.yield(.replied(request, reply))
            return .replied(reply)
        case .failed:
            return .notSent(Self.needsPhone(request))
        }
    }

    /// What to say when a live request can't reach the phone.
    static func needsPhone(_ request: WatchRequest) -> String {
        if case .undo? = request.command { return WatchDisplay.undoNeedsPhone }
        return WatchDisplay.askNeedsPhone
    }

    // MARK: Helpers

    private enum Answer {
        case reply(WatchReply)
        case failed(WatchTransportError)
    }

    /// One request and its reply. A reply the watch can't read (from a newer iPhone app) keeps
    /// the request queued and says to update the watch.
    private func exchange(_ request: WatchRequest) async -> Answer {
        let message: Data
        do {
            message = try WatchEnvelope(.request(request)).data()
        } catch {
            return .failed(.failed("\(error)"))
        }
        do {
            let data = try await transport.send(message, timeout: replyTimeout)
            guard case .reply(let reply)? = try? WatchEnvelope.decode(data).message else {
                return .reply(.unreadable(WatchDisplay.updateWatch))
            }
            return .reply(reply)
        } catch let error as WatchTransportError {
            return .failed(error)
        } catch {
            return .failed(.failed("\(error)"))
        }
    }

    private func clear(_ ids: [UUID]) {
        let before = box.count
        box.acknowledge(ids)
        guard box.count != before else { return }
        store.save(box)
    }

    private func resolve(_ id: UUID, _ result: CourierResult) {
        guard let list = waiters.removeValue(forKey: id) else { return }
        for waiter in list { waiter.resume(returning: result) }
    }

    private func acquireLane() async {
        guard laneBusy else {
            laneBusy = true
            return
        }
        await withCheckedContinuation { lane.append($0) }
    }

    /// Hands the lane to the next in line, or frees it.
    private func releaseLane() {
        if lane.isEmpty {
            laneBusy = false
        } else {
            lane.removeFirst().resume()
        }
    }
}
