import Foundation
import Testing
import TimeCardCore
import TreeFarmKitTestSupport
@testable import TimeCard

// STUB: slice d replaces
@MainActor
@Suite("Phone watch bridge")
struct PhoneWatchBridgeTests {
    @Test func theBridgeKeepsItsDesk() {
        let model = AppEnvironment.makeModel(mode: .uiTest(signedIn: true), watchTransport: FakeWatchTransport())
        #expect(model.watch.status == .noWatch)
        #expect(model.watch.desk.makeState().revision == 1)
    }
}
