import Foundation

/// What the map says after an edit, in the artifact's words. Pass the change the
/// matching `MarkOps` call returned.
public enum MarkMessages {
    public static let needShift = "Clock in or add a shift first. Trees are saved with a shift."
    public static let undid = "Undid your last change."
    public static let fillOneBlock = "Pick the first and last tree in the same block. Tap the first tree again to start over."

    /// A one-tree tap (one or erase mode). `shapedOn` is the day another shift shaped
    /// the tree, already formatted in the farm's time zone ("Oct 16").
    public static func tap(_ change: MarkChange, tree: TreeRef, block: Block, shapedOn: String? = nil) -> String {
        let label = block.label(tree)
        if !change.added.isEmpty { return "Marked \(label)." }
        if !change.removed.isEmpty { return "Unmarked \(label)." }
        if !change.skipped.isEmpty { return "\(label) was shaped on \(shapedOn ?? "another day")." }
        return "\(label) isn’t marked on this shift."
    }

    /// A tap on a row number.
    public static func rowTap(_ change: MarkChange, row: RowRef, block: Block, mode: TapMode) -> String {
        let label = block.label(row: row.row)
        if !change.removed.isEmpty { return "Cleared \(trees(change.removed.count)) from \(label)." }
        if !change.added.isEmpty { return "Marked \(trees(change.added.count)) in \(label). Tap the row number again to clear it." }
        return mode == .erase || change.skipped.isEmpty
            ? "Nothing in \(label) is marked on this shift."
            : "Every tree in \(label) was shaped on another day."
    }

    /// After a fill: "Marked 23 trees, from row 2, tree 3 to row 4, tree 5."
    public static func fill(_ change: MarkChange, from a: TreeRef, to b: TreeRef) -> String {
        guard !change.added.isEmpty else { return "Nothing new to mark there." }
        let (first, last) = (a.row, a.position) <= (b.row, b.position) ? (a, b) : (b, a)
        func spot(_ t: TreeRef) -> String { "row \(t.row + 1), tree \(t.position + 1)" }
        return "Marked \(trees(change.added.count)), from \(spot(first)) to \(spot(last))."
    }

    /// After typed row and tree numbers (`rows` 0-based, as passed to `MarkOps.range`).
    public static func range(_ change: MarkChange, block: Block, rows: ClosedRange<Int>, add: Bool) -> String {
        let n = add ? change.added.count : change.removed.count
        guard n > 0 else { return add ? "Those trees were already marked." : "None of those trees are marked on this shift." }
        let span = rows.count == 1 ? "row \(rows.lowerBound + 1)" : "rows \(rows.lowerBound + 1)–\(rows.upperBound + 1)"
        return "\(add ? "Marked" : "Unmarked") \(trees(n)) in \(block.displayName), \(span)."
    }

    /// Nil when typed numbers (0-based) fit the block, else what to fix.
    public static func checkRange(block: Block, rows: ClosedRange<Int>, positions: ClosedRange<Int>) -> String? {
        if rows.lowerBound < 0 || rows.upperBound >= block.rowCount {
            return "Rows in \(block.displayName) go from 1 to \(block.rowCount)."
        }
        if positions.lowerBound < 0 || positions.upperBound >= block.treesPerRow {
            return "Trees go from 1 to \(block.treesPerRow) in each row of \(block.displayName)."
        }
        return nil
    }

    static func trees(_ n: Int) -> String { "\(n) tree\(n == 1 ? "" : "s")" }
}
