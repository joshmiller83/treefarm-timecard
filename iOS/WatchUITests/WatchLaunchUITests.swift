import XCTest

/// Watch simulator UI tests (docs/watch.md 7.3). `-watchDemo` swaps in the app's own scripted
/// phone (the real FieldEngine on a demo farm), so every sentence on screen is the phone's.
/// `-watchPhoneAway` starts it out of reach.
class WatchUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor @discardableResult
    func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-watchDemo"] + arguments
        app.launch()
        self.app = app
        return app
    }

    @MainActor var primary: XCUIElement { app.buttons["primaryAction"] }

    @MainActor
    func waitFor(_ element: XCUIElement, label: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element) never read “\(label)” (it reads “\(element.exists ? element.label : "nothing")”)",
                       file: file, line: line)
    }

    @MainActor
    func waitFor(_ element: XCUIElement, labelBeginningWith prefix: String, timeout: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", prefix), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element) never began with “\(prefix)”", file: file, line: line)
    }

    @MainActor
    func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "\(element) never went away",
                       file: file, line: line)
    }

    /// A screenshot kept in the result bundle.
    @MainActor
    func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The toast's sentence, once one shows.
    @MainActor
    func toast(_ text: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let toast = app.descendants(matching: .any)["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: timeout), "no toast", file: file, line: line)
        waitFor(toast, label: text, timeout: timeout, file: file, line: line)
    }
}

final class WatchLaunchUITests: WatchUITestCase {
    @MainActor
    func testTheAppLaunchesOffTheClock() throws {
        launch()
        XCTAssertTrue(primary.waitForExistence(timeout: 30))
        waitFor(primary, label: "Clock in")
        snapshot("off-clock")
    }
}
