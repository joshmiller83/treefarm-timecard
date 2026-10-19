import XCTest

/// The Team tab: making an invite, adding a block, the last-admin rule, and a walk past
/// every screen that leaves screenshots in the test results.
///
/// Launch arguments: `-UITestInMemory` (the demo admin on the demo farm), `-UITestTab team`,
/// and the Team tab's own `-UITestTeamSection crew|fields|season` and `-UITestTeamWeek`
/// (two weeks of shifts, the worker on the clock, a former crew member).
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
        note.tap()
        note.typeText("Jordan\n")
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
        name.typeText("South Field")
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
        rows.tap()
        rows.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "3")
        let message = "12 shaped trees would fall outside that size. Erase them first, or keep the size."
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
        shot("block-resize-refused", app)

        let remove = app.buttons["block-remove"]
        reveal(remove, in: app)
        remove.tap()
        XCTAssertTrue(app.staticTexts["This block has 48 shaped trees, so it can’t be removed. Erase them first."].waitForExistence(timeout: 5))
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
