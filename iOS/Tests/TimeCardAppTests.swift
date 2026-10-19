import Foundation
import Testing
@testable import TimeCard

@Suite("App")
struct TimeCardAppTests {
    @Test func appBundleLoads() {
        #expect(Bundle.main.bundleIdentifier?.hasSuffix(".timecard") == true)
    }
}
