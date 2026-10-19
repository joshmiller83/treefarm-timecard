import Foundation

/// Wording shared by Siri, the lock screen and the app, so they always say the same thing.
public enum Speech {
    public static let notClockedIn = "You’re not clocked in. Say \"clock in with Time Card\" first."
    public static let noSeason = "There’s no active season. Ask an admin to start one."
    public static let noField = "There’s no field set up yet. Add one in the Trees tab."
    public static let blockGone = "That block isn’t on the map anymore."
    public static let emptyNote = "The note was empty, so nothing was saved."
    public static let nothingToUndo = "There’s nothing to undo."
    /// What the undo would put back was changed since (in the Log, by an admin, or by sync).
    public static let undoChanged = "That changed since, so it can’t be undone."
    /// The phone couldn't write the change (the app, Siri and the lock screen say the same).
    public static let saveFailed = "Couldn’t save that on this phone. Try again."

    /// A shift left open from an earlier day: "You’ve been clocked in since Sat, Oct 17 at 7:00 AM."
    public static func clockedInSince(_ shift: Shift, calendar: FarmCalendar) -> String {
        "You’ve been clocked in since \(Fmt.day(shift.start, calendar)) at \(Fmt.time(shift.start, calendar))."
    }

    /// Clocking out a shift left open more than `Limits.maxShift`: the server would refuse it,
    /// so the clock-out time is set in the Log instead.
    public static func tooLongToClockOut(_ shift: Shift, calendar: FarmCalendar) -> String {
        "\(clockedInSince(shift, calendar: calendar)) A shift can’t be longer than 24 hours, so set the clock-out time in the Log."
    }

    /// Follows `clockedInSince` where the times can be fixed.
    public static let fixTheTimes = "If you forgot to clock out, fix the times."

    /// "Block 2" for short names like "2" or "A"; longer names ("North 3") as they are.
    public static func blockTitle(_ block: Block) -> String {
        let name = block.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return "Block" }
        if name.count <= 3 && !name.contains(" ") { return "Block \(name)" }
        return name
    }

    /// The same, mid-sentence: "block 2".
    public static func blockPhrase(_ block: Block) -> String {
        let title = blockTitle(block)
        return title.hasPrefix("Block ") ? "block" + title.dropFirst("Block".count) : title
    }

    /// "block 2, row 14"
    public static func place(_ row: RowRef, _ block: Block) -> String {
        "\(blockPhrase(block)), row \(row.row + 1)"
    }

    /// A row named relative to another: "row 15" in the same block, "block 3, row 1" in another.
    public static func relative(_ row: RowRef, from other: RowRef?, blocks: (UUID) -> Block?) -> String {
        if row.blockId == other?.blockId { return "row \(row.row + 1)" }
        guard let b = blocks(row.blockId) else { return "row \(row.row + 1)" }
        return place(row, b)
    }

    public static func rowsRange(_ block: Block) -> String {
        "\(blockTitle(block)) has rows 1 to \(block.rowCount)."
    }

    public static func treesRange(_ block: Block) -> String {
        "\(blockTitle(block)) has \(block.treesPerRow) \(block.treesPerRow == 1 ? "tree" : "trees") in each row."
    }

    /// Trees an hour, said aloud: whole numbers from 10 up, one decimal below.
    public static func rate(_ x: Double) -> String {
        guard x.isFinite, x > 0 else { return "0" }
        if x >= 10 { return String(Int(x.rounded())) }
        let one = (x * 10).rounded() / 10
        return one == one.rounded() ? String(Int(one)) : String(format: "%.1f", one)
    }

    /// The first sentence, which is all the lock screen has room for. A stop inside quotes
    /// (straight or curly) doesn't end it:
    /// "Row 14 was shaped by Sam on Oct 16. Next open row is 15." → "Row 14 was shaped by Sam on Oct 16."
    public static func firstSentence(_ text: String) -> String {
        var quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "\"" { quoted.toggle() } else if ch == "“" { quoted = true } else if ch == "”" { quoted = false }
            let next = text.index(after: index)
            if !quoted, ".?!".contains(ch), next == text.endIndex || text[next] == " " {
                return String(text[...index])
            }
            index = next
        }
        return text
    }

    /// "a", "a and b", "a, b and c"
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
