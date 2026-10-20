import AppIntents
import TreeFarmKit

/// The watch app's own App Shortcuts: the ten in docs/watch.md 4.1 and the "Apple Watch"
/// section of docs/voice-test.md, word for word. iPhone App Shortcuts don't run on the watch,
/// and flexible matching is off there, so each phrase is said exactly as written: every one
/// ends in "in Time Card" and also exists with "with Time Card". An app may have ten.
///
/// "Mark row 14" phrases are filled from `WatchRowQuery.suggestedEntities()` (the first ten
/// chips), so `ShortcutParameterRefresher` refreshes them whenever the first chip changes.
struct WatchShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayGreen }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in in \(.applicationName)", "Clock in with \(.applicationName)",
                "Punch in in \(.applicationName)", "Punch in with \(.applicationName)",
                "Start work in \(.applicationName)", "Start work with \(.applicationName)",
                "Start my shift in \(.applicationName)", "Start my shift with \(.applicationName)",
            ],
            shortTitle: "Clock In",
            systemImageName: "leaf.fill")

        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out in \(.applicationName)", "Clock out with \(.applicationName)",
                "Punch out in \(.applicationName)", "Punch out with \(.applicationName)",
                "End my shift in \(.applicationName)", "End my shift with \(.applicationName)",
                "Stop work in \(.applicationName)", "Stop work with \(.applicationName)",
            ],
            shortTitle: "Clock Out",
            systemImageName: "stop.fill")

        AppShortcut(
            intent: TakeLunchIntent(),
            phrases: [
                "Take lunch in \(.applicationName)", "Take lunch with \(.applicationName)",
                "Start lunch in \(.applicationName)", "Start lunch with \(.applicationName)",
            ],
            shortTitle: "Lunch",
            systemImageName: "cup.and.saucer.fill")

        AppShortcut(
            intent: TakeBreakIntent(),
            phrases: [
                "Take a break in \(.applicationName)", "Take a break with \(.applicationName)",
                "Start a break in \(.applicationName)", "Start a break with \(.applicationName)",
            ],
            shortTitle: "Break",
            systemImageName: "pause.fill")

        AppShortcut(
            intent: BackToWorkIntent(),
            phrases: [
                "Back to work in \(.applicationName)", "Back to work with \(.applicationName)",
                "End my break in \(.applicationName)", "End my break with \(.applicationName)",
            ],
            shortTitle: "Back to Work",
            systemImageName: "play.fill")

        AppShortcut(
            intent: NextRowIntent(),
            phrases: [
                "Next row in \(.applicationName)", "Next row with \(.applicationName)",
                "Row done in \(.applicationName)", "Row done with \(.applicationName)",
                "Mark the next row in \(.applicationName)", "Mark the next row with \(.applicationName)",
            ],
            shortTitle: "Next Row",
            systemImageName: "checkmark")

        AppShortcut(
            intent: MarkRowIntent(),
            phrases: [
                "Mark \(\.$row) in \(.applicationName)", "Mark \(\.$row) with \(.applicationName)",
                "\(\.$row) done in \(.applicationName)", "\(\.$row) done with \(.applicationName)",
                "Mark a row in \(.applicationName)", "Mark a row with \(.applicationName)",
            ],
            shortTitle: "Mark a Row",
            systemImageName: "checkmark.circle")

        AppShortcut(
            intent: UndoIntent(),
            phrases: [
                "Undo in \(.applicationName)", "Undo with \(.applicationName)",
                "Undo that in \(.applicationName)", "Undo that with \(.applicationName)",
            ],
            shortTitle: "Undo",
            systemImageName: "arrow.uturn.backward")

        AppShortcut(
            intent: StatusIntent(),
            phrases: [
                "How long have I worked in \(.applicationName)", "How long have I worked with \(.applicationName)",
                "How many trees in \(.applicationName)", "How many trees with \(.applicationName)",
                "What row am I on in \(.applicationName)", "What row am I on with \(.applicationName)",
                "What's my pace in \(.applicationName)", "What's my pace with \(.applicationName)",
            ],
            shortTitle: "My Day",
            systemImageName: "clock")

        AppShortcut(
            intent: AddNoteIntent(),
            phrases: [
                "Add a note in \(.applicationName)", "Add a note with \(.applicationName)",
            ],
            shortTitle: "Add a Note",
            systemImageName: "note.text")
    }
}

/// Keeps "Mark row 14" phrases on the rows the watch shows: refreshes the App Shortcut
/// parameters whenever the first chip changes (`WatchShiftModel` calls `update` with every
/// displayed state). A later chip or a timer tick doesn't refresh.
@MainActor
final class ShortcutParameterRefresher {
    static let shared = ShortcutParameterRefresher()

    private let refresh: @MainActor () -> Void
    /// The first chip last seen: nil before any update, `.some(nil)` with no chip.
    private var lastFirst: RowChip??

    init(refresh: @escaping @MainActor () -> Void = { WatchShortcuts.updateAppShortcutParameters() }) {
        self.refresh = refresh
    }

    func update(_ displayed: WatchState?) {
        let first = displayed?.nextRows.first
        if case .some(let last) = lastFirst, last == first { return }
        lastFirst = .some(first)
        refresh()
    }
}
