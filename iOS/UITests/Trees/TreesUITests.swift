import XCTest

/// The Trees tab, offline on the demo farm (North Field: blocks 1–4 of 20 rows × 12 trees;
/// Sam shaped rows 1–4 of block 1). The map runs at size M in UI tests, so a tree sits
/// 26 points apart, its row's number 32 points to the left of the first tree's edge.
final class TreesUITests: XCTestCase {
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

    /// A tree on the map, found from its row's number.
    private func tree(_ position: Int, inRow rowNumber: XCUIElement) -> XCUICoordinate {
        rowNumber.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: 26 + 6 + (CGFloat(position) - 0.5) * 26, dy: 0))
    }

    // MARK: Marking

    func testMarkingARowFromTheMapAndUndoingIt() {
        let app = launch()
        clockIn(app)

        let row7 = app.buttons["map-row-1-7"]
        XCTAssertTrue(row7.waitForExistence(timeout: 5))
        XCTAssertEqual(row7.label, "Block 1, row 7")
        XCTAssertEqual(row7.value as? String, "Not shaped")

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
