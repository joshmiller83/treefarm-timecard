import XCTest

/// The flows in docs/watch.md 7.3, against the scripted phone.
final class WatchFlowUITests: WatchUITestCase {
    // MARK: Clock in, mark, the crown, Double Tap

    @MainActor
    func testClockInThenMarkTheRowShown() {
        launch()
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        waitFor(primary, label: "Clock in")

        primary.tap()

        waitFor(primary, label: "Mark row 14 in block 2 shaped")
        XCTAssertTrue(app.staticTexts["shiftTimer"].exists)
        snapshot("now-after-clock-in")

        primary.tap()

        toast("Row 14 marked")
        waitFor(primary, label: "Mark row 15 in block 2 shaped")
        snapshot("now-after-mark")
    }

    @MainActor
    func testTheCrownPicksALaterRow() {
        launch("-watchDemoWorking")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        waitFor(primary, labelBeginningWith: "Mark row 17")

        // A full turn reaches the last of the three rows (the selection stops there). The
        // button marks the row the crown chose, so tap before the 6 s snap-back. (Its
        // accessibility label can lag a crown turn in the simulator, so the phone's answer is
        // what's checked.)
        let button = primary.firstMatch
        XCUIDevice.shared.rotateDigitalCrown(delta: 1.5)
        button.tap()

        toast("Row 19 marked")
        snapshot("now-after-crown-mark")
        // The phone moves on from the row marked, as the lock screen's row buttons do.
        waitFor(primary, label: "Mark row 20 in block 2 shaped")
    }

    @MainActor
    func testDoubleTapMarksTheRowShown() throws {
        guard XCUIDevice.shared.supportsHandGestures else {
            throw XCTSkip("This simulator has no hand gestures; Double Tap is checked on the device (docs/watch.md 7.5).")
        }
        launch("-watchDemoWorking")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        waitFor(primary, labelBeginningWith: "Mark row 17")

        XCUIDevice.shared.perform(handGesture: .doubleTap)

        toast("Row 17 marked")
        waitFor(primary, labelBeginningWith: "Mark row 18")
    }

    @MainActor
    func testUndoClockInGoesBackOffTheClock() {
        launch()
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        primary.tap()
        let undo = app.buttons["undoClockIn"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        snapshot("now-undo-clock-in")

        undo.tap()

        waitFor(primary, label: "Clock in")
        snapshot("off-clock-after-undo")
    }

    // MARK: Lunch, back to work, clock out

    @MainActor
    func testLunchBackToWorkThenClockOutWithTheSummary() {
        launch("-watchDemoWorking")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))

        app.swipeRight()
        let lunch = app.buttons["lunch"]
        XCTAssertTrue(lunch.waitForExistence(timeout: 5))
        snapshot("controls")
        lunch.tap()

        waitFor(primary, label: "Back to work")
        snapshot("now-lunch")
        primary.tap()
        waitFor(primary, labelBeginningWith: "Mark row")

        app.swipeRight()
        let clockOut = app.buttons["clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 5))
        clockOut.tap()

        let yes = app.buttons["Yes, clock out"]
        XCTAssertTrue(yes.waitForExistence(timeout: 5))
        snapshot("confirm-clock-out")
        yes.tap()

        let done = app.buttons["summaryDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        snapshot("summary")
        done.tap()

        waitFor(primary, label: "Clock in")
    }

    // MARK: Out of reach

    @MainActor
    func testTapsWaitOutOfReachAndFlushWhenThePhoneIsBack() {
        launch("-watchDemoWorking", "-watchPhoneAway")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        waitFor(primary, label: "Mark row 17 in block 2 shaped")

        primary.tap()
        waitFor(primary, label: "Mark row 18 in block 2 shaped")
        primary.tap()
        waitFor(primary, label: "Mark row 19 in block 2 shaped")

        let badge = app.buttons["queueBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        waitFor(badge, label: "2 taps waiting for iPhone")
        snapshot("now-two-waiting")

        badge.tap()
        let taps = app.descendants(matching: .any).matching(identifier: "queuedTap")
        XCTAssertTrue(taps.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(taps.count, 2)
        snapshot("queue-sheet")
        dismissSheet()

        // The phone sends a state without the waiting taps: the screen keeps them.
        app.swipeLeft()
        let push = app.buttons["demoPushState"]
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.tap()
        app.swipeRight()
        waitFor(primary, label: "Mark row 19 in block 2 shaped")

        // The phone comes back: the taps apply and the badge clears.
        app.swipeLeft()
        app.buttons["demoPhoneReach"].tap()
        waitUntilGone(badge, timeout: 15)
        app.swipeRight()
        waitFor(primary, label: "Mark row 19 in block 2 shaped")
    }

    @MainActor
    func testAClockOutOutOfReachWaitsThenTheSummaryShows() {
        launch("-watchDemoWorking", "-watchPhoneAway", "-watchPhoneBackAfter", "25")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))

        app.swipeRight()
        let clockOut = app.buttons["clockOut"]
        XCTAssertTrue(clockOut.waitForExistence(timeout: 5))
        clockOut.tap()
        let yes = app.buttons["Yes, clock out"]
        XCTAssertTrue(yes.waitForExistence(timeout: 5))
        yes.tap()

        let waiting = app.descendants(matching: .any)["clockOutWaiting"]
        XCTAssertTrue(waiting.waitForExistence(timeout: 10))
        snapshot("summary-clock-out-waiting")

        waitUntilGone(waiting, timeout: 40)
        XCTAssertTrue(app.buttons["summaryDone"].exists)
        snapshot("summary-after-phone-back")
    }

    // MARK: Fit

    @MainActor
    func testNowFitsWithoutScrolling() {
        launch("-watchDemoWorking")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(primary.isHittable)
        XCTAssertLessThanOrEqual(primary.frame.maxY, window.maxY)
        XCTAssertGreaterThanOrEqual(primary.frame.minY, window.minY)
        XCTAssertEqual(app.scrollViews.count, 0, "Now must not scroll: Double Tap would scroll instead of acting")
    }

    @MainActor
    func testNowFitsAtTheLargestText() {
        launch("-watchDemoWorking", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        XCTAssertTrue(primary.isHittable)
        XCTAssertLessThanOrEqual(primary.frame.maxY, app.windows.firstMatch.frame.maxY)
        XCTAssertEqual(app.scrollViews.count, 0)
        snapshot("now-largest-text")
    }

    private func dismissSheet() {
        let close = app.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 2) {
            close.tap()
        } else {
            app.swipeDown()
        }
        waitUntilGone(app.descendants(matching: .any).matching(identifier: "queuedTap").firstMatch, timeout: 5)
    }
}
