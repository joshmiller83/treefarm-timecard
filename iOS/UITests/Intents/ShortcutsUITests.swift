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
        save("3-clock-out-question", settledOn: "No")
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

    /// The demo farm, clocked in, with the Shortcuts app open on Time Card's page.
    private func clockedInInShortcuts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Clock"].waitForExistence(timeout: 15))
        try openTimeCardShortcuts()
        run("Clock In")
        _ = answer(startingWith: "Clocked in at")
        done()
    }

    /// "Mark a row" asks which row; a row more than 5 away is checked first, and "No" marks
    /// nothing. (Strings: VoiceText.whichRow, FieldEngine.confirmation, VoiceText.nothingMarked.)
    func testMarkARowFarAwayAsksAndNoMarksNothing() throws {
        try clockedInInShortcuts()
        run("Mark a Row")
        _ = answer(startingWith: "Which row?")
        let row11 = springboard.staticTexts["Row 11"].firstMatch
        XCTAssertTrue(row11.waitForExistence(timeout: 10))
        row11.tap()
        XCTAssertEqual(answer(startingWith: "Row 11 in block 1?"), "Row 11 in block 1? That’s 6 rows ahead.")
        save("mark-a-row-far")
        tapSystemButton(["No"])
        XCTAssertEqual(answer(startingWith: "Okay"), "Okay, nothing marked.")
        done()
    }

    /// "Note a tree" with a tree past the end of the row says so right away, before the note
    /// is dictated. (Strings: VoiceText.whichTree, Speech.treesRange.)
    func testNoteATreePastTheEndOfTheRow() throws {
        try clockedInInShortcuts()
        run("Note a tree")
        _ = answer(startingWith: "Which tree?")
        let field = springboard.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("13")
        tapSystemButton(["Done"])
        XCTAssertEqual(answer(startingWith: "Block 1 has"), "Block 1 has 12 trees in each row.")
        XCTAssertFalse(springboard.staticTexts["What’s the note?"].exists)
        done()
    }

    /// "Fix my start time" asks for the time on a wheel and moves the open shift's start.
    /// (Strings: VoiceText.whatTime, FieldEngine's "Start time changed to …".)
    func testFixMyStartTime() throws {
        try clockedInInShortcuts()
        run("Fix my start time")
        _ = answer(startingWith: "What time did you start?")
        let hours = springboard.pickerWheels.firstMatch
        XCTAssertTrue(hours.waitForExistence(timeout: 5))
        // An hour earlier on the wheel ("11 o’clock" → "10 o’clock").
        let shown = (hours.value as? String) ?? ""
        let hour = Int(shown.prefix { $0.isNumber }) ?? 12
        hours.adjust(toPickerWheelValue: "\(hour == 1 ? 12 : hour - 1)")
        tapSystemButton(["Done"])
        let reply = answer(startingWith: "Start time changed to")
        XCTAssertTrue(reply.hasSuffix("."), reply)
        save("fix-start")
        done()
    }

    /// Siri runs a command while the app isn't running: iOS starts the app's process for the
    /// intent alone, which opens the store and answers. Run with the demo farm switched on for
    /// processes iOS starts by itself:
    ///   xcrun simctl spawn <device> launchctl setenv UITEST_IN_MEMORY 1
    /// and TEST_RUNNER_COLD_LAUNCH=1; `launchctl unsetenv UITEST_IN_MEMORY` afterwards.
    func testAColdLaunchAnswersFromTheDemoFarm() throws {
        guard ProcessInfo.processInfo.environment["COLD_LAUNCH"] == "1" else {
            throw XCTSkip("Needs UITEST_IN_MEMORY set with simctl launchctl, and TEST_RUNNER_COLD_LAUNCH=1")
        }
        XCUIApplication().terminate()
        try openTimeCardShortcuts()
        run("What row am I on")
        XCTAssertEqual(answer(startingWith: "You’re on"), "You’re on block 1, row 5. Next are rows 6 and 7.")
        save("cold-launch")
        done()
    }

    // MARK: Driving the Shortcuts app
    //
    // Found by what the Shortcuts app names its pages and sections (accessibility identifiers
    // and labels), and scrolled until a tile sits between its own navigation bar and tab bar,
    // so it works at any text size, where tiles grow and pages get longer.

    /// The App Shortcuts page of an app is "<bundle id>_auto_shortcuts".
    private var timeCardPage: XCUIElement {
        shortcuts.otherElements.matching(NSPredicate(format: "identifier ENDSWITH '.timecard_auto_shortcuts'")).firstMatch
    }

    private func openTimeCardShortcuts() throws {
        shortcuts.activate()
        guard shortcuts.wait(for: .runningForeground, timeout: 10) else { throw XCTSkip("The Shortcuts app isn't available") }
        dismissLeftoverAnswer()
        if !timeCardPage.waitForExistence(timeout: 2) {
            // Back to All Shortcuts, where each app has a header button that opens its page.
            let library = shortcuts.tabBars.buttons["Library"].firstMatch
            if library.exists { library.tap() }
            let allShortcuts = shortcuts.otherElements["all_shortcuts_library"].firstMatch
            for _ in 0..<3 where !allShortcuts.exists {
                let back = shortcuts.navigationBars.buttons["BackButton"].firstMatch
                guard back.exists else { break }
                back.tap()
            }
            if !allShortcuts.waitForExistence(timeout: 5) {
                // The Library's top level lists All Shortcuts first.
                shortcuts.buttons["All Shortcuts"].firstMatch.tap()
            }
            XCTAssertTrue(allShortcuts.waitForExistence(timeout: 10), "no All Shortcuts page")
            let header = allShortcuts.buttons["Time Card"].firstMatch
            XCTAssertTrue(bringIntoView(header), "Time Card's App Shortcuts aren't in the Shortcuts app")
            header.tap()
            XCTAssertTrue(timeCardPage.waitForExistence(timeout: 10))
        }
    }

    /// Taps an App Shortcut tile by its title, on its icon (the same size at every text size).
    private func run(_ title: String) {
        let icon = timeCardPage.otherElements[title].firstMatch.buttons.firstMatch
        XCTAssertTrue(bringIntoView(icon), "no “\(title)” shortcut")
        icon.tap()
    }

    /// Scrolls the page until `element` exists and sits clear of the navigation and tab bars,
    /// from the top of the page if it isn't there yet (the page keeps its place between runs).
    /// Each look at the page reads its whole accessibility tree, which is slow at the largest
    /// text sizes, so the bars are read once and each step looks only at the element.
    private func bringIntoView(_ element: XCUIElement) -> Bool {
        let tabs = shortcuts.tabBars.firstMatch
        let screen = shortcuts.windows.firstMatch.frame.height
        let top = shortcuts.navigationBars.firstMatch.frame.maxY + 8
        let bottom = (tabs.exists ? tabs.frame.minY : screen) - 8
        func place() -> CGRect? { element.exists ? element.frame : nil }
        var frame = place()
        if frame == nil {
            for _ in 0..<6 { scroll(by: -0.5) }
            frame = place()
        }
        for _ in 0..<24 {
            guard let f = frame else {
                // Not loaded yet: further down.
                scroll(by: 0.4)
                frame = place()
                continue
            }
            if f.minY >= top && f.maxY <= bottom { return true }
            // Move it just past the bar it's under, with some room.
            let distance = f.minY < top ? -(top - f.minY + 40) : f.maxY - bottom + 40
            scroll(by: max(-0.5, min(0.5, distance / screen)))
            frame = place()
        }
        return false
    }

    /// Drags the page by a fraction of the screen: positive moves the content up.
    private func scroll(by fraction: CGFloat) {
        let from = shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let to = shortcuts.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55 - fraction))
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

    /// Closes whatever an earlier run left up: a question (Cancel) or an answer (Done).
    private func dismissLeftoverAnswer() {
        let cancel = springboard.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 1) { cancel.tap() }
        let button = springboard.buttons["Done"].firstMatch
        if button.waitForExistence(timeout: 1) { button.tap() }
    }

    /// Saves what's on screen once iOS's answer sheet has finished sliding up (its `button`,
    /// Done unless it's asking a question, can be tapped), so no shot is caught mid-animation.
    private func save(_ name: String, settledOn button: String = "Done") {
        let done = springboard.buttons[button].firstMatch
        let deadline = Date().addingTimeInterval(5)
        while !(done.exists && done.isHittable) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.6)
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
