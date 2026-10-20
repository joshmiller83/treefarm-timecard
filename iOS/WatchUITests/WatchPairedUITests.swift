import XCTest

/// The paired-simulator integration (docs/watch.md 7.4): the watch app on its real
/// WatchConnectivity link, talking to the iPhone app on the paired iPhone simulator. The phone
/// runs the demo farm with the real link (`-UITestInMemory -UITestWatchLink`), so every state
/// and sentence comes from the phone's `WatchDesk`.
///
/// Skipped unless xcodebuild gets `TEST_RUNNER_WATCH_PAIRED_PHONE=1`, with the iPhone app
/// already running on the paired phone. `TEST_RUNNER_WATCH_PAIRED_STALL=1` also runs the
/// stalled-phone check, which needs a script around it to stop and resume the phone app.
final class WatchPairedUITests: WatchUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        guard ProcessInfo.processInfo.environment["WATCH_PAIRED_PHONE"] == "1" else {
            throw XCTSkip("Needs the iPhone app running on a paired iPhone simulator (docs/watch.md 7.4).")
        }
    }

    /// The watch app with no scripted phone: WatchConnectivity and HealthKit as on a device.
    @MainActor @discardableResult
    func launchPaired() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        self.app = app
        allowHealthIfAsked()
        return app
    }

    /// The first-launch card, then the system's Health sheet and the notification question.
    @MainActor
    func allowHealthIfAsked() {
        let allow = app.buttons["onboarding.allowHealth"]
        guard allow.waitForExistence(timeout: 8) else { return }
        snapshot("paired-health-card")
        allow.tap()
        // The system's sheets: turn everything on, then allow (labels vary by release).
        for _ in 0..<6 {
            sleep(2)
            snapshot("paired-health-sheet")
            print("HEALTH SHEET:\n\(app.debugDescription)")
            let candidates = ["Turn On All", "Allow", "Review", "Next", "Done", "Allow Notifications", "OK"]
            guard let label = candidates.first(where: { app.buttons[$0].exists && app.buttons[$0].isHittable }) else {
                if primary.exists { return }
                continue
            }
            app.buttons[label].tap()
        }
    }

    // MARK: In reach

    @MainActor
    func testTheWatchDrivesThePairedPhone() {
        launchPaired()
        // The phone's state arrived (context or reply): off the clock on its demo farm.
        XCTAssertTrue(primary.waitForExistence(timeout: 60), "no state from the phone")
        waitFor(primary, label: "Clock in", timeout: 60)
        snapshot("paired-off-clock")

        primary.tap()
        waitFor(primary, labelBeginningWith: "Mark row", timeout: 20)
        snapshot("paired-now-after-clock-in")
        let firstRow = primary.label

        primary.tap()
        toast("Row", prefix: true, timeout: 20)
        snapshot("paired-now-after-mark")
        XCTAssertNotEqual(primary.label, firstRow, "the phone moved to the next row")

        app.swipeLeft()
        let today = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "iPhone:")).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        waitFor(today, label: "iPhone: in reach")
        snapshot("paired-today")
        app.swipeRight()

        app.swipeRight()
        let lunch = app.buttons["lunch"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 5))
        lunch.tap()
        waitFor(primary, label: "Back to work", timeout: 20)
        snapshot("paired-lunch")

        primary.tap()
        waitFor(primary, labelBeginningWith: "Mark row", timeout: 20)

        app.swipeRight()
        let clockOut = app.buttons["clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 5))
        clockOut.tap()
        let yes = app.buttons["Yes, clock out"]
        XCTAssertTrue(yes.waitForExistence(timeout: 5))
        snapshot("paired-confirm-clock-out")
        yes.tap()

        let done = app.buttons["summaryDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        snapshot("paired-summary")
        done.tap()
        waitFor(primary, label: "Clock in", timeout: 20)
    }

    // MARK: A stalled phone

    /// With a script around it: once the watch shows the shift, the script stops the phone app
    /// (SIGSTOP) until a tap is waiting, then resumes it. The lunch tapped meanwhile waits on
    /// the watch, then applies at the time it was tapped (the screen's "since" time), and the
    /// late reply is ignored while the retry is answered from the phone's inbox.
    @MainActor
    func testATapWaitsForAStalledPhoneThenAppliesAtItsTime() throws {
        guard ProcessInfo.processInfo.environment["WATCH_PAIRED_STALL"] == "1" else {
            throw XCTSkip("Needs the script that stops and resumes the phone app.")
        }
        launchPaired()
        XCTAssertTrue(primary.waitForExistence(timeout: 60))
        if primary.label == "Clock in" {
            primary.tap()
        }
        waitFor(primary, labelBeginningWith: "Mark row", timeout: 20)
        snapshot("stall-working")

        // The script stops the phone app now.
        sleep(25)

        app.swipeRight()
        let lunch = app.buttons["lunch"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 5))
        lunch.tap()
        // Shown at once, then waiting for the phone.
        waitFor(primary, label: "Back to work", timeout: 10)
        let badge = app.buttons["queueBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 30), "the lunch never showed as waiting")
        snapshot("stall-lunch-waiting")

        // The script resumes the phone; the minute flush of the running workout sends it.
        waitUntilGone(badge, timeout: 240)
        waitFor(primary, label: "Back to work", timeout: 20)
        snapshot("stall-lunch-applied")
    }
}

extension WatchUITestCase {
    /// A toast beginning with `text`.
    @MainActor
    func toast(_ text: String, prefix: Bool, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: timeout), "no toast", file: file, line: line)
        if prefix {
            waitFor(toast, labelBeginningWith: text, timeout: timeout, file: file, line: line)
        } else {
            waitFor(toast, label: text, timeout: timeout, file: file, line: line)
        }
    }
}
