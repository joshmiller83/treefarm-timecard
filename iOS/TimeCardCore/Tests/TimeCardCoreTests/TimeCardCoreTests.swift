import Foundation
import Testing
@testable import TimeCardCore

@Suite("TimeCardCore")
struct TimeCardCoreTests {
    @Test func defaultServerIsTheFarmServer() {
        #expect(TimeCardCore.defaultServerURL.absoluteString == "https://timecard.joshnliz.com")
    }

    @Test func reExportsTheSharedModel() {
        // The app imports only TimeCardCore and still sees TreeFarmKit's types.
        #expect(Limits.pushBatch == 200)
    }
}
