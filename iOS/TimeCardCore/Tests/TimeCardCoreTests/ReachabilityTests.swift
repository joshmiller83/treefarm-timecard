import Foundation
import Testing
@testable import TimeCardCore

@Suite("Network")
struct ReachabilityTests {
    @Test func reportsTheCurrentPath() async throws {
        var updates = NetworkMonitor.updates().makeAsyncIterator()
        // Whatever this machine's network is doing, the monitor answers once right away.
        let first = await updates.next()
        #expect(first != nil)
    }
}
