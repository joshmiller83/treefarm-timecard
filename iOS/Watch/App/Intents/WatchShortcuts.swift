import AppIntents
import TreeFarmKit

// STUB: slice d replaces
//
// The watch app's own App Shortcuts (iPhone App Shortcuts don't run on the watch): the 10 in
// docs/watch.md 4.1. `WatchShiftModel` calls `WatchShortcuts.updateAppShortcutParameters()`
// whenever the first chip changes. Slice d writes the intents, test-first.

struct ClockInIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock In"
    /// The workout starts in the foreground, where WatchConnectivity is reachable.
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct WatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ClockInIntent(),
                    phrases: ["Clock in with \(.applicationName)", "Clock in in \(.applicationName)"],
                    shortTitle: "Clock In",
                    systemImageName: "leaf.fill")
    }
}
