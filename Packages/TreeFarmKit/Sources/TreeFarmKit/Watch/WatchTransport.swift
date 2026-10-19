import Foundation

// The seam between the watch link's logic and WatchConnectivity. `WCSessionTransport`
// (iOS/WatchLink, compiled into both apps) is the real one; `FakeWatchTransport`
// (TreeFarmKitTestSupport) scripts it for tests.
//
// Every `Data` that crosses it is one `WatchEnvelope`: requests and replies, the state in the
// application context, and the state in a complication user-info transfer.
//
// WatchConnectivity calls back on its own serial queues. Each side turns those callbacks into
// one `AsyncStream` of events, read by one main-actor loop, so WatchConnectivity's order is
// kept and no callback is ever assumed to run on the main actor.

public protocol WatchTransport: Sendable {
    /// The other app can be messaged right now.
    var isReachable: Bool { get }
    /// WatchConnectivity still holds deliveries for this app (a background wake waits for them).
    var hasContentPending: Bool { get }
    /// Everything that arrives, in WatchConnectivity's order. Read by one loop only.
    var events: AsyncStream<WatchTransportEvent> { get }
    func activate()
    /// Sends a `.request` envelope and returns the `.reply` envelope. Throws
    /// `WatchTransportError.timedOut` after `timeout`; a reply that arrives later is ignored
    /// (`ResumeOnce`), and the request stays queued for a retry.
    func send(_ message: Data, timeout: Duration) async throws -> Data
    /// Sends an envelope that needs no reply (a `.state` push, a `.workoutSummary`).
    func post(_ message: Data) async throws
    /// Replaces the application context with this `.state` envelope.
    func publishContext(_ state: Data) throws
    /// Sends this `.state` envelope as the current complication user info. iOS only, and only
    /// while the complication is on a face with transfers left today; false otherwise.
    func transferComplicationState(_ state: Data) -> Bool
    /// Returns once every context and user-info event delivered so far has been marked done.
    func drained() async
}

public enum WatchTransportEvent: Sendable {
    /// Activation finished, or (on the iPhone) the watch's pairing or install state changed.
    /// On the watch `paired` is always true and `installed` means the iPhone app is installed.
    case activated(paired: Bool, installed: Bool, complicationEnabled: Bool)
    case reachabilityChanged(Bool)
    /// The watch can't reach the iPhone until it is unlocked once after a restart.
    case needsUnlock(Bool)
    /// A message. `reply` is set when the sender waits for an answer, which must be sent
    /// exactly once.
    case received(Data, reply: WatchReplySink?)
    /// A new application context. Call `done` once it has been handled.
    case contextReceived(Data, done: WatchEventDone)
    /// A complication user-info transfer (`transferCurrentComplicationUserInfo`), handled
    /// exactly like a context. Call `done` once it has been handled.
    case userInfoReceived(Data, done: WatchEventDone)
}

/// Answers one received message. Holds WatchConnectivity's reply handler.
public struct WatchReplySink: Sendable {
    public let send: @Sendable (Data) -> Void

    public init(send: @escaping @Sendable (Data) -> Void) {
        self.send = send
    }
}

/// Marks a delivered context or user-info event as handled, for `WatchTransport.drained()`.
public struct WatchEventDone: Sendable {
    public let call: @Sendable () -> Void

    public init(_ call: @escaping @Sendable () -> Void) {
        self.call = call
    }

    public func callAsFunction() {
        call()
    }
}

public enum WatchTransportError: Error, Equatable, Sendable {
    /// The session hasn't finished activating (or WatchConnectivity isn't supported here).
    case notActivated
    /// The other app can't be messaged right now.
    case notReachable
    /// No reply in time. Nobody knows WatchConnectivity's own reply timeout, so the courier
    /// sets its own and keeps the request queued.
    case timedOut
    case failed(String)
}

/// Where the watch's outbox is kept between launches (`FileOutboxStore` in the App Group).
public protocol WatchOutboxStore: Sendable {
    func load() -> WatchOutbox?
    func save(_ outbox: WatchOutbox)
}

/// Counts delivered context and user-info events that haven't been handled yet, so a
/// background wake can wait until they all have (`WatchTransport.drained()`). Each transport
/// keeps one.
public final class WatchEventLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var open = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Counts one more delivered event; the returned `done` marks it handled (once, however
    /// often it is called).
    public func begin() -> WatchEventDone {
        lock.withLock { open += 1 }
        let once = Once()
        return WatchEventDone { [weak self] in
            if once.first() { self?.end() }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false

        func first() -> Bool {
            lock.withLock {
                defer { used = true }
                return !used
            }
        }
    }

    public var unhandled: Int {
        lock.withLock { open }
    }

    public func drained() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                if open == 0 { return true }
                waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    private func end() {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            open = max(0, open - 1)
            guard open == 0 else { return [] }
            defer { waiters = [] }
            return waiters
        }
        ready.forEach { $0.resume() }
    }
}

/// A transport with nothing on the other end: never reachable, and every send fails with
/// `.notReachable`. The iPhone app uses it in UI-test mode and while hosting unit tests, so no
/// test touches the real WCSession; previews can use it too.
public final class DisconnectedWatchTransport: WatchTransport {
    public let events: AsyncStream<WatchTransportEvent>
    private let continuation: AsyncStream<WatchTransportEvent>.Continuation

    public init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    public var isReachable: Bool { false }
    public var hasContentPending: Bool { false }

    public func activate() {
        continuation.yield(.activated(paired: false, installed: false, complicationEnabled: false))
    }

    public func send(_ message: Data, timeout: Duration) async throws -> Data {
        throw WatchTransportError.notReachable
    }

    public func post(_ message: Data) async throws {
        throw WatchTransportError.notReachable
    }

    public func publishContext(_ state: Data) throws {}

    public func transferComplicationState(_ state: Data) -> Bool { false }

    public func drained() async {}
}
