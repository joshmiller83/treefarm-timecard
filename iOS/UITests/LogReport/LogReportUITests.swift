import XCTest

/// The Log and Report tabs, offline on the demo farm.
///
/// Launch arguments (see `LogScenario`): `-UITestLog weeks` adds two weeks of shifts with
/// trees for the demo admin and Sam; `-UITestOpenShift last|new` opens the editor at launch;
/// `-UITestReportPeriod lastWeek` starts the Report on last week.
///
/// With `TEST_RUNNER_LOGREPORT_ARTIFACTS=<folder>` passed to xcodebuild, the screenshot test
/// saves PNGs of each screen there for a person to look at, then the Log, the editor and the
/// Report again at the largest text size (`-UIPreferredContentSizeCategoryName`).
@MainActor
final class LogReportUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"] + extra
        app.launch()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func toast(_ app: XCUIApplication) -> XCUIElement {
        element("log-toast", in: app)
    }

    // MARK: Log

    func testAddAShiftThenAddItsLunch() {
        let app = launch(["-UITestTab", "log"])
        XCTAssertTrue(element("log-empty", in: app).waitForExistence(timeout: 10), "a new account starts with an empty log")

        app.buttons["add-shift"].tap()
        XCTAssertTrue(app.navigationBars["Add a Shift"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("editor-totals", in: app).label.contains("8.50 hrs worked"))
        app.buttons["editor-save"].tap()

        XCTAssertTrue(toast(app).waitForExistence(timeout: 5))
        XCTAssertEqual(toast(app).label, "Shift added.")
        let row = element("log-shift-row", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("7:00 AM to 3:30 PM"), row.label)
        XCTAssertTrue(row.label.contains("8.50 hours"), row.label)

        app.buttons["log-edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 5))
        app.buttons["editor-add-break"].tap()
        let breakStart = element("editor-break-start", in: app)
        XCTAssertTrue(breakStart.waitForExistence(timeout: 5))
        XCTAssertEqual(breakStart.value as? String, "12:00 PM")
        type("Rain", into: app.textFields["editor-break-reason"])
        app.buttons["editor-save"].tap()

        XCTAssertTrue(toast(app).waitForExistence(timeout: 5))
        XCTAssertEqual(toast(app).label, "Shift saved.")
        let updated = element("log-shift-row", in: app)
        XCTAssertTrue(updated.label.contains("Lunch 30 min (Rain)"), updated.label)
        XCTAssertTrue(updated.label.contains("8.00 hours"), updated.label)
    }

    func testAnOverlappingShiftShowsTheRule() {
        let app = launch(["-UITestTab", "log"])
        XCTAssertTrue(app.buttons["add-shift"].waitForExistence(timeout: 10))
        app.buttons["add-shift"].tap()
        app.buttons["editor-save"].tap()
        XCTAssertTrue(element("log-shift-row", in: app).waitForExistence(timeout: 5))

        // The same hours again clash with the shift just added.
        app.buttons["add-shift"].tap()
        XCTAssertTrue(app.navigationBars["Add a Shift"].waitForExistence(timeout: 5))
        app.buttons["editor-save"].tap()
        let error = element("editor-problem", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.hasPrefix("This overlaps your shift on"), error.label)

        // A day earlier fixes it.
        app.buttons["editor-day-back"].tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 3))
        app.buttons["editor-save"].tap()
        XCTAssertTrue(toast(app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "log-shift-row").count, 2)
    }

    func testDeletingAShiftAsksTwiceAndUnmarksItsTrees() {
        let app = launch(["-UITestTab", "log", "-UITestLog", "weeks", "-UITestOpenShift", "last"])
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 15))
        let delete = app.buttons["editor-delete"]
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        delete.tap()

        let question = element("editor-delete-question", in: app)
        XCTAssertTrue(question.waitForExistence(timeout: 5))
        XCTAssertTrue(question.label.contains("trees will be unmarked on the map too"), question.label)
        let confirm = app.buttons["editor-confirm-delete"]
        XCTAssertTrue(confirm.label.hasPrefix("Delete shift and "), confirm.label)

        // "Keep this shift" backs out; the second ask really deletes.
        app.buttons["editor-keep"].tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 3))
        for _ in 0..<6 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(toast(app).waitForExistence(timeout: 5))
        XCTAssertTrue(toast(app).label.hasPrefix("Shift deleted."), toast(app).label)
        XCTAssertTrue(toast(app).label.contains("trees unmarked"), toast(app).label)
    }

    func testCancelWithChangesAsksFirst() {
        let app = launch(["-UITestTab", "log", "-UITestLog", "weeks", "-UITestOpenShift", "last"])
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 15))
        // Nothing changed yet: Cancel just closes.
        app.buttons["editor-cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForNonExistence(timeout: 5))

        app.buttons["log-edit"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 5))
        app.buttons["editor-day-back"].tap()
        app.buttons["editor-cancel"].tap()
        let discard = app.buttons["Discard changes"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Cancel with changes asks before throwing them away")
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(discard.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Edit Shift"].exists)
        app.buttons["editor-cancel"].tap()
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.tap()
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(toast(app).exists, "nothing was saved")
    }

    func testTreesButtonShowsTheShiftsRows() {
        let app = launch(["-UITestTab", "log", "-UITestLog", "weeks"])
        let trees = app.buttons["log-trees"].firstMatch
        XCTAssertTrue(trees.waitForExistence(timeout: 15))
        trees.tap()
        XCTAssertTrue(element("shift-trees-sheet", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["trees shaped"].exists)
        app.buttons["trees-done"].tap()
    }

    // MARK: Report

    func testExportThePDFAndTheCSV() {
        let app = launch(["-UITestTab", "report", "-UITestLog", "weeks", "-UITestReportPeriod", "lastWeek"])
        let row = element("paper-row", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(element("paper-totals", in: app).exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '$'")).firstMatch.exists, "pay never shows on the report")

        app.buttons["export-pdf"].tap()
        XCTAssertTrue(waitForShareSheet(in: app), "the share sheet should open for the PDF")
        dismissShareSheet(in: app)

        app.buttons["export-csv"].tap()
        XCTAssertTrue(waitForShareSheet(in: app), "the share sheet should open for the CSV")
        dismissShareSheet(in: app)
    }

    func testPickDatesAndAnotherCrewMember() {
        let app = launch(["-UITestTab", "report", "-UITestLog", "weeks", "-UITestReportPeriod", "lastWeek"])
        XCTAssertTrue(element("paper-row", in: app).waitForExistence(timeout: 15))
        let mine = app.descendants(matching: .any).matching(identifier: "paper-row").count

        // Sam worked four days last week.
        app.buttons["report-person"].tap()
        let sam = app.buttons["Sam Ortiz"]
        XCTAssertTrue(sam.waitForExistence(timeout: 5))
        sam.tap()
        XCTAssertEqual(app.buttons["report-person"].value as? String, "Sam Ortiz")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "paper-row").count, 4)
        XCTAssertNotEqual(mine, 4)

        // Pick dates opens on the period showing; applying it keeps those days.
        let label = app.staticTexts["report-range-label"].label
        app.buttons["report-pick-dates"].tap()
        XCTAssertTrue(app.navigationBars["Pick Dates"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["pick-summary"].label, label)
        app.buttons["pick-apply"].tap()
        XCTAssertTrue(app.staticTexts["Your dates"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["report-range-label"].label, label)
    }

    // MARK: Screenshots

    /// Saves each screen when `LOGREPORT_ARTIFACTS` is set; otherwise skipped.
    func testScreenshots() throws {
        guard let folder = ProcessInfo.processInfo.environment["LOGREPORT_ARTIFACTS"], !folder.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_LOGREPORT_ARTIFACTS to save screenshots.")
        }
        let tag = ProcessInfo.processInfo.environment["LOGREPORT_TAG"] ?? "light"
        func shot(_ name: String) {
            let data = XCUIScreen.main.screenshot().pngRepresentation
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(tag)-\(name).png"))
        }

        var app = launch(["-UITestTab", "log", "-UITestLog", "weeks"])
        XCTAssertTrue(element("log-shift-row", in: app).waitForExistence(timeout: 15))
        sleep(1)
        shot("log-1")
        app.swipeUp()
        sleep(1)
        shot("log-2")
        app.terminate()

        app = launch(["-UITestTab", "log", "-UITestLog", "weeks", "-UITestOpenShift", "last"])
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 15))
        app.buttons["editor-add-break"].tap()
        sleep(1)
        shot("editor-1")
        app.buttons["editor-clock-out"].tap()
        sleep(1)
        shot("editor-2")
        app.buttons["editor-clock-out"].tap()
        for _ in 0..<4 { app.swipeUp() }
        app.buttons["editor-delete"].tap()
        sleep(1)
        shot("editor-3")
        app.terminate()

        app = launch(["-UITestTab", "report", "-UITestLog", "weeks", "-UITestReportPeriod", "lastWeek"])
        XCTAssertTrue(element("paper-row", in: app).waitForExistence(timeout: 15))
        sleep(1)
        shot("report-1")
        app.swipeUp()
        sleep(1)
        shot("report-2")
        app.swipeUp()
        sleep(1)
        shot("report-3")
        app.swipeDown()
        app.swipeDown()
        app.buttons["report-pick-dates"].tap()
        sleep(1)
        shot("report-pick")
        app.terminate()

        // The largest text size: numbers, dates and choices never break inside a word.
        let ax5 = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app = launch(["-UITestTab", "log", "-UITestLog", "weeks"] + ax5)
        XCTAssertTrue(element("log-shift-row", in: app).waitForExistence(timeout: 15))
        sleep(1)
        shot("ax5-log-1")
        app.swipeUp()
        sleep(1)
        shot("ax5-log-2")
        app.terminate()

        app = launch(["-UITestTab", "log", "-UITestLog", "weeks", "-UITestOpenShift", "last"] + ax5)
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 15))
        app.buttons["editor-add-break"].tap()
        sleep(1)
        shot("ax5-editor-1")
        app.terminate()

        app = launch(["-UITestTab", "report", "-UITestLog", "weeks", "-UITestReportPeriod", "lastWeek"] + ax5)
        XCTAssertTrue(element("paper-row", in: app).waitForExistence(timeout: 15))
        sleep(1)
        shot("ax5-report-1")
        app.swipeUp()
        sleep(1)
        shot("ax5-report-2")
        app.terminate()
    }

    // MARK: Helpers

    /// Taps a text field until it has the keyboard, then types. A tap that lands while the
    /// editor is still scrolling a new break into view can miss the field.
    private func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        var focused = false
        for _ in 0..<3 where !focused {
            wait(for: field, "isHittable == true", timeout: 5)
            field.tap()
            focused = wait(for: field, "hasKeyboardFocus == true", timeout: 3)
        }
        XCTAssertTrue(focused, "the field never took the keyboard", file: file, line: line)
        field.typeText(text)
    }

    @discardableResult
    private func wait(for element: XCUIElement, _ predicate: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Waits for the system share sheet, however this iOS version shows it.
    private func waitForShareSheet(in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let candidates = [
            app.otherElements["ActivityListView"],
            app.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'ActivityList'")).firstMatch,
            app.buttons["Copy"],
            app.cells["Copy"],
            app.buttons["Save to Files"],
            app.cells["Save to Files"],
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if candidates.contains(where: \.exists) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return false
    }

    private func dismissShareSheet(in app: XCUIApplication) {
        let close = app.buttons["Close"].exists ? app.buttons["Close"] : app.navigationBars.buttons.firstMatch
        if close.exists {
            close.tap()
        } else {
            app.swipeDown(velocity: .fast)
        }
        _ = app.buttons["export-pdf"].waitForExistence(timeout: 5)
        sleep(1)
    }
}
