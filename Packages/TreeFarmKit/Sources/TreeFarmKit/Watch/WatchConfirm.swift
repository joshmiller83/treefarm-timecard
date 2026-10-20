import Foundation

/// The watch's own copy of `FieldEngine.confirmation`, built from its `WatchState`, so it asks
/// the same question Siri would ("You've worked 7 hours 12 minutes today. Clock out?") with no
/// round trip, and still asks with the phone out of reach. Tests hold the two to the same text.
public enum WatchConfirm {
    /// How far from the next row a row can be before marking it asks first (in case of a mishearing).
    public static let farRows = 5

    public static func question(for command: FieldCommand, state: WatchState, now: Date) -> String? {
        switch command {
        case .clockOut:
            guard let snapshot = state.snapshot else { return nil }
            let worked = snapshot.phase == .working ? now.timeIntervalSince(snapshot.timerStart) : snapshot.workedSoFar
            let cal = state.calendar
            let stale = state.shiftStart.map { cal.dayKey($0) < cal.dayKey(now) } ?? (snapshot.workedLabel == "worked this shift")
            return "You’ve worked \(Fmt.spokenDuration(worked)) \(stale ? "this shift" : "today"). Clock out?"
        case .markRow(let row):
            guard let here = state.nextRows.first else { return nil }
            let herePhrase = WatchDisplay.blockPhrase(here.blockName)
            if here.blockId != row.blockId {
                let name = state.nextRows.first { $0.blockId == row.blockId }.map { WatchDisplay.blockPhrase($0.blockName) } ?? "another block"
                return "Row \(row.row + 1) in \(name)? You’re in \(herePhrase)."
            }
            let distance = row.row - here.row
            guard abs(distance) > farRows else { return nil }
            return "Row \(row.row + 1) in \(herePhrase)? That’s \(abs(distance)) rows \(distance > 0 ? "ahead" : "behind")."
        default:
            return nil
        }
    }
}
