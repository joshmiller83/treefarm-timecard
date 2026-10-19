import Foundation
import Testing
import TimeCardCore
import TreeFarmKitTestSupport
@testable import TimeCard

// STUB: slice d replaces
@MainActor
@Suite("Phone watch bridge")
struct PhoneWatchBridgeTests {
    @Test func theBridgeActivatesItsTransport() {
        let fake = FakeWatchTransport()
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true), watchTransport: fake)
        #expect(fake.activations == 1)
        _ = model
    }
}
