import Foundation
import TreeFarmKit
import WatchConnectivity

/// The real `WatchTransport`: WatchConnectivity's default session, compiled into both apps.
///
/// WatchConnectivity has no `Sendable` annotations and calls its delegate on its own serial
/// queue. A closure written in `@MainActor` code is inferred `@MainActor` and traps at runtime
/// when WatchConnectivity calls it, and the compiler doesn't warn. So every delegate method
/// here is `nonisolated`, and all it does is yield into one `AsyncStream`, read by one
/// main-actor loop on each side. That keeps WatchConnectivity's order; no callback gets its own
/// `Task { @MainActor in }`.
///
/// Its only shared mutable state is the stream's continuation and the event ledger behind
/// `drained()`.
///
/// Every `Data` here is a `WatchEnvelope`. The application context and the complication user
/// info carry a `.state` envelope under `contextKey`, with `versionKey` beside it.
final class WCSessionTransport: NSObject, WCSessionDelegate, WatchTransport, @unchecked Sendable {
    static let contextKey = "tc.state"
    static let versionKey = "v"

    let events: AsyncStream<WatchTransportEvent>
    private let continuation: AsyncStream<WatchTransportEvent>.Continuation
    private let session: WCSession?
    private let ledger = WatchEventLedger()

    init(session: WCSession? = WCSession.isSupported() ? .default : nil) {
        self.session = session
        (events, continuation) = AsyncStream.makeStream()
        super.init()
    }

    // MARK: WatchTransport

    var isReachable: Bool {
        guard let session, session.activationState == .activated else { return false }
        return session.isReachable
    }

    var hasContentPending: Bool {
        session?.hasContentPending ?? false
    }

    func activate() {
        guard let session else {
            continuation.yield(.activated(paired: false, installed: false, complicationEnabled: false))
            return
        }
        session.delegate = self
        if session.activationState == .activated {
            // Already active (a second model in the same process): say so again.
            announce(session)
        } else {
            session.activate()
        }
    }

    func send(_ message: Data, timeout: Duration) async throws -> Data {
        guard let session, session.activationState == .activated else { throw WatchTransportError.notActivated }
        guard session.isReachable else { throw WatchTransportError.notReachable }
        return try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Data, any Error>) in
            let once = ResumeOnce(waiter)
            let timer = Task {
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { once.resume(throwing: WatchTransportError.timedOut) }
            }
            session.sendMessageData(message, replyHandler: { reply in
                timer.cancel()
                once.resume(returning: reply)
            }, errorHandler: { error in
                timer.cancel()
                once.resume(throwing: Self.transportError(error))
            })
        }
    }

    func post(_ message: Data) async throws {
        guard let session, session.activationState == .activated else { throw WatchTransportError.notActivated }
        guard session.isReachable else { throw WatchTransportError.notReachable }
        // No reply handler: the other side gets `session(_:didReceiveMessageData:)`. A failure
        // after this returns is lost; what's posted (a state, a summary) is sent again later.
        session.sendMessageData(message, replyHandler: nil, errorHandler: nil)
    }

    func publishContext(_ state: Data) throws {
        guard let session, session.activationState == .activated else { throw WatchTransportError.notActivated }
        try session.updateApplicationContext([Self.contextKey: state, Self.versionKey: WatchWire.version])
    }

    func transferComplicationState(_ state: Data) -> Bool {
        #if os(iOS)
        guard let session, session.activationState == .activated, session.isComplicationEnabled,
              session.remainingComplicationUserInfoTransfers > 0 else { return false }
        session.transferCurrentComplicationUserInfo([Self.contextKey: state, Self.versionKey: WatchWire.version])
        return true
        #else
        return false
        #endif
    }

    func drained() async {
        await ledger.drained()
    }

    // MARK: WCSessionDelegate (nonisolated: WatchConnectivity's own queue)

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        guard activationState == .activated else { return }
        announce(session)
        // A context that arrived while the app wasn't running.
        if let data = session.receivedApplicationContext[Self.contextKey] as? Data {
            continuation.yield(.contextReceived(data, done: ledger.begin()))
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        continuation.yield(.reachabilityChanged(session.isReachable))
        #if os(watchOS)
        continuation.yield(.needsUnlock(session.iOSDeviceNeedsUnlockAfterRebootForReachability))
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        continuation.yield(.received(messageData, reply: nil))
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        let box = ReplyBox(replyHandler)
        continuation.yield(.received(messageData, reply: WatchReplySink { box.send($0) }))
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.contextKey] as? Data else { return }
        continuation.yield(.contextReceived(data, done: ledger.begin()))
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[Self.contextKey] as? Data else { return }
        continuation.yield(.userInfoReceived(data, done: ledger.begin()))
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The person switched to another watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// Paired, installed or complication state changed on the watch side.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        announce(session)
    }
    #endif

    // MARK: Helpers

    private nonisolated func announce(_ session: WCSession) {
        #if os(iOS)
        continuation.yield(.activated(paired: session.isPaired, installed: session.isWatchAppInstalled,
                                      complicationEnabled: session.isComplicationEnabled))
        #else
        continuation.yield(.activated(paired: true, installed: session.isCompanionAppInstalled, complicationEnabled: false))
        continuation.yield(.needsUnlock(session.iOSDeviceNeedsUnlockAfterRebootForReachability))
        #endif
        continuation.yield(.reachabilityChanged(session.isReachable))
    }

    static func transportError(_ error: any Error) -> WatchTransportError {
        guard let wc = error as? WCError else { return .failed(error.localizedDescription) }
        switch wc.code {
        case .notReachable, .deviceNotPaired, .watchAppNotInstalled, .companionAppNotInstalled: return .notReachable
        case .messageReplyTimedOut: return .timedOut
        case .sessionNotActivated, .sessionInactive: return .notActivated
        default: return .failed(wc.localizedDescription)
        }
    }

    /// Holds WatchConnectivity's reply handler, which isn't `Sendable`, so it can travel in a
    /// `WatchReplySink`. It is called once, by the loop that handles the message.
    private final class ReplyBox: @unchecked Sendable {
        private let handler: (Data) -> Void
        init(_ handler: @escaping (Data) -> Void) { self.handler = handler }
        func send(_ data: Data) { handler(data) }
    }
}
