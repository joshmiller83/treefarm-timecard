import XCTest

/// The phone's side of the paired-simulator check (docs/watch.md 7.4): the demo farm with the
/// real watch link (`-UITestWatchLink`). A clock-in on the phone publishes the state, then
/// asks the watch to start the shift's workout (`startWatchApp`); the watch is checked by its
/// own screenshot. Skipped unless xcodebuild gets `TEST_RUNNER_WATCH_PAIRED_PHONE=1`, with the
/// paired watch simulator booted and the watch app installed.
@MainActor
final class WatchLinkUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAPhoneClockInStartsTheWatchWorkout() throws {
        guard ProcessInfo.processInfo.environment["WATCH_PAIRED_PHONE"] == "1" else {
            throw XCTSkip("Needs a paired watch simulator with the watch app installed (docs/watch.md 7.4).")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestWatchLink"]
        app.launch()
        let clockIn = app.buttons["clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 20))
        shot(app, "phone-before-clock-in")

        clockIn.tap()

        XCTAssertTrue(clockIn.waitForNonExistence(timeout: 10), "the phone never clocked in")
        shot(app, "phone-after-clock-in")
        // startWatchApp has a 10 s timeout; the watch is photographed from outside meanwhile.
        sleep(20)
        shot(app, "phone-after-launch")
    }
}
