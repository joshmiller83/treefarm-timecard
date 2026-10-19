import Foundation
import os

/// Where the bearer token lives between launches.
public protocol TokenStore: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// Keeps the token in memory only: tests and UI-test runs.
public final class InMemoryTokenStore: TokenStore {
    private let token: OSAllocatedUnfairLock<String?>

    public init(token: String? = nil) {
        self.token = OSAllocatedUnfairLock(initialState: token)
    }

    public func read() throws -> String? { token.withLock { $0 } }
    public func save(_ token: String) throws { self.token.withLock { $0 = token } }
    public func clear() throws { token.withLock { $0 = nil } }
}
