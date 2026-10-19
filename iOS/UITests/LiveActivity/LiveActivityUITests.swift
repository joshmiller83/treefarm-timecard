import XCTest

/// The lock-screen Live Activity, end to end: the app clocks in on the demo farm
/// (`-LiveActivityDemo rows`: clocked in 6 h 42 min ago, rows 5 and 6 marked, so rows 7, 8
/// and 9 are next), the phone locks, and the activity's buttons are tapped on the lock screen.
///
/// Screenshots go to iOS/build/LiveActivityScreens (git-ignored), named with
/// `TEST_RUNNER_LIVE_SHOT_SUFFIX` (say "dark") when it's set.
@MainActor
final class LiveActivityUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// How long the lock screen may take to show an update. A phone takes well under a
    /// second; a busy simulator on an Intel Mac has taken more than ten.
    private static let redraw: TimeInterval = 30

    override func setUp() {
        continueAfterFailure = false
    }

    func testLockScreenButtonsMarkARowTakeABreakAndUndo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-LiveActivityDemo", "rows"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Clock"].waitForExistence(timeout: Self.redraw))

        // The island while using another app.
        XCUIDevice.shared.press(.home)
        let row7 = springboard.buttons["Mark row 7 shaped"]
        // The island draws once the extension has rendered the activity.
        sleep(6)
        shot("home-compact")
        expandIsland()
        shot("home-expanded")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()

        lockAndWake()
        // The first time, iOS asks under the activity whether to keep showing it.
        for title in ["Allow", "Always Allow"] where springboard.buttons[title].waitForExistence(timeout: 2) {
            springboard.buttons[title].tap()
            sleep(1)
        }
        // A cold widget extension can take a while to draw the first time on a busy simulator.
        if !row7.waitForExistence(timeout: 20) {
            lockAndWake()
        }
        XCTAssertTrue(row7.waitForExistence(timeout: 20), "No row 7 button on the lock screen.\n\(springboard.debugDescription)")
        shot("lock-rows")

        // Tap Row 7: it's marked, Undo appears, and the buttons move on to 8, 9 and 10.
        row7.tap()
        XCTAssertTrue(springboard.buttons["Mark row 10 shaped"].waitForExistence(timeout: Self.redraw), "The rows didn't move on.\n\(springboard.debugDescription)")
        XCTAssertTrue(springboard.staticTexts["Row 7 marked"].exists)
        shot("lock-row7-marked")

        // Undo takes it back.
        let undo = springboard.buttons["Undo: Row 7 marked"]
        XCTAssertTrue(undo.exists)
        undo.tap()
        XCTAssertTrue(row7.waitForExistence(timeout: Self.redraw), "Undo didn't bring row 7 back.\n\(springboard.debugDescription)")
        XCTAssertTrue(springboard.staticTexts["Undid row 7"].exists)

        // Break: one big Back to work, and no row buttons.
        springboard.buttons["Start a break"].tap()
        let back = springboard.buttons["Back to work"]
        XCTAssertTrue(back.waitForExistence(timeout: Self.redraw), "No Back to work.\n\(springboard.debugDescription)")
        XCTAssertFalse(row7.exists)
        shot("lock-break")
        back.tap()
        if !row7.waitForExistence(timeout: Self.redraw) {
            shot("lock-back-to-work-missing")
            XCTFail("Back to work didn't bring the rows back.\n\(springboard.debugDescription)")
        }

        // No way to clock out from the lock screen.
        XCTAssertFalse(springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'clock out'")).firstMatch.exists)
    }

    // MARK: Helpers

    private func lockAndWake() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        // Pressing home wakes the screen to the lock screen without unlocking.
        XCUIDevice.shared.press(.home)
        sleep(2)
    }

    /// Long-pressing the island opens the expanded view.
    private func expandIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
        sleep(2)
    }

    private func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let suffix = ProcessInfo.processInfo.environment["LIVE_SHOT_SUFFIX"].map { "-\($0)" } ?? ""
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/LiveActivityScreens")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent("\(name)\(suffix).png"))
    }
}
