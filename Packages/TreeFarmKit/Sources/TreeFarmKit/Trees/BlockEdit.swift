import Foundation

/// Rules for adding, resizing, moving and removing blocks. The app shows these
/// messages in the block editor and the server sends the same ones back.
public enum BlockEdit {
    /// Nil when the form is fine, else what to fix.
    public static func validate(name: String, rows: Int, treesPerRow: Int) -> String? {
        if let size = checkSize(rows: rows, treesPerRow: treesPerRow) { return size }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Give the block a name." }
        if trimmed.count > Limits.blockName { return "Block names can be up to \(Limits.blockName) characters." }
        return nil
    }

    /// Refuses a resize that would strand marks (from any season) or notes outside the new size.
    public static func checkResize(_ block: Block, rows: Int, treesPerRow: Int, marks: [TreeMark], notes: [TreeNote]) -> String? {
        if let size = checkSize(rows: rows, treesPerRow: treesPerRow) { return size }
        func outside(_ blockId: UUID, _ row: Int, _ position: Int) -> Bool {
            blockId == block.id && (row >= rows || position >= treesPerRow)
        }
        let lostMarks = marks.filter { $0.isLive && outside($0.blockId, $0.row, $0.position) }.count
        let lostNotes = notes.filter { $0.isLive && outside($0.blockId, $0.row, $0.position) }.count
        guard lostMarks + lostNotes > 0 else { return nil }
        return "\(things(lostMarks, lostNotes)) would fall outside that size. \(fix(lostMarks, lostNotes)) first, or keep the size."
    }

    /// Refuses to remove a block that still has marks (any season) or notes.
    public static func checkRemove(_ block: Block, marks: [TreeMark], notes: [TreeNote]) -> String? {
        let markCount = marks.filter { $0.isLive && $0.blockId == block.id }.count
        let noteCount = notes.filter { $0.isLive && $0.blockId == block.id }.count
        guard markCount + noteCount > 0 else { return nil }
        return "This block has \(things(markCount, noteCount)), so it can’t be removed. \(fix(markCount, noteCount)) first."
    }

    /// Where a new block goes: `.rightOf` a block (same strip, the next column),
    /// `.newRowBelow` the last strip, or `.first` (top left).
    public enum Placement: Equatable, Sendable {
        case rightOf(UUID)
        case newRowBelow
        case first
    }

    /// Gives `new` its grid spot and moves later blocks in its strip right only as far
    /// as needed (a gap in the column numbers absorbs the shift). Returns the new block
    /// first, then every other block whose spot changed. Deleted blocks never move.
    /// An unknown neighbor falls back to a new row below. Callers set `updatedAt`.
    public static func place(new: Block, _ placement: Placement, among blocks: [Block]) -> [Block] {
        let live = blocks.filter { $0.deletedAt == nil && $0.id != new.id }
        func strip(_ row: Int) -> [Block] {
            live.filter { $0.gridRow == row }.sorted(by: FieldWalker.walksBefore)
        }
        switch placement {
        case .rightOf(let id):
            guard let left = live.first(where: { $0.id == id }) else { return place(new: new, .newRowBelow, among: blocks) }
            let later = strip(left.gridRow).drop { $0.id != left.id }.dropFirst()
            return insert(new, row: left.gridRow, column: left.gridColumn + 1, before: Array(later))
        case .newRowBelow:
            return insert(new, row: (live.map(\.gridRow).max() ?? -1) + 1, column: 0, before: [])
        case .first:
            let top = live.map(\.gridRow).min() ?? 0
            let blocks = strip(top)
            return insert(new, row: top, column: min(0, blocks.first?.gridColumn ?? 0), before: blocks)
        }
    }

    private static func insert(_ new: Block, row: Int, column: Int, before later: [Block]) -> [Block] {
        var placed = new
        placed.gridRow = row
        placed.gridColumn = column
        var changed = [placed]
        var taken = column
        for var block in later {
            if block.gridColumn <= taken {
                block.gridColumn = taken + 1
                changed.append(block)
            }
            taken = block.gridColumn
        }
        return changed
    }

    // MARK: - Wording

    private static func checkSize(rows: Int, treesPerRow: Int) -> String? {
        if !Limits.blockRows.contains(rows) {
            return "Rows in block has to be a number from \(Limits.blockRows.lowerBound) to \(Limits.blockRows.upperBound)."
        }
        if !Limits.treesPerRow.contains(treesPerRow) {
            return "Trees per row has to be a number from \(Limits.treesPerRow.lowerBound) to \(Limits.treesPerRow.upperBound)."
        }
        return nil
    }

    /// "3 shaped trees", "1 tree note", "1 shaped tree and 2 tree notes".
    private static func things(_ marks: Int, _ notes: Int) -> String {
        let m = "\(marks) shaped tree\(marks == 1 ? "" : "s")"
        let n = "\(notes) tree note\(notes == 1 ? "" : "s")"
        if marks > 0 && notes > 0 { return "\(m) and \(n)" }
        return marks > 0 ? m : n
    }

    private static func fix(_ marks: Int, _ notes: Int) -> String {
        if marks > 0 && notes > 0 { return "Erase the trees and delete the notes" }
        let them = marks + notes == 1 ? "it" : "them"
        return marks > 0 ? "Erase \(them)" : "Delete \(them)"
    }
}
