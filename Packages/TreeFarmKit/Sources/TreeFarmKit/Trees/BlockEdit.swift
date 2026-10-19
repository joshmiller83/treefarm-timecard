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
