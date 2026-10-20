import Foundation

/// What the phone says when it won't apply a tap from the watch (docs/watch.md 1.3 step 4).
/// The watch shows these in its toast and keeps them in the Queue sheet for an hour, so each
/// names the tap and why, the way Siri would say it.
public enum WatchDeskSpeech {
    /// Taps made for another person (someone else was signed in on the phone meanwhile).
    public static func forSomeoneElse(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "These taps were for someone else, so they weren’t applied." }
        return "These taps were for \(name), so they weren’t applied."
    }

    /// Taps the watch made before it knew who was signed in.
    public static let beforeSignIn = "These taps were made before you signed in, so they weren’t applied."

    /// A queued clock-in from before the last shift ended.
    public static func clockInBeforeLastShift(tapped: Date, lastEnd: Date, calendar: FarmCalendar) -> String {
        "That clock-in at \(Fmt.spokenTime(tapped, calendar)) was before your last shift ended at \(Fmt.spokenTime(lastEnd, calendar)), so it wasn’t applied."
    }

    /// A shift tap made during a shift that has closed since. `start` is that shift's start,
    /// nil when the phone doesn't know the shift.
    public static func closedShift(_ command: FieldCommand, start: Date?, calendar: FarmCalendar) -> String {
        let shift = start.map { "the shift that started at \(Fmt.spokenTime($0, calendar))" } ?? "an earlier shift"
        switch command {
        case .markRow(let row):
            return "Row \(row.row + 1) was marked during \(shift), which is already closed, so it wasn’t applied. Fix it in the Log."
        case .markTrees(let row, _):
            return "Those trees in row \(row.row + 1) were marked during \(shift), which is already closed, so they weren’t applied. Fix it in the Log."
        case .cancelShift:
            return "That shift isn’t the one on the clock, so nothing was cancelled."
        default:
            return "\(capitalized(thing(command))) was for \(shift), which is already closed, so it wasn’t applied."
        }
    }

    /// A shift tap that arrived with no shift on the clock.
    public static func notClockedIn(_ command: FieldCommand) -> String {
        switch command {
        case .cancelShift: return "You’re not clocked in, so there was no clock-in to undo."
        default: return "You’re not clocked in, so \(thing(command)) wasn’t applied."
        }
    }

    /// "that clock-out", "that lunch", "row 14": the tap, as part of a sentence.
    static func thing(_ command: FieldCommand) -> String {
        switch command {
        case .clockIn: "that clock-in"
        case .clockOut: "that clock-out"
        case .startBreak(let kind, _): kind == .lunch ? "that lunch" : "that break"
        case .endBreak: "the end of that break"
        case .markRow(let row): "row \(row.row + 1)"
        case .markTrees(let row, _): "those trees in row \(row.row + 1)"
        case .addShiftNote: "that note"
        case .cancelShift: "that undo of the clock-in"
        case .markNextRow: "that row"
        case .moveTo: "that move"
        case .addTreeNote: "that tree note"
        case .changeStart: "that start time"
        case .undo: "that undo"
        }
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
