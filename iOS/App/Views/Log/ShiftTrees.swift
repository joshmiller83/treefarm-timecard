import Foundation
import TimeCardCore

/// Which trees each shift shaped, for the log, the report and the shift editor.
///
/// Marks are grouped by season and each season gets its own `MarkIndex`, so a shift from
/// last season still shows its trees, and when two phones claimed one tree only the winner
/// counts (the same rule the map uses).
struct ShiftTrees {
    private let indexes: [MarkIndex]
    private let blocks: [Block]
    private let marksByShift: [UUID: [TreeMark]]

    init(marks: some Sequence<TreeMark>, blocks: some Sequence<Block>) {
        let live = marks.filter(\.isLive)
        self.indexes = Dictionary(grouping: live, by: \.seasonId).values.map { MarkIndex(marks: $0) }
        self.blocks = blocks.filter { $0.deletedAt == nil }
        self.marksByShift = Dictionary(grouping: live, by: \.shiftId)
    }

    init(snapshot: FarmSnapshot) {
        self.init(marks: snapshot.marks.values, blocks: snapshot.blocks.values)
    }

    /// Trees the shift holds, inside today's blocks.
    func count(_ shiftId: UUID) -> Int {
        indexes.reduce(0) { $0 + $1.count(onShift: shiftId, blocks: blocks) }
    }

    /// The trees the shift holds, as marks.
    func marks(_ shiftId: UUID) -> [TreeMark] {
        indexes.flatMap { $0.marks(onShift: shiftId) }
    }

    /// "Block 1: rows 1–12, row 13 (trees 1–4)", or "" for none.
    func summary(_ shiftId: UUID) -> String {
        TreeSummary.text(marks: marks(shiftId), blocks: blocks)
    }

    /// One line per block the shift worked in, in walk order (fields by their own order).
    func byBlock(_ shiftId: UUID, fields: [Field]) -> [(block: Block, count: Int, text: String)] {
        let grouped = Dictionary(grouping: marks(shiftId), by: \.blockId)
        let worked = blocks.filter { grouped[$0.id] != nil }
        let fieldOrder = Dictionary(fields.map { ($0.id, ($0.sortOrder, $0.name)) }, uniquingKeysWith: { a, _ in a })
        let fieldIds = Set(worked.map(\.fieldId)).sorted { a, b in
            let fa = fieldOrder[a] ?? (Int.max, ""), fb = fieldOrder[b] ?? (Int.max, "")
            return fa != fb ? fa < fb : a.uuidString < b.uuidString
        }
        return fieldIds
            .flatMap { id in FieldWalker(blocks: worked.filter { $0.fieldId == id }).blocks }
            .compactMap { block in
                let marks = grouped[block.id] ?? []
                let count = marks.filter { block.contains($0.tree) }.count
                guard count > 0 else { return nil }
                return (block, count, TreeSummary.text(marks: marks, blocks: [block]))
            }
    }

    /// Every live mark recorded on the shift, which deleting the shift removes. This is every
    /// record, so a copy that lost a tree to another phone goes too.
    static func marksToDelete(onShift shiftId: UUID, in snapshot: FarmSnapshot) -> [TreeMark] {
        snapshot.marks.values.filter { $0.isLive && $0.shiftId == shiftId }
    }
}
