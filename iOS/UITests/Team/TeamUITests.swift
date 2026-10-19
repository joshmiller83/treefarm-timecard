import XCTest

/// The Team tab: making an invite, adding a block, the last-admin rule, and a walk past
/// every screen that leaves screenshots in the test results.
///
/// Launch arguments: `-UITestInMemory` (the demo admin on the demo farm), `-UITestTab team`,
/// and the Team tab's own `-UITestTeamSection crew|fields|season`, `-UITestTeamWeek`
/// (two weeks of shifts, the worker on the clock, a former crew member), `-UITestTeamForgot`
/// (the worker's shift open 26 hours) and `-UITestTeamWaiting` (before the first pull).
/// Set `TEST_RUNNER_TEAM_TYPE_SIZE=UICTContentSizeCategoryAccessibilityL` to walk at a big text size.
final class TeamUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestTab", "team"] + extra
        if let size = ProcessInfo.processInfo.environment["TEAM_TYPE_SIZE"], !size.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size]
        }
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        let suffix = ProcessInfo.processInfo.environment["TEAM_SHOT_SUFFIX"] ?? ""
        attachment.name = "team-\(name)\(suffix)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps a text field and waits until it has the keyboard before typing. On a fresh
    /// simulator the first tap can land before the field is ready, so it taps again.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication, tap: Bool = true) {
        var focused = false
        for attempt in 0..<3 where !focused {
            if tap || attempt > 0 { field.tap() }
            focused = waitForKeyboardFocus(field, in: app)
        }
        XCTAssertTrue(focused, "\(field.identifier) never got the keyboard")
        field.typeText(text)
    }

    private func waitForKeyboardFocus(_ field: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 4) -> Bool {
        let hasFocus = NSPredicate(format: "hasKeyboardFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: hasFocus, object: field)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed && app.keyboards.firstMatch.waitForExistence(timeout: 2)
    }

    /// The dialog's button sits next to the button that opened it, not over unrelated controls.
    private func assertDialog(_ action: XCUIElement, isBy button: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(action.waitForExistence(timeout: 5), file: file, line: line)
        let gap = min(abs(action.frame.minY - button.maxY), abs(button.minY - action.frame.maxY), abs(action.frame.midY - button.midY))
        XCTAssertLessThan(gap, 260, "dialog at \(action.frame), button at \(button)", file: file, line: line)
    }

    /// Back to the top of the page, where the Crew, Fields and Season buttons are.
    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<3 { app.swipeDown() }
    }

    /// Scrolls the page until the element is on screen and can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = false) {
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            up ? app.swipeDown() : app.swipeUp()
        }
    }

    // MARK: Flows

    func testMakingAnInviteShowsACodeToReadAloudAndListsIt() {
        let app = launch()
        let invite = app.buttons["team-invite"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10))
        invite.tap()

        let note = app.textFields["invite-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        type("Jordan\n", into: note, in: app)
        app.buttons["invite-role-worker"].tap()
        app.buttons["invite-make"].tap()

        let code = element("code-display", in: app)
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.label.hasPrefix("Code: "), code.label)
        XCTAssertTrue(app.staticTexts["This is the only time the code is shown. Share it or write it down now."].exists)
        XCTAssertTrue(app.buttons["code-share"].exists)
        shot("invite-code", app)

        app.buttons["invite-done"].tap()
        let listed = element("invite-Jordan", in: app)
        XCTAssertTrue(listed.waitForExistence(timeout: 5))
        reveal(listed, in: app)
        shot("invites", app)
    }

    func testAddingABlockToTheRightOfAnother() {
        let app = launch(["-UITestTeamSection", "fields"])
        let field = element("field-North Field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()

        let add = app.buttons["block-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        reveal(add, in: app)
        add.tap()

        let name = app.textFields["block-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "5")
        let placement = app.buttons["block-placement"]
        reveal(placement, in: app)
        placement.tap()
        let rightOfOne = app.buttons["To the right of Block 1"]
        XCTAssertTrue(rightOfOne.waitForExistence(timeout: 5))
        rightOfOne.tap()

        let more = app.buttons["One more: Rows in block"]
        reveal(more, in: app, up: true)
        more.tap()
        more.tap()
        XCTAssertEqual(app.textFields["block-rows"].value as? String, "22")
        shot("block-new", app)

        let save = app.buttons["block-save"]
        reveal(save, in: app)
        save.tap()

        let added = element("block-row-Block 5", in: app)
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertTrue(added.label.contains("22 rows"), added.label)
        // Walk order is now Block 1, Block 5, Block 2: it went in right of Block 1.
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'block-row-'"))
        let order = rows.allElementsBoundByIndex.sorted { $0.frame.minY < $1.frame.minY }.map { $0.identifier }
        XCTAssertEqual(Array(order.prefix(3)), ["block-row-Block 1", "block-row-Block 5", "block-row-Block 2"])
        shot("field-after-add", app)
    }

    func testANewFieldOpensForItsFirstBlock() {
        let app = launch(["-UITestTeamSection", "fields"])
        let add = app.buttons["field-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        reveal(add, in: app)
        add.tap()
        let name = app.textFields["field-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        // The sheet focuses the name itself; tap only if it hasn't.
        type("South Field", into: name, in: app, tap: false)
        app.buttons["field-name-save"].tap()

        XCTAssertTrue(app.navigationBars["South Field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No blocks yet"].exists)
        app.buttons["block-add"].tap()
        let placement = app.buttons["block-placement"]
        XCTAssertTrue(placement.waitForExistence(timeout: 5))
        XCTAssertTrue(placement.label.contains("The first block"), placement.label)
        XCTAssertEqual(app.textFields["block-name"].value as? String, "1")
        let save = app.buttons["block-save"]
        reveal(save, in: app)
        save.tap()
        let block = element("block-row-Block 1", in: app)
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        XCTAssertTrue(block.label.contains("20 rows of 10 trees"), block.label)
    }

    func testTheOnlyAdminCannotStepDown() {
        let app = launch()
        let alex = element("crew-Alex Rivera", in: app)
        XCTAssertTrue(alex.waitForExistence(timeout: 10))
        alex.tap()
        let edit = app.buttons["member-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        reveal(edit, in: app)
        edit.tap()
        let crew = app.buttons["member-role-worker"]
        XCTAssertTrue(crew.waitForExistence(timeout: 5))
        crew.tap()
        let save = app.buttons["member-save"]
        reveal(save, in: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["A farm needs at least one admin. Make someone else an admin first."].waitForExistence(timeout: 5))
        shot("last-admin", app)
    }

    func testABlockWithShapedTreesCannotShrinkOrGo() {
        let app = launch(["-UITestTeamSection", "fields"])
        let field = element("field-North Field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        let block = element("block-row-Block 1", in: app)
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        reveal(block, in: app)
        block.tap()

        // Sam shaped rows 1–4 of block 1, so three rows is too small.
        let rows = app.textFields["block-rows"]
        XCTAssertTrue(rows.waitForExistence(timeout: 5))
        type(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "3", into: rows, in: app)
        let message = "12 shaped trees would fall outside that size. Erase them first, or keep the size."
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
        shot("block-resize-refused", app)

        let remove = app.buttons["block-remove"]
        reveal(remove, in: app)
        remove.tap()
        XCTAssertTrue(app.staticTexts["This block has 48 shaped trees, so it can’t be removed. Erase them first."].waitForExistence(timeout: 5))
    }

    func testAForgottenClockOutIsFlaggedForTheAdmin() {
        let app = launch(["-UITestTeamWeek", "-UITestTeamForgot"])
        let sam = element("crew-Sam Ortiz", in: app)
        XCTAssertTrue(sam.waitForExistence(timeout: 10))
        let summary = element("team-forgot", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.label, "Sam Ortiz may have forgotten to clock out.")
        XCTAssertTrue(sam.label.contains("Still clocked in since"), sam.label)
        XCTAssertTrue(sam.label.contains("(26 h). Did Sam forget to clock out?"), sam.label)
        shot("forgot-crew", app)

        sam.tap()
        let warning = element("member-forgot", in: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["member-fix-shift"].exists)
        XCTAssertTrue(element("Trees this week", in: app).exists)
        shot("forgot-member", app)
        app.buttons["member-fix-shift"].tap()
        // The shift editor opens over the page (the Log slice's editor).
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).waitForExistence(timeout: 5))
        shot("forgot-fix", app)
    }

    func testBeforeTheFirstPullNothingOffersToStartOver() {
        let app = launch(["-UITestTeamWaiting", "-UITestTeamSection", "fields"])
        let waiting = element("team-waiting", in: app)
        XCTAssertTrue(waiting.waitForExistence(timeout: 10))
        XCTAssertTrue(waiting.label.contains("Getting the farm from the server…"), waiting.label)
        XCTAssertFalse(app.buttons["field-add"].exists)
        XCTAssertFalse(app.staticTexts["No fields yet"].exists)
        shot("waiting-fields", app)
        app.buttons["team-section-season"].tap()
        XCTAssertTrue(element("team-waiting", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["season-start"].exists)
        XCTAssertFalse(app.staticTexts["No season yet"].exists)
    }

    func testConfirmationsOpenBesideTheirButtons() {
        let app = launch(["-UITestTeamWeek"])
        // Revoke: by the invite's own button.
        let revoke = app.buttons["invite-revoke"].firstMatch
        XCTAssertTrue(revoke.waitForExistence(timeout: 10))
        reveal(revoke, in: app)
        revoke.tap()
        assertDialog(app.buttons["Revoke invite"], isBy: revoke.frame)
        shot("dialog-revoke", app)
        dismissDialog(app, cancel: "Keep it", action: app.buttons["Revoke invite"])

        // Remove someone: by "Remove from the farm".
        scrollToTop(app)
        element("crew-Sam Ortiz", in: app).tap()
        let remove = app.buttons["member-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        reveal(remove, in: app)
        remove.tap()
        assertDialog(app.buttons["Remove Sam"], isBy: remove.frame)
        shot("dialog-remove", app)
        dismissDialog(app, cancel: "Keep Sam", action: app.buttons["Remove Sam"])
        app.navigationBars.buttons.firstMatch.tap()

        // Archive a field: by "Archive field".
        XCTAssertTrue(app.navigationBars["Team"].waitForExistence(timeout: 5))
        scrollToTop(app)
        app.buttons["team-section-fields"].tap()
        element("field-North Field", in: app).tap()
        let archive = app.buttons["field-archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        reveal(archive, in: app)
        archive.tap()
        // The dialog's "Archive field", not the page's button with the same words.
        let confirmArchive = app.buttons.matching(NSPredicate(format: "label == 'Archive field' AND identifier != 'field-archive'")).firstMatch
        assertDialog(confirmArchive, isBy: archive.frame)
        shot("dialog-archive", app)
        dismissDialog(app, cancel: "Keep it on the map", action: confirmArchive)
        app.navigationBars.buttons.firstMatch.tap()

        // Start a season: by its Start button, not over the name field.
        XCTAssertTrue(app.navigationBars["Team"].waitForExistence(timeout: 5))
        scrollToTop(app)
        app.buttons["team-section-season"].tap()
        let start = app.buttons["season-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        reveal(start, in: app)
        start.tap()
        let begin = app.buttons["season-new-start"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sam Ortiz is on the clock right now."].exists)
        reveal(begin, in: app)
        let title = begin.label
        begin.tap()
        // The dialog's own "Start 2026", not the sheet's button with the same words.
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'season-new-start'", title)).firstMatch
        assertDialog(confirm, isBy: begin.frame)
        // Below the season name, not covering it.
        XCTAssertGreaterThan(confirm.frame.minY, app.textFields["season-new-name"].frame.maxY)
        shot("dialog-season", app)
    }

    /// Closes a dialog with its cancel button, or by tapping away when it shows as a popover
    /// (a popover has no cancel button), and waits until its action is gone.
    private func dismissDialog(_ app: XCUIApplication, cancel: String, action: XCUIElement) {
        let button = app.buttons[cancel]
        if button.exists && button.isHittable {
            button.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
        XCTAssertTrue(action.waitForNonExistence(timeout: 5))
    }

    func testASeasonStartedByMistakeCanBeTakenBack() {
        let app = launch(["-UITestTeamSection", "season"])
        let name = element("season-name", in: app)
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let before = name.label
        let start = app.buttons["season-start"]
        reveal(start, in: app)
        start.tap()
        let begin = app.buttons["season-new-start"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        let title = begin.label
        begin.tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'season-new-start'", title)).firstMatch.tap()

        // The new season is active, and the one before it can come back while nothing is shaped.
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, String(title.dropFirst("Start ".count)))
        let undo = app.buttons["season-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        reveal(undo, in: app)
        shot("season-undo", app)
        undo.tap()
        let confirm = app.buttons["Make \(before) active"]
        assertDialog(confirm, isBy: undo.frame)
        shot("dialog-season-undo", app)
        confirm.tap()
        reveal(name, in: app, up: true)
        XCTAssertTrue(app.staticTexts[before].waitForExistence(timeout: 5))
        XCTAssertEqual(name.label, before)
        XCTAssertFalse(app.buttons["season-undo"].exists)
    }

    // MARK: A look at every screen

    func testWalkThroughEveryTeamScreen() {
        let app = launch(["-UITestTeamWeek"])
        XCTAssertTrue(app.navigationBars["Team"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("crew-Sam Ortiz", in: app).waitForExistence(timeout: 10))
        sleep(1)
        shot("1-crew", app)
        let former = element("crew-Jo Banks", in: app)
        reveal(former, in: app)
        shot("2-crew-bottom", app)
        reveal(element("crew-Sam Ortiz", in: app), in: app, up: true)

        element("crew-Sam Ortiz", in: app).tap()
        XCTAssertTrue(app.buttons["member-report"].waitForExistence(timeout: 5))
        shot("3-member", app)
        let reset = app.buttons["member-reset"]
        reveal(reset, in: app)
        shot("4-member-tools", app)
        reset.tap()
        XCTAssertTrue(element("code-display", in: app).waitForExistence(timeout: 5))
        shot("5-reset-code", app)
        app.buttons["reset-done"].tap()

        let report = app.buttons["member-report"]
        reveal(report, in: app, up: true)
        report.tap()
        XCTAssertTrue(element("report-total", in: app).waitForExistence(timeout: 5))
        shot("6-report-week", app)
        app.buttons["report-last-week"].tap()
        shot("7-report-last-week", app)
        app.navigationBars.buttons.firstMatch.tap()
        let edit = app.buttons["member-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.buttons["member-save"].waitForExistence(timeout: 5))
        shot("8-member-edit", app)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["member-edit"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Team"].waitForExistence(timeout: 5))
        scrollToTop(app)
        app.buttons["team-section-fields"].tap()
        XCTAssertTrue(element("field-North Field", in: app).waitForExistence(timeout: 5))
        shot("9-fields", app)
        element("field-North Field", in: app).tap()
        XCTAssertTrue(app.buttons["block-add"].waitForExistence(timeout: 5))
        shot("10-field-editor", app)
        let add = app.buttons["block-add"]
        reveal(add, in: app)
        shot("11-field-editor-bottom", app)
        add.tap()
        XCTAssertTrue(app.buttons["block-save"].waitForExistence(timeout: 5))
        shot("12-block-new", app)
        app.swipeUp()
        shot("13-block-new-bottom", app)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["block-add"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["Team"].waitForExistence(timeout: 5))
        scrollToTop(app)
        app.buttons["team-section-season"].tap()
        XCTAssertTrue(element("season-name", in: app).waitForExistence(timeout: 5))
        shot("14-season", app)
        let start = app.buttons["season-start"]
        reveal(start, in: app)
        start.tap()
        XCTAssertTrue(app.buttons["season-new-start"].waitForExistence(timeout: 5))
        shot("15-season-new", app)
    }
}
