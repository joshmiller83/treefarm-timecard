import AppIntents

/// The phrases Siri knows with no setup. Every phrase names the app (Siri requires it), and
/// each command has several everyday ways to say it, since a word Siri doesn't expect means
/// pulling a glove off.
///
/// iOS allows an app ten App Shortcuts, so the less frequent commands (notes, a few trees,
/// fixing the start time) share the last one through `FieldTask`, and the status questions
/// share one through `StatusTopic`. Every intent also appears in the Shortcuts app, where it
/// can be given any phrase or put on the Action button.
///
/// Phrases with a row, block or field in them are filled in from those entities' suggested
/// values; `SiriSuggestions` calls `updateAppShortcutParameters()` whenever they change, so
/// "Mark row 14" always covers the next ten open rows. A time can't be part of a phrase (App
/// Shortcut parameters can't be dates), so the start time is asked for. Every phrase is
/// listed in docs/voice-test.md.
struct TimeCardShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .grayGreen }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ClockInIntent(),
            phrases: [
                "Clock in with \(.applicationName)",
                "Clock in on \(.applicationName)",
                "Clock me in with \(.applicationName)",
                "Punch in with \(.applicationName)",
                "Start work with \(.applicationName)",
                "Start my shift with \(.applicationName)",
                "Start my shift in \(.applicationName)",
                "\(.applicationName) clock in",
                "Clock in at \(\.$field) with \(.applicationName)",
                "Start work at \(\.$field) with \(.applicationName)",
            ],
            shortTitle: "Clock In",
            systemImageName: "clock.badge.checkmark")

        AppShortcut(
            intent: ClockOutIntent(),
            phrases: [
                "Clock out with \(.applicationName)",
                "Clock out on \(.applicationName)",
                "Clock me out with \(.applicationName)",
                "Punch out with \(.applicationName)",
                "End my shift with \(.applicationName)",
                "End my shift in \(.applicationName)",
                "Stop work with \(.applicationName)",
                "I'm done for the day in \(.applicationName)",
                "\(.applicationName) clock out",
            ],
            shortTitle: "Clock Out",
            systemImageName: "clock.badge.xmark")

        AppShortcut(
            intent: TakeBreakIntent(),
            phrases: [
                "Take \(\.$kind) with \(.applicationName)",
                "Take \(\.$kind) in \(.applicationName)",
                "Start \(\.$kind) in \(.applicationName)",
                "Start \(\.$kind) with \(.applicationName)",
                "Go on \(\.$kind) with \(.applicationName)",
                "Going to \(\.$kind) in \(.applicationName)",
                "\(\.$kind) time in \(.applicationName)",
                // A break unless lunch is said.
                "Take a break with \(.applicationName)",
                "Start a break in \(.applicationName)",
                "Go on break with \(.applicationName)",
            ],
            shortTitle: "Take a Break",
            systemImageName: "cup.and.saucer")

        AppShortcut(
            intent: BackToWorkIntent(),
            phrases: [
                "Back to work with \(.applicationName)",
                "Back to work in \(.applicationName)",
                "End my break in \(.applicationName)",
                "End my break with \(.applicationName)",
                "End lunch in \(.applicationName)",
                "Lunch is over in \(.applicationName)",
                "Break's over in \(.applicationName)",
                "I'm back in \(.applicationName)",
                "\(.applicationName) back to work",
            ],
            shortTitle: "Back to Work",
            systemImageName: "figure.walk")

        AppShortcut(
            intent: NextRowIntent(),
            phrases: [
                "Next row in \(.applicationName)",
                "Next row with \(.applicationName)",
                "Row done in \(.applicationName)",
                "Row done with \(.applicationName)",
                "Done with this row in \(.applicationName)",
                "Finished the row in \(.applicationName)",
                "Mark the next row in \(.applicationName)",
                "\(.applicationName) next row",
                "\(.applicationName) row done",
            ],
            shortTitle: "Next Row",
            systemImageName: "arrow.down.to.line")

        AppShortcut(
            intent: MarkRowByNumberIntent(),
            phrases: [
                "Mark \(\.$row) in \(.applicationName)",
                "Mark \(\.$row) with \(.applicationName)",
                "Mark \(\.$row) done in \(.applicationName)",
                "\(\.$row) done in \(.applicationName)",
                "Shaped \(\.$row) in \(.applicationName)",
                "Finished \(\.$row) in \(.applicationName)",
                "Mark a row in \(.applicationName)",
                "Mark a row with \(.applicationName)",
            ],
            shortTitle: "Mark a Row",
            systemImageName: "checklist")

        AppShortcut(
            intent: MoveToBlockIntent(),
            phrases: [
                "I'm in \(\.$block) in \(.applicationName)",
                "I'm in \(\.$block) with \(.applicationName)",
                "Move to \(\.$block) in \(.applicationName)",
                "Go to \(\.$block) in \(.applicationName)",
                "Switch to \(\.$block) in \(.applicationName)",
                "Change blocks in \(.applicationName)",
                "Move to another block in \(.applicationName)",
            ],
            shortTitle: "Move to a Block",
            systemImageName: "square.grid.2x2")

        AppShortcut(
            intent: UndoIntent(),
            phrases: [
                "Undo in \(.applicationName)",
                "Undo with \(.applicationName)",
                "Undo that in \(.applicationName)",
                "Undo the last one in \(.applicationName)",
                "Take that back in \(.applicationName)",
                "\(.applicationName) undo",
            ],
            shortTitle: "Undo",
            systemImageName: "arrow.uturn.backward")

        AppShortcut(
            intent: AskTimeCardIntent(),
            phrases: [
                "\(\.$topic) in \(.applicationName)",
                "\(\.$topic) with \(.applicationName)",
                "\(\.$topic) on \(.applicationName)",
                "Ask \(.applicationName) \(\.$topic)",
                "\(.applicationName) status",
                "Check \(.applicationName)",
            ],
            shortTitle: "How's My Day",
            systemImageName: "chart.bar")

        AppShortcut(
            intent: FieldTaskIntent(),
            phrases: [
                "\(\.$task) in \(.applicationName)",
                "\(\.$task) with \(.applicationName)",
                "\(\.$task) on \(.applicationName)",
            ],
            shortTitle: "Notes and Fixes",
            systemImageName: "square.and.pencil")
    }
}
