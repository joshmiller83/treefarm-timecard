import XCTest

// STUB: slice a replaces
//
// Watch simulator UI tests (docs/watch.md 7.3): `-watchDemo` swaps in a scripted in-process
// phone, `-watchPhoneAway` starts unreachable.
final class WatchLaunchUITests: XCTestCase {
    @MainActor
    func testTheAppLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-watchDemo"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }
}
