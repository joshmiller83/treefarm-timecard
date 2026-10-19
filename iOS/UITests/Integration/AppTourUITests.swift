import XCTest

/// The whole app on one working day: every tab, the links between them and Settings, on the
/// demo farm (`-UITestInMemory -UITestClock working`: a shift on the clock for three hours
/// with rows marked, and three earlier days this week).
///
/// Each step keeps a screenshot as a test attachment. Set `TOUR_SHOTS_DIR`
/// (`TEST_RUNNER_TOUR_SHOTS_DIR` on the xcodebuild command line) to also write them there as
/// PNGs, named with `TOUR_SUFFIX` ("dark", "ax3") when it's set, and `TOUR_TEXT_SIZE` to run
/// at a Dynamic Type size (a UIContentSizeCategory name such as
/// UICTContentSizeCategoryAccessibilityL).
@MainActor
final class AppTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testATourOfEveryTabOnAWorkingDay() {
        app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestClock", "working"]
        if let size = ProcessInfo.processInfo.environment["TOUR_TEXT_SIZE"] {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()

        // Clock: on the clock, with the lock screen's row buttons.
        XCTAssertTrue(element("big-timer").waitForExistence(timeout: 15), "No timer on the Clock tab.")
        shot("1-clock")
        // The row buttons sit in a lazy grid: at the largest text sizes they're made once in view.
        let nextRow = element("next-row-0")
        for _ in 0..<4 where !nextRow.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(nextRow.exists, "No next-row buttons.")
        app.swipeUp()
        shot("1-clock-lower")

        // "Mark trees" on the trees card opens the map.
        let markTrees = app.buttons["Mark trees"]
        for _ in 0..<4 where !(markTrees.exists && markTrees.isHittable) { app.swipeUp() }
        XCTAssertTrue(markTrees.exists, "No Mark trees button on the Clock tab.")
        markTrees.tap()
        XCTAssertTrue(selected("Trees"), "Mark trees didn't open the Trees tab.")
        XCTAssertTrue(element("tree-map").waitForExistence(timeout: 15), "No map on the Trees tab.")
        shot("2-trees")

        tab("Log")
        XCTAssertTrue(element("log-shift-card").waitForExistence(timeout: 10), "No shifts in the Log.")
        shot("3-log")

        tab("Report")
        XCTAssertTrue(element("export-pdf").waitForExistence(timeout: 10), "No Export PDF on the Report.")
        shot("4-report")

        tab("Team")
        XCTAssertTrue(element("team-invite").waitForExistence(timeout: 10), "No crew on the Team tab.")
        shot("5-team")

        tab("Clock")
        let gear = app.buttons["settings-button"]
        for _ in 0..<4 where !(gear.exists && gear.isHittable) { app.swipeDown() }
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        XCTAssertTrue(app.textFields["profile-job"].waitForExistence(timeout: 10), "Settings didn't open.")
        shot("6-settings")
    }

    // MARK: Helpers

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No \(name) tab.")
        button.tap()
        XCTAssertTrue(selected(name), "The \(name) tab didn't open.")
    }

    private func selected(_ name: String) -> Bool {
        let button = app.tabBars.buttons[name]
        let isSelected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
        return XCTWaiter().wait(for: [isSelected], timeout: 10) == .completed
    }

    /// Lets the screen settle (a toast or a tab switch animating), then keeps a screenshot.
    private func shot(_ name: String) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 1)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let environment = ProcessInfo.processInfo.environment
        if let dir = environment["TOUR_SHOTS_DIR"] {
            let suffix = environment["TOUR_SUFFIX"].map { "-\($0)" } ?? ""
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name)\(suffix).png"))
        }
    }
}
