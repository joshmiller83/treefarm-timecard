import XCTest

/// The Trees tab, offline on the demo farm (North Field: blocks 1–4 of 20 rows × 12 trees;
/// Sam shaped rows 1–4 of block 1). The map runs at size M in UI tests (it doesn't scale
/// with text size), so trees in a row sit 26 points apart, the first one starting 6 points
/// past the right edge of its row's number.
final class TreesUITests: XCTestCase {
    /// Tree spacing at size M (`MapMetrics.m`).
    static let treeSpacing: CGFloat = 26
    static let largestText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestTab", "trees"] + extra
        app.launch()
        return app
    }

    private func message(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts["trees-message"]
    }

    private func waitForMessage(_ app: XCUIApplication, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", text)
        let found = expectation(for: predicate, evaluatedWith: message(app))
        let result = XCTWaiter().wait(for: [found], timeout: 5)
        XCTAssertEqual(result, .completed, "message was “\(message(app).label)”", file: file, line: line)
    }

    private func clockIn(_ app: XCUIApplication) {
        let clockIn = app.buttons["trees-clock-in"]
        XCTAssertTrue(clockIn.waitForExistence(timeout: 10))
        clockIn.tap()
        XCTAssertTrue(app.buttons["marking-for"].waitForExistence(timeout: 5))
        XCTAssertTrue(message(app).label.hasPrefix("Clocked in at"), message(app).label)
    }

    /// A tree on the map, found from its row's number (scrolled into reach first).
    private func tree(_ position: Int, inRow rowNumber: XCUIElement, file: StaticString = #filePath, line: UInt = #line) -> XCUICoordinate {
        reveal(rowNumber, file: file, line: line)
        return rowNumber.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: 6 + (CGFloat(position) - 0.5) * Self.treeSpacing, dy: 0))
    }

    /// Scrolls the page (the header above the map, not the map) until `element` can be
    /// tapped: at large text sizes the map starts below the tab bar.
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let app = XCUIApplication()
        let page = app.scrollViews["trees-page"]
        for _ in 0..<6 where !element.isHittable {
            // Drag from the top of the page, which is header, never map, until the map is in reach.
            let top = page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: -260)))
        }
        XCTAssertTrue(element.isHittable, "\(element) is out of reach", file: file, line: line)
    }

    private func assertGloveSized(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(element) is missing", file: file, line: line)
        // Half a point of slack: frames come back as 53.99999.
        XCTAssertGreaterThanOrEqual(element.frame.width, 53.5, "\(element.identifier) is too narrow", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 53.5, "\(element.identifier) is too short", file: file, line: line)
    }

    // MARK: Marking

    func testMarkingARowFromTheMapAndUndoingIt() {
        let app = launch()
        clockIn(app)

        let row7 = app.buttons["map-row-1-7"]
        XCTAssertTrue(row7.waitForExistence(timeout: 5))
        XCTAssertEqual(row7.label, "Block 1, row 7")
        XCTAssertEqual(row7.value as? String, "Not shaped")

        reveal(row7)
        row7.tap()
        waitForMessage(app, "Marked 12 trees in Block 1, row 7. Tap the row number again to clear it.")
        XCTAssertEqual(app.buttons["map-row-1-7"].value as? String, "12 of 12 shaped, 12 on this shift")
        XCTAssertTrue(app.buttons["marking-for"].value.map { "\($0)".hasSuffix("12 trees") } ?? false)

        app.buttons["trees-undo"].tap()
        waitForMessage(app, "Undid your last change.")
        XCTAssertEqual(app.buttons["map-row-1-7"].value as? String, "Not shaped")
    }

    func testTappingOneTreeAndSomeoneElsesTree() {
        let app = launch()
        clockIn(app)
        let row8 = app.buttons["map-row-1-8"]
        XCTAssertTrue(row8.waitForExistence(timeout: 5))
        tree(3, inRow: row8).tap()
        waitForMessage(app, "Marked Block 1, row 8, tree 3.")

        let row2 = app.buttons["map-row-1-2"]
        tree(5, inRow: row2).tap()
        XCTAssertTrue(message(app).label.hasPrefix("Block 1, row 2, tree 5 was shaped on "), message(app).label)
    }

    func testTypingRowAndTreeNumbers() {
        let app = launch()
        clockIn(app)
        app.buttons["type-numbers"].tap()
        let fromRow = app.textFields["type-fromRow"]
        XCTAssertTrue(fromRow.waitForExistence(timeout: 5))
        fromRow.typeText("9")
        app.buttons["type-mark"].tap()
        let result = app.staticTexts["type-message"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertEqual(result.label, "Marked 12 trees in Block 1, row 9.")
        app.navigationBars.buttons["Done"].tap()
        XCTAssertEqual(app.buttons["map-row-1-9"].value as? String, "12 of 12 shaped, 12 on this shift")
    }

    // MARK: Notes

    func testAddingATreeNote() {
        let app = launch()
        let row10 = app.buttons["map-row-1-10"]
        XCTAssertTrue(row10.waitForExistence(timeout: 10))
        app.buttons["mode-notes"].tap()
        tree(4, inRow: row10).tap()

        let status = app.staticTexts["tree-card-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Not shaped yet this season.")
        XCTAssertTrue(app.navigationBars["Block 1, row 10, tree 4"].exists)

        app.buttons["tree-card-add-note"].tap()
        let body = app.textViews["note-body"].exists ? app.textViews["note-body"] : app.textFields["note-body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.typeText("Bagworms on the north side")
        app.buttons["note-flag-attention"].tap()
        app.buttons["note-save"].tap()

        XCTAssertTrue(app.staticTexts["Bagworms on the north side"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Needs attention"].exists)
        XCTAssertTrue(app.staticTexts["You"].exists)
        app.buttons["tree-card-done"].tap()

        waitForMessage(app, "Noted on block 1, row 10, tree 4.")
        XCTAssertEqual(app.buttons["map-row-1-10"].value as? String, "Not shaped, 1 note")
    }

    func testLongPressOpensTheTreeCardWithWhoShapedIt() {
        let app = launch()
        let row1 = app.buttons["map-row-1-1"]
        XCTAssertTrue(row1.waitForExistence(timeout: 10))
        tree(2, inRow: row1).press(forDuration: 0.8)
        let status = app.staticTexts["tree-card-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.hasPrefix("Shaped by Sam Ortiz on "), status.label)
    }

    // MARK: The list (what VoiceOver gets)

    func testTheRowListMarksARow() {
        let app = launch()
        clockIn(app)
        app.buttons["trees-list-toggle"].tap()
        let row5 = app.buttons["row-1-5"]
        XCTAssertTrue(row5.waitForExistence(timeout: 5))
        XCTAssertEqual(row5.label, "Block 1, row 5")
        row5.tap()
        waitForMessage(app, "Marked 12 trees in Block 1, row 5. Tap the row number again to clear it.")
        XCTAssertEqual(app.buttons["row-1-5"].value as? String, "12 of 12 shaped, 12 on this shift")
    }

    // MARK: Zoom

    func testPinchingSnapsToASize() {
        let app = launch()
        let map = app.scrollViews["tree-map"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["zoom-m"].isSelected)
        map.pinch(withScale: 2.2, velocity: 2)
        XCTAssertTrue(app.buttons["zoom-l"].waitForSelection(timeout: 5))
        map.pinch(withScale: 0.3, velocity: -2)
        XCTAssertFalse(app.buttons["zoom-l"].isSelected)
    }

    func testTheWholeFieldZoomsIntoATappedBlock() {
        let app = launch()
        let allSizes = app.buttons["zoom-all"]
        XCTAssertTrue(allSizes.waitForExistence(timeout: 10))
        allSizes.tap()
        waitForMessage(app, "This is the whole field. Tap a block to zoom in and mark trees.")
        // Block 1 is the top-left block.
        app.scrollViews["tree-map"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25)).tap()
        waitForMessage(app, "Showing Block 1. Tap All to see the whole field again.")
        XCTAssertTrue(app.buttons["zoom-m"].isSelected)
        XCTAssertTrue(app.buttons["map-row-1-1"].waitForExistence(timeout: 5))
    }

    // MARK: Earlier shifts

    func testMarkingTreesForAnEarlierShift() {
        let app = launch(["-UITestTreesSeed"])
        let picker = app.buttons["marking-for"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        // Wait for the seed: today's shift with rows 5 and 6.
        let seeded = expectation(for: NSPredicate(format: "value CONTAINS %@", "24 trees"), evaluatedWith: picker)
        XCTAssertEqual(XCTWaiter().wait(for: [seeded], timeout: 10), .completed)
        picker.tap()
        let yesterday = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "120 trees")).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        yesterday.tap()
        let back = app.buttons["use-open-shift"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This is an earlier shift, not the one you’re clocked in on."].exists)

        // Row 5 was marked on today's shift, so it's someone else's day now.
        reveal(app.buttons["map-row-1-5"])
        app.buttons["map-row-1-5"].tap()
        waitForMessage(app, "Every tree in Block 1, row 5 was shaped on another day.")

        back.tap()
        XCTAssertFalse(app.buttons["use-open-shift"].waitForExistence(timeout: 1))
    }

    func testSwitchingBackFollowsTheClock() {
        let app = launch(["-UITestTreesSeed"])
        let picker = app.buttons["marking-for"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let seeded = expectation(for: NSPredicate(format: "value CONTAINS %@", "24 trees"), evaluatedWith: picker)
        XCTAssertEqual(XCTWaiter().wait(for: [seeded], timeout: 10), .completed)
        let row9 = app.buttons["map-row-1-9"]
        reveal(row9)
        row9.tap()
        waitForMessage(app, "Marked 12 trees in Block 1, row 9. Tap the row number again to clear it.")
        picker.tap()
        let yesterday = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "120 trees")).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        yesterday.tap()
        XCTAssertTrue(app.buttons["use-open-shift"].waitForExistence(timeout: 5))
        // “Marked 12 trees…” was about today's shift, so it goes.
        waitForMessage(app, "Tap a tree to mark it, or a row number to mark the whole row.")
        app.buttons["use-open-shift"].tap()
        XCTAssertTrue((picker.value as? String)?.hasPrefix("Today") ?? false, "\(String(describing: picker.value))")
    }

    // MARK: A shift left open

    func testAShiftLeftOpenSinceYesterdayIsFlagged() {
        let app = launch(["-UITestTreesStaleShift"])
        let picker = app.buttons["marking-for"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let seeded = expectation(for: NSPredicate(format: "value ENDSWITH %@", "12 trees"), evaluatedWith: picker)
        XCTAssertEqual(XCTWaiter().wait(for: [seeded], timeout: 10), .completed)
        XCTAssertFalse((picker.value as? String)?.hasPrefix("Today") ?? true, "the shift began yesterday")

        let warning = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "You’ve been clocked in since ")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.hasSuffix(" at 7:00 AM. If you forgot to clock out, fix the times."), warning.label)
        let fix = app.buttons["trees-fix-times"]
        assertGloveSized(fix)
        fix.tap()
        XCTAssertTrue(app.navigationBars["Edit Shift"].waitForExistence(timeout: 5))
    }

    // MARK: Large text and gloves

    func testControlsAreGloveSized() {
        let app = launch(["-UITestTreesSeed"])
        XCTAssertTrue(app.buttons["map-row-1-7"].waitForExistence(timeout: 10))
        for id in ["marking-for", "trees-list-toggle", "trees-undo", "type-numbers"] + ["one", "fill", "erase", "notes"].map({ "mode-\($0)" })
            + ["all", "xs", "s", "m", "l"].map({ "zoom-\($0)" }) {
            assertGloveSized(app.buttons[id])
        }
    }

    func testTheMapStaysReachableAtTheLargestTextSize() {
        let app = launch(["-UITestTreesSeed"] + Self.largestText)
        let picker = app.buttons["marking-for"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let seeded = expectation(for: NSPredicate(format: "value CONTAINS %@", "24 trees"), evaluatedWith: picker)
        XCTAssertEqual(XCTWaiter().wait(for: [seeded], timeout: 10), .completed)
        for id in ["trees-list-toggle", "trees-undo"] { assertGloveSized(app.buttons[id]) }

        let row7 = app.buttons["map-row-1-7"]
        XCTAssertTrue(row7.waitForExistence(timeout: 10))
        reveal(row7)
        row7.tap()
        waitForMessage(app, "Marked 12 trees in Block 1, row 7. Tap the row number again to clear it.")
        tree(3, inRow: app.buttons["map-row-1-8"]).tap()
        waitForMessage(app, "Marked Block 1, row 8, tree 3.")
    }

    // MARK: Pictures for review

    func testScreenshotsOfTheTreesTab() {
        let app = launch(["-UITestTreesSeed"])
        XCTAssertTrue(app.buttons["map-row-1-7"].waitForExistence(timeout: 10))
        sleep(1)
        attach(app, "Trees – map")

        tree(4, inRow: app.buttons["map-row-1-7"]).press(forDuration: 0.8)
        XCTAssertTrue(app.staticTexts["tree-card-status"].waitForExistence(timeout: 5))
        sleep(1)
        attach(app, "Trees – tree card")
        app.buttons["tree-card-done"].tap()

        app.buttons["mode-fill"].tap()
        tree(3, inRow: app.buttons["map-row-1-8"]).tap()
        XCTAssertTrue(app.buttons["trees-message-action"].waitForExistence(timeout: 5))
        attach(app, "Trees – fill, first tree picked")
        app.buttons["trees-message-action"].tap()
        app.buttons["mode-one"].tap()

        app.buttons["type-numbers"].tap()
        XCTAssertTrue(app.textFields["type-fromRow"].waitForExistence(timeout: 5))
        app.textFields["type-fromRow"].typeText("12")
        app.buttons["type-mark"].tap()
        XCTAssertTrue(app.staticTexts["type-message"].waitForExistence(timeout: 5))
        attach(app, "Trees – type numbers")
        app.navigationBars.buttons["Done"].tap()

        app.buttons["marking-for"].tap()
        let yesterday = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "120 trees")).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        yesterday.tap()
        XCTAssertTrue(app.buttons["use-open-shift"].waitForExistence(timeout: 5))
        attach(app, "Trees – marking an earlier shift")
        app.buttons["use-open-shift"].tap()

        app.buttons["trees-list-toggle"].tap()
        XCTAssertTrue(app.buttons["row-1-5"].waitForExistence(timeout: 5))
        attach(app, "Trees – row list")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

private extension XCUIElement {
    func waitForSelection(timeout: TimeInterval) -> Bool {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter().wait(for: [selected], timeout: timeout) == .completed
    }
}
