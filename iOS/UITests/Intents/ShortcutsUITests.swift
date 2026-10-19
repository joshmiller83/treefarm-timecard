import XCTest

/// Runs Time Card's App Shortcuts the way iOS runs them for Siri: from the Shortcuts app,
/// through the system, into the app's process, with the answer shown by iOS itself.
///
/// The app is launched first with the demo farm (-UITestInMemory) and stays alive in the
/// background, so the intents iOS runs find that farm. Set SHOTS_DIR (TEST_RUNNER_SHOTS_DIR
/// for xcodebuild) to also save each answer as a PNG.
@MainActor
final class ShortcutsUITests: XCTestCase {
    let shortcuts = XCUIApplication(bundleIdentifier: "com.apple.shortcuts")
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        continueAfterFailure = false
    }

    /// A morning in the field, by voice command: clock in, mark rows, lunch, ask how it's
    /// going, then clock out, saying "no" the first time.
    func testAFieldDayThroughShortcuts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Clock"].waitForExistence(timeout: 15))
        try openTimeCardShortcuts()

        run("Clock In")
        expect(answer(startingWith: "Clocked in at"), endsWith: "You’re on block 1, row 5.")
        save("1-clock-in")
        done()

        run("Next Row")
        XCTAssertEqual(answer(startingWith: "Row 5 marked"), "Row 5 marked, 12 trees. Next is row 6.")
        done()

        // Row 6 is one of the rows Siri knows by name ("Mark row 6 in Time Card").
        run("Row 6")
        XCTAssertEqual(answer(startingWith: "Row 6 marked"), "Row 6 marked, 12 trees. Next is row 7.")
        done()

        run("Lunch")
        expect(answer(startingWith: "Lunch started at"), endsWith: ".")
        done()

        run("Back to Work")
        let back = answer(startingWith: "Back at")
        XCTAssertTrue(back.contains(". Lunch was "), back)
        done()

        run("How many trees")
        // "24 trees today…", or past midnight "No trees marked yet today…": the shift began yesterday.
        let trees = answer(containing: "You’re on block 1, row 7.")
        XCTAssertTrue(trees.hasPrefix("24 trees today") || trees.hasPrefix("No trees marked yet today"), trees)
        save("2-how-many-trees")
        done()

        // Clocking out always asks first. "No" keeps the shift going.
        run("Clock Out")
        let question = answer(startingWith: "You’ve worked")
        XCTAssertTrue(question.hasSuffix("Clock out?"), question)
        save("3-clock-out-question")
        tapSystemButton(["No"])
        XCTAssertEqual(answer(startingWith: "Okay"), "Okay, you’re still clocked in.")
        done()

        run("Clock Out")
        _ = answer(startingWith: "You’ve worked")
        tapSystemButton(["Clock out", "Clock Out"])
        expect(answer(startingWith: "Clocked out at"), endsWith: ", 24 trees.")
        save("4-clocked-out")
        done()
    }

    // MARK: Driving the Shortcuts app

    private func openTimeCardShortcuts() throws {
        shortcuts.activate()
        guard shortcuts.wait(for: .runningForeground, timeout: 10) else { throw XCTSkip("The Shortcuts app isn't available") }
        dismissLeftoverAnswer()
        if shortcuts.navigationBars["Time Card"].waitForExistence(timeout: 2) {
            for _ in 0..<4 { scroll(by: -0.4) }
            return
        }
        let library = shortcuts.buttons["Library"].firstMatch
        if library.exists { library.tap() }
        let back = shortcuts.navigationBars.buttons["BackButton"].firstMatch
        if back.exists, back.label == "All Shortcuts" || back.label == "Library" { back.tap() }
        let header = shortcuts.buttons["Time Card"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "Time Card's App Shortcuts aren't in the Shortcuts app")
        header.tap()
        XCTAssertTrue(shortcuts.navigationBars["Time Card"].waitForExistence(timeout: 10))
    }

    /// Taps an App Shortcut tile by its title, scrolling until it sits clear of the bars.
    private func run(_ title: String) {
        let tile = shortcuts.otherElements[title].firstMatch
        let screen = shortcuts.windows.firstMatch.frame
        func clear() -> Bool {
            tile.exists && tile.frame.minY > screen.minY + 240 && tile.frame.maxY < screen.maxY - 120
        }
        if !clear() {
            // From the top of the page, work down to the tile.
            for _ in 0..<5 { scroll(by: -0.45) }
            var tries = 0
            while !clear() && tries < 16 {
                scroll(by: tile.exists && tile.frame.minY <= screen.minY + 240 ? -0.15 : 0.25)
                tries += 1
            }
        }
        XCTAssertTrue(clear(), "no “\(title)” shortcut")
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    }

    /// Drags the page by a fraction of the screen: positive moves the content up.
    private func scroll(by fraction: CGFloat) {
        let from = shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let to = shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6 - fraction))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// The status card, as iOS draws it under Siri's answer. Run with the simulator in dark
    /// mode or with large text (xcrun simctl ui … appearance / content_size) to see those looks.
    func testTheStatusCardUnderSiri() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Clock"].waitForExistence(timeout: 15))
        try openTimeCardShortcuts()
        let look = ProcessInfo.processInfo.environment["LOOK"] ?? "default"

        run("Clock In")
        _ = answer(startingWith: "Clocked in at")
        done()
        run("Next Row")
        _ = answer(startingWith: "Row 5 marked")
        done()

        run("What row am I on")
        XCTAssertEqual(answer(startingWith: "You’re on"), "You’re on block 1, row 6. Next are rows 7 and 8.")
        save("where-\(look)")
        done()

        run("How long have I worked")
        _ = answer(containing: "this week.")
        save("hours-\(look)")
        done()
    }

    // MARK: Reading what iOS shows

    /// What iOS showed for the intent's dialog (drawn by the system, over the Shortcuts app).
    private func answer(startingWith prefix: String) -> String {
        answer(matching: NSPredicate(format: "label BEGINSWITH %@", prefix), described: "“\(prefix)…”")
    }

    private func answer(containing text: String) -> String {
        answer(matching: NSPredicate(format: "label CONTAINS %@", text), described: "“…\(text)…”")
    }

    private func answer(matching match: NSPredicate, described: String) -> String {
        let places = [springboard.staticTexts.matching(match).firstMatch, shortcuts.staticTexts.matching(match).firstMatch]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let found = places.first(where: \.exists) { return found.label }
            Thread.sleep(forTimeInterval: 0.5)
        }
        save("missing-answer")
        print("=== SYSTEM\n\(springboard.debugDescription)\n=== SHORTCUTS\n\(shortcuts.debugDescription)")
        XCTFail("iOS never showed \(described)")
        return ""
    }

    private func expect(_ answer: String, endsWith ending: String, line: UInt = #line) {
        XCTAssertTrue(answer.hasSuffix(ending), "“\(answer)” should end “\(ending)”", line: line)
    }

    private func tapSystemButton(_ labels: [String]) {
        for label in labels {
            let button = springboard.buttons[label].firstMatch
            if button.waitForExistence(timeout: 5) {
                button.tap()
                return
            }
        }
        XCTFail("no \(labels) button")
    }

    private func done() {
        let button = springboard.buttons["Done"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
        _ = button.waitForNonExistence(timeout: 5)
    }

    private func dismissLeftoverAnswer() {
        let button = springboard.buttons["Done"].firstMatch
        if button.waitForExistence(timeout: 1) { button.tap() }
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
