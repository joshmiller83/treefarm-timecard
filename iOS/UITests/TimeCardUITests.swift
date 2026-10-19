import XCTest

final class TimeCardUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"] + extra
        app.launch()
        return app
    }

    /// Opens a tab, looking under "More" when the tab bar is full.
    private func openTab(_ name: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[name]
        if button.waitForExistence(timeout: 2) {
            button.tap()
            return
        }
        app.tabBars.buttons["More"].tap()
        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No \(name) tab")
        row.tap()
    }

    func testSignedInAdminSeesEveryTab() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["Clock"].waitForExistence(timeout: 10))
        for tab in ["Trees", "Log", "Report"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "missing \(tab)")
        }
        XCTAssertTrue(app.staticTexts["clock-farm-name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["clock-farm-name"].label, "Pine Hollow Tree Farm")

        openTab("Team", in: app)
        XCTAssertTrue(app.navigationBars["Team"].waitForExistence(timeout: 5))
    }

    func testSettingsShowsSyncStatusAndSignOut() {
        let app = launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        openTab("Settings", in: app)
        let summary = app.staticTexts["sync-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "All changes saved")
        XCTAssertTrue(app.staticTexts["Pine Hollow Tree Farm"].exists)

        let signOut = app.buttons["sign-out"]
        XCTAssertTrue(signOut.exists)
        signOut.tap()
        let confirm = app.sheets.buttons["Sign out"].exists ? app.sheets.buttons["Sign out"] : app.buttons["Sign out"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["sign-in-button"].waitForExistence(timeout: 5))
    }

    func testSignInWithTheDemoAccount() {
        let app = launch(["-UITestSignedOut"])
        let email = app.textFields["sign-in-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("demo@example.com")
        let password = app.secureTextFields["sign-in-password"]
        password.tap()
        password.typeText("demo-password")
        app.buttons["sign-in-button"].tap()
        XCTAssertTrue(app.tabBars.buttons["Clock"].waitForExistence(timeout: 10))
    }

    func testAWrongPasswordSaysSo() {
        let app = launch(["-UITestSignedOut"])
        let email = app.textFields["sign-in-email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("demo@example.com")
        let password = app.secureTextFields["sign-in-password"]
        password.tap()
        password.typeText("not it")
        app.buttons["sign-in-button"].tap()
        XCTAssertTrue(app.staticTexts["That email and password don't match."].waitForExistence(timeout: 5))
    }

    func testJoinAndResetScreensOpen() {
        let app = launch(["-UITestSignedOut"])
        let join = app.buttons["Join with an invite code"]
        XCTAssertTrue(join.waitForExistence(timeout: 10))
        join.tap()
        XCTAssertTrue(app.textFields["join-code"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let reset = app.buttons["I have a reset code"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        XCTAssertTrue(app.textFields["reset-code"].waitForExistence(timeout: 5))
    }
}
