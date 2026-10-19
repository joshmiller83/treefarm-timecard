import XCTest

/// The Clock tab's main flows on the demo farm (in-memory store, offline stub server).
/// Screenshots of each step are kept as test attachments.
@MainActor
final class ClockFlowUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"] + extra
        app.launch()
        return app
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Waits until the element's label matches.
    private func waitFor(_ element: XCUIElement, label: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", label)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: timeout), .completed,
                       "expected “\(label)”, saw “\(element.exists ? element.label : "nothing")”", file: file, line: line)
    }

    private func waitFor(_ element: XCUIElement, labelBeginsWith prefix: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", prefix)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: timeout), .completed,
                       "expected “\(prefix)…”, saw “\(element.exists ? element.label : "nothing")”", file: file, line: line)
    }

    private func waitFor(_ element: XCUIElement, labelContains part: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", part)
        let found = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: timeout), .completed,
                       "expected “…\(part)…”, saw “\(element.exists ? element.label : "nothing")”", file: file, line: line)
    }

    // MARK: Flows

    func testClockInLunchBackToWorkAndClockOut() {
        let app = launch()
        let clockIn = app.buttons["clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
        let pill = element("status-pill", in: app)
        waitFor(pill, label: "Off the clock")
        XCTAssertEqual(element("big-timer", in: app).exists, true)
        shot(app, "1 Off the clock")

        clockIn.tap()
        waitFor(element("toast", in: app), labelBeginsWith: "Clocked in at")
        waitFor(pill, label: "On the clock")
        waitFor(element("now-place", in: app), label: "Block 1, row 5")
        shot(app, "2 Clocked in")

        app.buttons["start-lunch"].tap()
        waitFor(element("toast", in: app), labelBeginsWith: "Lunch started at")
        waitFor(pill, label: "On lunch")
        waitFor(element("break-line", in: app), labelBeginsWith: "Lunch started")
        shot(app, "3 On lunch")

        app.buttons["back-to-work"].tap()
        waitFor(element("toast", in: app), labelBeginsWith: "Back at")
        waitFor(pill, label: "On the clock")
        shot(app, "4 Back to work")

        clockOut(app)
        waitFor(element("toast", in: app), labelBeginsWith: "Clocked out at")
        waitFor(pill, label: "Off the clock")
        waitFor(element("status-meta", in: app), labelBeginsWith: "Last clocked out at")
        shot(app, "5 Clocked out")
    }

    /// Two taps on Clock out. The second has to land within five seconds, so on a slow test
    /// machine this asks again if the first one lapsed.
    private func clockOut(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let out = app.buttons["clock-out"]
        let off = NSPredicate(format: "label == %@", "Off the clock")
        for _ in 0..<3 {
            out.tap()
            out.tap()
            let done = XCTNSPredicateExpectation(predicate: off, object: element("status-pill", in: app))
            if XCTWaiter().wait(for: [done], timeout: 4) == .completed { return }
        }
        XCTFail("Couldn’t clock out", file: file, line: line)
    }

    func testClockOutAsksTwiceAndForgetsTheFirstTap() {
        let app = launch()
        let clockIn = app.buttons["clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
        clockIn.tap()
        let out = app.buttons["clock-out"]
        XCTAssertTrue(out.waitForExistence(timeout: 5))
        out.tap()
        let question = element("clock-out-question", in: app)
        XCTAssertTrue(question.waitForExistence(timeout: 4))
        shot(app, "Tap again to clock out")
        XCTAssertTrue(question.label.hasPrefix("You’ve worked"), question.label)
        // Left alone, it goes back after a few seconds, so a pocket bump can't finish the job later.
        waitFor(out, label: "Clock out", timeout: 8)
        waitFor(element("status-pill", in: app), label: "On the clock")
    }

    func testRowButtonsMarkRowsAndUndoTakesThemBack() {
        let app = launch()
        let clockIn = app.buttons["clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
        clockIn.tap()

        let first = app.buttons["next-row-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Mark row 5")
        first.tap()
        waitFor(element("toast", in: app), labelBeginsWith: "Row 5 marked")
        waitFor(element("trees-card", in: app), labelContains: "60 of 960")
        waitFor(element("now-place", in: app), label: "Block 1, row 6")
        waitFor(element("last-action", in: app), label: "Row 5 marked")
        shot(app, "Row 5 marked")

        app.buttons["undo"].tap()
        waitFor(element("toast", in: app), label: "Undid row 5.")
        waitFor(element("now-place", in: app), label: "Block 1, row 5")
    }

    func testOtherBreakTakesAReason() {
        let app = launch()
        let clockIn = app.buttons["clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
        clockIn.tap()
        let other = app.buttons["start-break"]
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()

        let fuel = app.buttons["reason-Fuel run"]
        XCTAssertTrue(fuel.waitForExistence(timeout: 5))
        fuel.tap()
        shot(app, "Other break")
        app.buttons["break-go"].tap()
        waitFor(element("toast", in: app), labelBeginsWith: "Break for Fuel run started at")
        waitFor(element("status-pill", in: app), label: "On break")
        waitFor(element("break-line", in: app), labelContains: "Fuel run")
    }

    func testChangeStartTimeSaysWhyATimeWontWork() {
        let app = launch()
        let clockIn = app.buttons["clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
        clockIn.tap()
        app.buttons["change-start"].tap()
        let later = app.buttons["start-nudge5"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        app.buttons["start-save"].tap()
        waitFor(element("form-error", in: app), label: "That time hasn’t happened yet. Pick an earlier time.")
        shot(app, "Change start time refused")

        app.buttons["start-nudge-15"].tap()
        app.buttons["start-nudge-5"].tap()
        app.buttons["start-save"].tap()
        waitFor(element("toast", in: app), labelBeginsWith: "Start time changed to")
        waitFor(element("status-pill", in: app), label: "On the clock")
    }

    func testAShiftLeftOpenOffersToFixTheTimes() {
        let app = launch(["-UITestClock", "stale"])
        let warning = element("stale-warning", in: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 10))
        waitFor(element("big-timer", in: app), labelContains: "worked this shift")
        shot(app, "Forgot to clock out")
        app.buttons["fix-times"].tap()
        // The shift editor (from the Log tab) opens on top.
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testSettingsKeepSiriChoicesAndYourDetails() {
        let app = launch()
        let gear = app.buttons["settings-button"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()

        let job = app.textFields["profile-job"]
        XCTAssertTrue(job.waitForExistence(timeout: 5))
        job.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        job.typeText(" and pruning")
        app.buttons["profile-save"].tap()
        XCTAssertTrue(element("profile-saved", in: app).waitForExistence(timeout: 5))
        shot(app, "Settings: your details")

        let ask = app.switches["ask-break-reason"]
        XCTAssertTrue(ask.waitForExistence(timeout: 5))
        for _ in 0..<6 where !ask.isHittable { app.swipeUp() }
        XCTAssertEqual(ask.value as? String, "0")
        ask.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        waitFor(ask, value: "1")
        XCTAssertTrue(element("siri-phrases", in: app).exists)
        shot(app, "Settings: Siri")

        app.buttons["settings-done"].tap()
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        let subtitle = app.staticTexts["Crew lead and pruning · Alex Rivera"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))

        gear.tap()
        let again = app.switches["ask-break-reason"]
        XCTAssertTrue(again.waitForExistence(timeout: 5))
        XCTAssertEqual(again.value as? String, "1")
    }

    private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let found = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [found], timeout: timeout), .completed, "value stayed \(element.value ?? "nil")", file: file, line: line)
    }
}
