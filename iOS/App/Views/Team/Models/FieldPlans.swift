import Foundation
import TimeCardCore

/// Adding, renaming and archiving fields. Archived fields drop out of the map's field
/// picker but keep their blocks, marks and notes, so they can come back.
enum FieldPlans {
    static func add(name: String, farmId: UUID, fields: [Field], now: Date) -> TeamEdit {
        if let problem = TeamErrors.nameProblem(name, thing: "field") { return .problem(problem) }
        let order = (fields.filter { $0.deletedAt == nil }.map(\.sortOrder).max() ?? -1) + 1
        let field = Field(farmId: farmId, name: trimmed(name), sortOrder: order, updatedAt: now.roundedToMillisecond)
        return .save([.field(field)])
    }

    static func rename(_ field: Field, to name: String, now: Date) -> TeamEdit {
        if let problem = TeamErrors.nameProblem(name, thing: "field") { return .problem(problem) }
        guard trimmed(name) != field.name else { return .unchanged }
        var renamed = field
        renamed.name = trimmed(name)
        return .save([.field(stamped(renamed, now))])
    }

    static func archive(_ field: Field, now: Date) -> TeamEdit {
        guard field.archivedAt == nil else { return .unchanged }
        var archived = field
        archived.archivedAt = now.roundedToMillisecond
        return .save([.field(stamped(archived, now))])
    }

    static func restore(_ field: Field, now: Date) -> TeamEdit {
        guard field.archivedAt != nil else { return .unchanged }
        var restored = field
        restored.archivedAt = nil
        return .save([.field(stamped(restored, now))])
    }

    /// Fields in their order: the ones in use, then the archived ones.
    static func sorted(_ fields: [Field]) -> (active: [Field], archived: [Field]) {
        let live = fields.filter { $0.deletedAt == nil }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        return (live.filter { $0.archivedAt == nil }, live.filter { $0.archivedAt != nil })
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A newer `updatedAt` than the stored copy, so last-writer-wins keeps this edit.
    private static func stamped(_ field: Field, _ now: Date) -> Field {
        var field = field
        field.updatedAt = max(now.roundedToMillisecond, field.updatedAt.addingTimeInterval(0.001))
        return field
    }
}

/// The block form: name, size and which way the rows run.
struct BlockDraft: Equatable {
    var name: String
    var rows: Int
    var treesPerRow: Int
    var direction: RowDirection

    init(name: String, rows: Int, treesPerRow: Int, direction: RowDirection) {
        self.name = name
        self.rows = rows
        self.treesPerRow = treesPerRow
        self.direction = direction
    }

    init(block: Block) {
        self.init(name: block.name, rows: block.rowCount, treesPerRow: block.treesPerRow, direction: block.direction)
    }
}

/// One answer to "where does the new block go?"
struct PlacementChoice: Identifiable, Equatable {
    var placement: BlockEdit.Placement
    var label: String

    var id: String {
        switch placement {
        case .rightOf(let id): "right-\(id.uuidString)"
        case .newRowBelow: "below"
        case .first: "first"
        }
    }
}

/// The block editor's plans. Every rule and sentence is TreeFarmKit's `BlockEdit`:
/// `validate` for the form, `place` for the grid spot, `checkResize` and `checkRemove`
/// so no shaped tree (from any season) or note is stranded.
enum BlockPlans {
    static let defaultRows = 20
    static let defaultTrees = 10

    /// The next free number: one past the highest numbered block ("1", "2", "Block 7"), else one past the count.
    static func nextName(_ blocks: [Block]) -> String {
        let live = blocks.filter { $0.deletedAt == nil }
        let numbers = live.compactMap { block -> Int? in
            let words = block.name.split(separator: " ")
            return words.last.flatMap { Int($0) }
        }
        return String(max(numbers.max() ?? 0, live.count) + 1)
    }

    /// Every block to sit beside, in walk order, then a new row below. An empty field has one spot.
    static func choices(_ blocks: [Block]) -> [PlacementChoice] {
        let walk = FieldWalker(blocks: blocks).blocks
        guard !walk.isEmpty else { return [PlacementChoice(placement: .first, label: "The first block")] }
        return walk.map { PlacementChoice(placement: .rightOf($0.id), label: "To the right of \($0.displayName)") }
            + [PlacementChoice(placement: .newRowBelow, label: "In a new row below")]
    }

    /// Right of the last block in walk order, or the first block.
    static func defaultPlacement(_ blocks: [Block]) -> BlockEdit.Placement {
        FieldWalker(blocks: blocks).blocks.last.map { .rightOf($0.id) } ?? .first
    }

    /// A new block's form: the next number, and the size of the block beside it (or the last one).
    static func newDraft(blocks: [Block], placement: BlockEdit.Placement) -> BlockDraft {
        let walk = FieldWalker(blocks: blocks).blocks
        var model = walk.last
        if case .rightOf(let id) = placement, let neighbor = walk.first(where: { $0.id == id }) { model = neighbor }
        return BlockDraft(name: nextName(blocks), rows: model?.rowCount ?? defaultRows,
                          treesPerRow: model?.treesPerRow ?? defaultTrees, direction: model?.direction ?? .across)
    }

    /// The new block and every block that moved over to make room, all stamped `now`.
    static func add(_ draft: BlockDraft, placement: BlockEdit.Placement, fieldId: UUID, blocks: [Block], now: Date) -> TeamEdit {
        if let problem = BlockEdit.validate(name: draft.name, rows: draft.rows, treesPerRow: draft.treesPerRow) {
            return .problem(problem)
        }
        let stamp = now.roundedToMillisecond
        let new = Block(fieldId: fieldId, name: trimmed(draft.name), gridRow: 0, gridColumn: 0, rowCount: draft.rows,
                        treesPerRow: draft.treesPerRow, direction: draft.direction, updatedAt: stamp)
        let placed = BlockEdit.place(new: new, placement, among: blocks.filter { $0.fieldId == fieldId })
        return .save(placed.map { block in
            var block = block
            block.updatedAt = max(stamp, block.updatedAt.addingTimeInterval(block.id == new.id ? 0 : 0.001))
            return .block(block)
        })
    }

    /// The block with the form applied, or why not (a bad size, or trees that would fall outside).
    static func update(_ block: Block, with draft: BlockDraft, marks: [TreeMark], notes: [TreeNote], now: Date) -> TeamEdit {
        if let problem = BlockEdit.validate(name: draft.name, rows: draft.rows, treesPerRow: draft.treesPerRow) {
            return .problem(problem)
        }
        if let problem = BlockEdit.checkResize(block, rows: draft.rows, treesPerRow: draft.treesPerRow, marks: marks, notes: notes) {
            return .problem(problem)
        }
        var saved = block
        saved.name = trimmed(draft.name)
        saved.rowCount = draft.rows
        saved.treesPerRow = draft.treesPerRow
        saved.direction = draft.direction
        guard saved != block else { return .unchanged }
        saved.updatedAt = max(now.roundedToMillisecond, block.updatedAt.addingTimeInterval(0.001))
        return .save([.block(saved)])
    }

    /// A soft delete, refused while the block holds shaped trees (any season) or notes.
    static func remove(_ block: Block, marks: [TreeMark], notes: [TreeNote], now: Date) -> TeamEdit {
        if let problem = BlockEdit.checkRemove(block, marks: marks, notes: notes) { return .problem(problem) }
        var removed = block
        removed.deletedAt = now.roundedToMillisecond
        removed.updatedAt = max(now.roundedToMillisecond, block.updatedAt.addingTimeInterval(0.001))
        return .save([.block(removed)])
    }

    /// The field as it would look with the form applied, for the mini map: a new block in
    /// its spot (the others moved over), or the edited block at its new size. Sizes are
    /// clamped to the allowed range so a half-typed number still draws.
    static func preview(blocks: [Block], draft: BlockDraft, editing: Block?, placement: BlockEdit.Placement?) -> (blocks: [Block], highlight: UUID) {
        let rows = min(max(draft.rows, Limits.blockRows.lowerBound), Limits.blockRows.upperBound)
        let trees = min(max(draft.treesPerRow, Limits.treesPerRow.lowerBound), Limits.treesPerRow.upperBound)
        var live = blocks.filter { $0.deletedAt == nil }
        if let editing {
            if let i = live.firstIndex(where: { $0.id == editing.id }) {
                live[i].rowCount = rows
                live[i].treesPerRow = trees
                live[i].direction = draft.direction
                live[i].name = draft.name
            }
            return (live, editing.id)
        }
        let ghost = Block(id: previewID, fieldId: live.first?.fieldId ?? UUID(), name: draft.name, gridRow: 0, gridColumn: 0,
                          rowCount: rows, treesPerRow: trees, direction: draft.direction)
        let placed = BlockEdit.place(new: ghost, placement ?? defaultPlacement(live), among: live)
        for block in placed {
            if let i = live.firstIndex(where: { $0.id == block.id }) { live[i] = block } else { live.append(block) }
        }
        return (live, ghost.id)
    }

    /// The new block's id in previews.
    static let previewID = UUID(uuidString: "00000000-0000-0000-0000-00000000B10C")!

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
