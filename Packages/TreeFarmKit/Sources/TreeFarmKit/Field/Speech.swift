import Foundation

/// Wording shared by Siri, the lock screen and the app, so they always say the same thing.
public enum Speech {
    public static let notClockedIn = "You're not clocked in. Say \"clock in with Time Card\" first."
    public static let noSeason = "There's no active season. Ask an admin to start one."
    public static let noField = "There's no field set up yet. Add one in the Trees tab."
    public static let blockGone = "That block isn't on the map anymore."
    public static let emptyNote = "The note was empty, so nothing was saved."
    public static let nothingToUndo = "There's nothing to undo."

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

    /// "a", "a and b", "a, b and c"
    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}
