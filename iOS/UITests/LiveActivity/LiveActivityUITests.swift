import XCTest

/// The lock-screen Live Activity, end to end: the app clocks in on the demo farm
/// (`-LiveActivityDemo rows`: clocked in 6 h 42 min ago, rows 5 and 6 marked, so rows 7, 8
/// and 9 are next), the phone locks, and the activity's buttons are tapped on the lock screen.
///
/// Each screenshot waits for the end state it shows (the buttons that should be there, and
/// gone the ones that shouldn't), then for the screen to stop moving.
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

        // The island while using another app: compact, then expanded with the same buttons.
        XCUIDevice.shared.press(.home)
        let row7 = springboard.buttons["Mark row 7 shaped"]
        if springboard.descendants(matching: .any)["Next, row 7"].waitForExistence(timeout: Self.redraw) {
            shot("home-compact")
        } else {
            note("No compact island", springboard.debugDescription)
        }
        expandIsland()
        if row7.waitForExistence(timeout: Self.redraw) {
            shot("home-expanded")
        } else {
            note("No expanded island", springboard.debugDescription)
        }
        // Home collapses the island without tapping anything on the home screen.
        XCUIDevice.shared.press(.home)
        _ = row7.waitForNonExistence(timeout: 10)

        lockAndWake()
        // The first time, iOS asks under the activity whether to keep showing it.
        for title in ["Allow", "Always Allow"] where springboard.buttons[title].waitForExistence(timeout: 2) {
            springboard.buttons[title].tap()
        }
        // A cold widget extension can take a while to draw the first time on a busy simulator.
        if !row7.waitForExistence(timeout: 20) {
            lockAndWake()
        }
        XCTAssertTrue(row7.waitForExistence(timeout: 20), "No row 7 button on the lock screen.\n\(springboard.debugDescription)")
        shot("lock-rows")

        // Tap Row 7: it's marked, the confirmation is the Undo button, and the rows move on to 8, 9 and 10.
        row7.tap()
        let undoRow7 = springboard.buttons["Undo: Row 7 marked"]
        XCTAssertTrue(undoRow7.waitForExistence(timeout: Self.redraw), "No Row 7 marked · Undo.\n\(springboard.debugDescription)")
        XCTAssertTrue(springboard.buttons["Mark row 10 shaped"].waitForExistence(timeout: Self.redraw), "The rows didn't move on.")
        XCTAssertTrue(row7.waitForNonExistence(timeout: Self.redraw), "Row 7 is still offered.")
        shot("lock-row7-marked")

        // Undo takes it back, and says so without offering another Undo.
        undoRow7.tap()
        XCTAssertTrue(row7.waitForExistence(timeout: Self.redraw), "Undo didn't bring row 7 back.\n\(springboard.debugDescription)")
        XCTAssertTrue(springboard.descendants(matching: .any)["Undid row 7"].waitForExistence(timeout: Self.redraw))
        XCTAssertTrue(undoRow7.waitForNonExistence(timeout: Self.redraw))

        // Break: Back to work and a full-size Undo, and no row buttons.
        springboard.buttons["Start a break"].tap()
        let back = springboard.buttons["Back to work"]
        XCTAssertTrue(back.waitForExistence(timeout: Self.redraw), "No Back to work.\n\(springboard.debugDescription)")
        XCTAssertTrue(springboard.buttons["Undo: Break started"].waitForExistence(timeout: Self.redraw), "No Undo beside Back to work.")
        XCTAssertTrue(row7.waitForNonExistence(timeout: Self.redraw))
        shot("lock-break")
        back.tap()
        if !row7.waitForExistence(timeout: Self.redraw) {
            shot("lock-back-to-work-missing")
            XCTFail("Back to work didn't bring the rows back.\n\(springboard.debugDescription)")
        }
        XCTAssertTrue(back.waitForNonExistence(timeout: Self.redraw))

        // No way to clock out from the lock screen.
        XCTAssertFalse(springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'clock out'")).firstMatch.exists)
    }

    // MARK: Helpers

    private func lockAndWake() {
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        // The screen needs a moment to lock before the next press can wake it; nothing on
        // screen says when, so this one wait is a fixed one.
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "locking")], timeout: 1.5)
        // Pressing home wakes the screen to the lock screen without unlocking.
        XCUIDevice.shared.press(.home)
    }

    /// Long-pressing the island opens the expanded view.
    private func expandIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03)).press(forDuration: 1.2)
    }

    /// Waits until two screenshots a quarter second apart match: the animation is over (a
    /// timer may still tick between them, so it gives up after a few seconds).
    private func waitForStillScreen() -> XCUIScreenshot {
        var last = XCUIScreen.main.screenshot()
        for _ in 0..<16 {
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "a quarter second")], timeout: 0.25)
            let next = XCUIScreen.main.screenshot()
            if next.pngRepresentation == last.pngRepresentation { return next }
            last = next
        }
        return last
    }

    private func shot(_ name: String) {
        let screenshot = waitForStillScreen()
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

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
