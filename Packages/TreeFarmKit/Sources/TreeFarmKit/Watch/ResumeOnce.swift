import Foundation

/// A continuation that can be resumed from several racing places, of which only the first
/// counts: a WatchConnectivity reply handler, its error handler and a timeout task. Resuming a
/// `CheckedContinuation` twice is a fatal error, and a reply can arrive after the timeout.
///
/// One per send. The continuation is taken out under a lock, so the first caller wins and
/// later callers do nothing.
public final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    // NSLock rather than Mutex: TreeFarmKit still builds for macOS 14, iOS 17 and Linux.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?

    public init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    /// True once someone has resumed it.
    public var isResumed: Bool {
        lock.withLock { continuation == nil }
    }

    public func resume(returning value: T) {
        take()?.resume(returning: value)
    }

    public func resume(throwing error: any Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<T, any Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}
