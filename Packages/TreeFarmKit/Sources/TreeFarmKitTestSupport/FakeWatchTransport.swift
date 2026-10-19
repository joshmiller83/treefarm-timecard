import Foundation
import TreeFarmKit

/// A scripted WatchConnectivity for tests, usable on either side of the link.
///
/// - **Sending** (`send`): each send takes the next scripted `Answer` (`enqueue`), else
///   `defaultAnswer`, else it is lost and times out. Answers can come at once, from a scripted
///   other side (`respond`), after a delay (later than the timeout makes a late reply, which
///   is ignored and counted in `lateReplies`), never (`lost`), or as an error. While
///   unreachable a send fails with `.notReachable` and nothing is answered.
/// - **Receiving**: `deliverMessage` hands a message to whoever reads `events` and returns
///   the reply sent through its `WatchReplySink` (counting every reply, so a test can check
///   "answered exactly once"); `deliverContext` and `deliverUserInfo` hand over state and are
///   counted until their `done` is called (`drained()`).
/// - **Recording**: every send, post, published context and complication transfer.
public final class FakeWatchTransport: WatchTransport, @unchecked Sendable {
    public indirect enum Answer: Sendable {
        /// Answer at once with this envelope.
        case reply(Data)
        /// Answer with what the other side makes of the request (a scripted phone or watch).
        case respond(@Sendable (Data) async -> Data)
        /// Answer after a delay. Longer than the send's timeout, it arrives late and is ignored.
        case after(Duration, Answer)
        /// Never answered: the send times out.
        case lost
        /// The send fails with this error.
        case fail(WatchTransportError)
    }

    public let events: AsyncStream<WatchTransportEvent>
    private let continuation: AsyncStream<WatchTransportEvent>.Continuation
    private let ledger = WatchEventLedger()
    private let lock = NSLock()

    private var reachable: Bool
    private var contentPending = false
    private var queued: [Answer] = []
    private var fallback: Answer?
    private var budget: Int
    private var _paired: Bool
    private var _installed: Bool
    private var _complicationEnabled: Bool
    private var _sent: [Data] = []
    private var _posted: [Data] = []
    private var _contexts: [Data] = []
    private var _transfers: [Data] = []
    private var _activations = 0
    private var _lateReplies = 0
    private var _repliesSent: [Data] = []

    public init(reachable: Bool = true, paired: Bool = true, installed: Bool = true,
                complicationEnabled: Bool = false, complicationTransfers: Int = 50) {
        self.reachable = reachable
        self._paired = paired
        self._installed = installed
        self._complicationEnabled = complicationEnabled
        self.budget = complicationTransfers
        (events, continuation) = AsyncStream.makeStream()
    }

    // MARK: WatchTransport

    public var isReachable: Bool { lock.withLock { reachable } }
    public var hasContentPending: Bool { lock.withLock { contentPending } }

    public func activate() {
        let (paired, installed, complications, reachable) = lock.withLock {
            _activations += 1
            return (_paired, _installed, _complicationEnabled, self.reachable)
        }
        continuation.yield(.activated(paired: paired, installed: installed, complicationEnabled: complications))
        continuation.yield(.reachabilityChanged(reachable))
    }

    public func send(_ message: Data, timeout: Duration) async throws -> Data {
        let answer: Answer = lock.withLock {
            _sent.append(message)
            guard reachable else { return .fail(.notReachable) }
            return queued.isEmpty ? (fallback ?? .lost) : queued.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { once.resume(throwing: WatchTransportError.timedOut) }
            }
            Task { await self.play(answer, for: message, once: once, timer: timer) }
        }
    }

    public func post(_ message: Data) async throws {
        try lock.withLock {
            guard reachable else { throw WatchTransportError.notReachable }
            _posted.append(message)
        }
    }

    public func publishContext(_ state: Data) throws {
        lock.withLock { _contexts.append(state) }
    }

    public func transferComplicationState(_ state: Data) -> Bool {
        lock.withLock {
            guard _complicationEnabled, budget > 0 else { return false }
            budget -= 1
            _transfers.append(state)
            return true
        }
    }

    public func drained() async {
        await ledger.drained()
    }

    // MARK: Scripting

    /// Answers for the next sends, in order.
    public func enqueue(_ answers: Answer...) {
        lock.withLock { queued.append(contentsOf: answers) }
    }

    /// The answer for sends with nothing enqueued (nil: they are lost).
    public var defaultAnswer: Answer? {
        get { lock.withLock { fallback } }
        set { lock.withLock { fallback = newValue } }
    }

    /// Changes reachability and tells the reader, as WatchConnectivity does.
    public func setReachable(_ value: Bool) {
        lock.withLock { reachable = value }
        continuation.yield(.reachabilityChanged(value))
    }

    public func setNeedsUnlock(_ value: Bool) {
        continuation.yield(.needsUnlock(value))
    }

    public func setHasContentPending(_ value: Bool) {
        lock.withLock { contentPending = value }
    }

    /// Changes what activation reports and tells the reader (the iPhone's watch-state change).
    public func setWatch(paired: Bool, installed: Bool, complicationEnabled: Bool) {
        lock.withLock {
            _paired = paired
            _installed = installed
            _complicationEnabled = complicationEnabled
        }
        continuation.yield(.activated(paired: paired, installed: installed, complicationEnabled: complicationEnabled))
    }

    public func setComplicationTransfers(_ remaining: Int) {
        lock.withLock { budget = remaining }
    }

    /// A message from the other side that waits for a reply. Returns the first reply sent
    /// through the sink, or nil if none came within `timeout`.
    public func deliverMessage(_ data: Data, timeout: Duration = .seconds(5)) async -> Data? {
        do {
            return try await withCheckedThrowingContinuation { waiter in
                let once = ResumeOnce(waiter)
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    once.resume(throwing: WatchTransportError.timedOut)
                }
                let sink = WatchReplySink { [weak self] reply in
                    self?.recordReply(reply)
                    timer.cancel()
                    once.resume(returning: reply)
                }
                self.continuation.yield(.received(data, reply: sink))
            }
        } catch {
            return nil
        }
    }

    /// A message from the other side that needs no reply.
    public func deliverPost(_ data: Data) {
        continuation.yield(.received(data, reply: nil))
    }

    /// A new application context from the other side.
    public func deliverContext(_ data: Data) {
        continuation.yield(.contextReceived(data, done: ledger.begin()))
    }

    /// A complication user-info transfer from the other side.
    public func deliverUserInfo(_ data: Data) {
        continuation.yield(.userInfoReceived(data, done: ledger.begin()))
    }

    /// Ends the event stream.
    public func finish() {
        continuation.finish()
    }

    // MARK: Records

    public var sent: [Data] { lock.withLock { _sent } }
    public var posted: [Data] { lock.withLock { _posted } }
    public var contexts: [Data] { lock.withLock { _contexts } }
    public var complicationTransfers: [Data] { lock.withLock { _transfers } }
    public var activations: Int { lock.withLock { _activations } }
    /// Replies that arrived after their send had already timed out (and were ignored).
    public var lateReplies: Int { lock.withLock { _lateReplies } }
    /// Every reply sent through a sink handed out by `deliverMessage`.
    public var repliesSent: [Data] { lock.withLock { _repliesSent } }
    /// Delivered contexts and user-info events not yet marked done.
    public var unhandledEvents: Int { ledger.unhandled }

    /// The messages in `sent`, decoded.
    public var sentMessages: [WatchMessage] { sent.compactMap { try? WatchEnvelope.decode($0).message } }
    /// The requests in `sent`, in order.
    public var sentRequests: [WatchRequest] {
        sentMessages.compactMap { if case .request(let r) = $0 { r } else { nil } }
    }
    /// The states in published contexts, in order.
    public var contextStates: [WatchState] {
        contexts.compactMap { if case .state(let s)? = try? WatchEnvelope.decode($0).message { s } else { nil } }
    }

    // MARK: Helpers

    /// An envelope for a reply, for scripting answers.
    public static func envelope(_ message: WatchMessage) -> Data {
        // Encoding our own value types can't fail.
        try! WatchEnvelope(message).data()
    }

    private func recordReply(_ reply: Data) {
        lock.withLock { _repliesSent.append(reply) }
    }

    private func play(_ answer: Answer, for message: Data, once: ResumeOnce<Data>, timer: Task<Void, Never>) async {
        switch answer {
        case .reply(let data):
            finish(once, timer) { $0.resume(returning: data) }
        case .respond(let other):
            let data = await other(message)
            finish(once, timer) { $0.resume(returning: data) }
        case .after(let delay, let inner):
            try? await Task.sleep(for: delay)
            await play(inner, for: message, once: once, timer: timer)
        case .lost:
            break
        case .fail(let error):
            finish(once, timer) { $0.resume(throwing: error) }
        }
    }

    private func finish(_ once: ResumeOnce<Data>, _ timer: Task<Void, Never>, _ body: (ResumeOnce<Data>) -> Void) {
        if once.isResumed {
            lock.withLock { _lateReplies += 1 }
            return
        }
        timer.cancel()
        body(once)
    }
}

/// The watch's outbox store, in memory.
public final class InMemoryOutboxStore: WatchOutboxStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: WatchOutbox?
    private var _saves = 0

    public init(_ outbox: WatchOutbox? = nil) {
        stored = outbox
    }

    public func load() -> WatchOutbox? {
        lock.withLock { stored }
    }

    public func save(_ outbox: WatchOutbox) {
        lock.withLock {
            stored = outbox
            _saves += 1
        }
    }

    /// How many times the outbox was saved.
    public var saves: Int { lock.withLock { _saves } }
}
