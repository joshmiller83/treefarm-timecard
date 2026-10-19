import Foundation

// STUB: slice a replaces
//
// The watch's courier: owns the persistent `WatchOutbox` (saved through a `WatchOutboxStore`
// after every change), sends one request at a time, oldest first, and waits for each reply.
// See docs/watch.md 1.4. Slice 0 fixed these signatures; slice a writes the real thing,
// test-first, in this file (with WatchCourierTests).

/// What became of one submitted request.
public enum CourierResult: Equatable, Sendable {
    /// The phone answered (it may have refused: see `WatchReply.succeeded`).
    case replied(WatchReply)
    /// Saved on the watch; `count` taps now wait (not counting one in flight).
    case queued(count: Int)
    /// Live-only and the phone is away: nothing was stored. The sentence says so.
    case notSent(String)
}

/// What the courier tells the model as it works.
public enum CourierEvent: Sendable {
    case replied(WatchRequest, WatchReply)
    case queued
    /// No reply within the timeout: the request stays queued ("Waiting for phone…").
    case waiting(UUID)
    case flushed
    /// Row taps dropped past the outbox limit (the total so far).
    case dropped(Int)
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

    public func submit(_ request: WatchRequest, durable: Bool) async -> CourierResult {
        guard durable else { return .notSent(WatchDisplay.askNeedsPhone) }
        box.add(request)
        store.save(box)
        continuation.yield(.queued)
        return .queued(count: box.count)
    }

    public func flush() async {}

    public func acknowledge(_ state: WatchState) {
        box.acknowledge(state.appliedRequestIds)
        store.save(box)
    }

    public func takeBackLastQueued() -> WatchRequest? {
        let last = box.removeLast()
        store.save(box)
        return last
    }
}
