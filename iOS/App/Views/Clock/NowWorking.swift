import Foundation
import TimeCardCore

/// The "Now working" card: where you are and the same next-row buttons as the lock screen.
/// It reads the lock screen's own `LiveSnapshot`, so the two never disagree.
struct NowWorking: Equatable {
    struct BlockChoice: Equatable, Identifiable {
        var id: UUID
        /// "Block 2"
        var title: String
        var fieldName: String
    }

    var fieldName: String
    /// "Block 1, row 3": the next open row. Nil when nothing is left.
    var place: String?
    /// Up to three rows, exactly as on the lock screen.
    var rows: [RowChip]
    /// Why there are no rows: no field yet, no blocks, or everything shaped.
    var done: String?
    /// On a break the row buttons rest: "Row 4 is next when you’re back."
    var waiting: String?
    var onBreak: Bool
    /// "Row 14 marked", for the line beside Undo.
    var lastAction: String?
    var canUndo: Bool
    var shiftTrees: Int
    var fieldShaped: Int
    var fieldTotal: Int
    /// Rounded, but never 100 until every tree is shaped.
    var fieldPercent: Int
    /// Every block on the farm in walk order, for "Move to another block".
    var blocks: [BlockChoice]

    /// Nil off the clock.
    init?(state: FieldState, live: LiveSnapshot?) {
        guard let live else { return nil }
        fieldName = live.fieldName
        rows = live.nextRows
        onBreak = live.phase != .working
        lastAction = live.lastAction
        canUndo = live.canUndo
        shiftTrees = live.shiftTrees
        fieldShaped = live.fieldShaped
        fieldTotal = live.fieldTotal
        fieldPercent = Self.percent(live.fieldShaped, of: live.fieldTotal)

        if let first = live.nextRows.first {
            place = "\(first.blockName), row \(first.row + 1)"
            done = nil
            waiting = onBreak ? "\(first.title) is next when you’re back." : nil
        } else {
            place = nil
            waiting = nil
            if let field = state.currentField {
                done = state.walker(for: field).blocks.isEmpty
                    ? "\(field.name) has no blocks yet. Add them in the Trees tab."
                    : "Every row in \(field.name) is shaped."
            } else {
                done = Speech.noField
            }
        }

        blocks = state.liveFields.flatMap { field in
            state.walker(for: field).blocks.map { BlockChoice(id: $0.id, title: Speech.blockTitle($0), fieldName: field.name) }
        }
    }

    /// Rows past the first one's block say which block they're in.
    func showsBlock(_ chip: RowChip) -> Bool {
        guard let first = rows.first else { return false }
        return chip.blockId != first.blockId
    }

    static func percent(_ shaped: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        if shaped >= total { return 100 }
        return min(99, Int((Double(shaped) / Double(total) * 100).rounded()))
    }
}

/// Off the clock, the field's progress stands in for "trees this shift".
struct FieldSummary: Equatable {
    var fieldName: String
    var shaped: Int
    var total: Int
    var percent: Int
    /// "1,104 of 8,540 trees shaped"
    var line: String

    /// Nil when the current field has no blocks yet.
    init?(state: FieldState) {
        guard let field = state.currentField else { return nil }
        let walker = state.walker(for: field)
        guard !walker.blocks.isEmpty else { return nil }
        let progress = walker.progress(index: state.index)
        fieldName = field.name
        shaped = progress.shaped
        total = progress.total
        percent = NowWorking.percent(progress.shaped, of: progress.total)
        line = "\(Fmt.count(progress.shaped)) of \(Fmt.plural(progress.total, "tree")) shaped"
    }
}
