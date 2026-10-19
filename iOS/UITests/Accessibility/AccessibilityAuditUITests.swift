import XCTest

/// Xcode's accessibility audit on every tab, at the default text size and at the largest
/// (AX XXXL), so regressions like a card that merges its button into text are caught.
/// Contrast runs on its own: the system's glass tab bar and navigation bars draw over (and
/// blur just beyond) whatever scrolls under them, which the audit reads as low contrast, so
/// issues on them are left out. The map's row numbers and trees are as dense as the field
/// (the zoom buttons and the row list are the large-target ways in), so their hit areas are
/// left out too. Everything else must pass.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    static let tabs = ["clock", "trees", "log", "report", "team"]
    static let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]

    override func setUp() async throws {
        continueAfterFailure = true
    }

    private func launch(tab: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory", "-UITestTab", tab] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        // Let the farm load and the first sync settle.
        Thread.sleep(forTimeInterval: 2)
        return app
    }

    /// The system's own bars, and elements drawn under them.
    private func isSystemChrome(_ issue: XCUIAccessibilityAuditIssue, in app: XCUIApplication) -> Bool {
        guard let element = issue.element else { return true }
        if element.elementType == .tabBar || element.elementType == .navigationBar { return true }
        let frame = element.frame
        let tabBar = app.tabBars.firstMatch.frame
        let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 60
        return frame.maxY > tabBar.minY - 30 || frame.minY < top
    }

    /// The map itself: one element per row number and tree, sized by the zoom, and its legend.
    private func isMap(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard issue.auditType == .hitRegion, let element = issue.element else { return false }
        return element.identifier.hasPrefix("map-") || element.label.hasPrefix("Legend:")
    }

    private func audit(_ app: XCUIApplication, _ name: String) throws {
        let general: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion, .trait, .elementDetection]
        try app.performAccessibilityAudit(for: general) { [self] issue in
            if isSystemChrome(issue, in: app) || isMap(issue) { return true }
            print("AUDIT \(name): \(issue.auditType) \(issue.compactDescription) — \(issue.element?.debugDescription.prefix(160) ?? "")")
            return false
        }
        try app.performAccessibilityAudit(for: .contrast) { [self] issue in
            if isSystemChrome(issue, in: app) { return true }
            print("AUDIT \(name) contrast: \(issue.compactDescription) — \(issue.element?.debugDescription.prefix(160) ?? "")")
            return false
        }
    }

    func testEveryTabAtTheDefaultSize() throws {
        for tab in Self.tabs {
            let app = launch(tab: tab)
            try audit(app, tab)
            app.terminate()
        }
    }

    func testEveryTabAtTheLargestSize() throws {
        for tab in Self.tabs {
            let app = launch(tab: tab, extra: Self.largest)
            try audit(app, "\(tab)-ax")
            app.terminate()
        }
    }
}
