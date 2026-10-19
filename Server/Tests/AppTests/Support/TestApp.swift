import Foundation
import NIOPosix
import Testing
import TreeFarmKit
import Vapor
import VaporTesting
@testable import App

/// A clock tests can move forward to cross expiry windows.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_760_600_000)) {
        current = start
    }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

enum TestSupport {
    /// The server runs on one event loop so SQLite gets one connection; tests do the same.
    static let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
}

/// Builds an app on a fresh in-memory database, runs `body`, and shuts it down.
func withTestApp<T>(
    clock: TestClock = TestClock(),
    adjust: (inout AppConfig) -> Void = { _ in },
    _ body: (Application, TestClock) async throws -> T
) async throws -> T {
    let app = try await Application.make(.testing, .shared(TestSupport.eventLoopGroup))
    var config = AppConfig.testing(now: { clock.now })
    adjust(&config)
    let result: T
    do {
        try await configure(app, config: config)
        result = try await body(app, clock)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
    return result
}
