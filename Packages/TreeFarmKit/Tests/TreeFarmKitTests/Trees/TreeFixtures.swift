import Foundation
@testable import TreeFarmKit

/// Small builders for the tree tests. Ids are fixed so failures are easy to read.
enum TreeFixtures {
    static let fieldId = UUID(uuidString: "F1E1D000-0000-0000-0000-000000000001")!
    static let seasonId = UUID(uuidString: "5EA50000-0000-0000-0000-000000000001")!
    static let farmId = UUID(uuidString: "FA000000-0000-0000-0000-000000000001")!
    static let me = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let sam = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let myShift = UUID(uuidString: "5F000000-0000-0000-0000-000000000001")!
    static let samShift = UUID(uuidString: "5F000000-0000-0000-0000-000000000002")!
    static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "B10C0000-0000-0000-0000-%012d", n))!
    }

    static func block(_ n: Int, name: String? = nil, gridRow: Int = 0, gridColumn: Int? = nil, rows: Int = 5, trees: Int = 4,
                      direction: RowDirection = .across, deleted: Bool = false) -> Block {
        Block(id: id(n), fieldId: fieldId, name: name ?? String(n), gridRow: gridRow, gridColumn: gridColumn ?? n,
              rowCount: rows, treesPerRow: trees, direction: direction, updatedAt: t0, deletedAt: deleted ? t0 : nil)
    }

    static func mark(_ block: Block, _ row: Int, _ position: Int, shift: UUID = myShift, user: UUID = me,
                     at seconds: TimeInterval = 0, id markId: UUID = UUID(), deleted: Bool = false) -> TreeMark {
        TreeMark(id: markId, seasonId: seasonId, tree: TreeRef(blockId: block.id, row: row, position: position),
                 shiftId: shift, userId: user, markedAt: t0.addingTimeInterval(seconds), deletedAt: deleted ? t0 : nil)
    }

    /// Every tree in `rows` of `block`, on one shift.
    static func marks(_ block: Block, rows: ClosedRange<Int>, shift: UUID = myShift, user: UUID = me) -> [TreeMark] {
        rows.flatMap { r in (0..<block.treesPerRow).map { p in mark(block, r, p, shift: shift, user: user) } }
    }

    static func ctx(shift: UUID = myShift, user: UUID = me, at seconds: TimeInterval = 3600) -> MarkContext {
        MarkContext(shiftId: shift, userId: user, seasonId: seasonId, now: t0.addingTimeInterval(seconds))
    }

    static func tree(_ block: Block, _ row: Int, _ position: Int) -> TreeRef {
        TreeRef(blockId: block.id, row: row, position: position)
    }

    static func row(_ block: Block, _ row: Int) -> RowRef {
        RowRef(blockId: block.id, row: row)
    }
}
