import Foundation

extension Block {
    /// The name people see and hear: a bare number reads "Block 2", anything else as typed ("North 3").
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Block" }
        return trimmed.allSatisfy { $0.isASCII && $0.isNumber } ? "Block \(trimmed)" : trimmed
    }

    /// "Block 2, row 14". `row` counts from 0.
    public func label(row: Int) -> String {
        "\(displayName), row \(row + 1)"
    }

    /// "Block 2, row 14, tree 3".
    public func label(_ tree: TreeRef) -> String {
        "\(label(row: tree.row)), tree \(tree.position + 1)"
    }
}

/// Walk order through one field: blocks by (gridRow, gridColumn, name), rows ascending.
/// This is the order a crew works and the order "next row" follows.
public struct FieldWalker: Sendable {
    /// Live blocks in walk order.
    public let blocks: [Block]
    private let firstRow: [Int]
    private let blockIndex: [UUID: Int]
    private let rowTotal: Int

    /// Pass ONE field's blocks. Deleted blocks are left out.
    public init(blocks: [Block]) {
        let live = blocks.filter { $0.deletedAt == nil }.sorted(by: Self.walksBefore)
        var starts: [Int] = []
        var total = 0
        for block in live {
            starts.append(total)
            total += max(0, block.rowCount)
        }
        self.blocks = live
        self.firstRow = starts
        self.rowTotal = total
        self.blockIndex = Dictionary(live.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public func block(_ id: UUID) -> Block? {
        blockIndex[id].map { blocks[$0] }
    }

    public func rows() -> [RowRef] {
        blocks.flatMap { b in (0..<max(0, b.rowCount)).map { RowRef(blockId: b.id, row: $0) } }
    }

    /// The next `count` rows that still have an unshaped tree, starting AT `from`
    /// (inclusive) and wrapping around once. `from == nil` starts at the field's
    /// first row; a row past the end of a shrunk block starts at the next block.
    /// Fewer than `count` near the end; empty when the field is done.
    public func nextRows(from: RowRef?, count: Int, index: MarkIndex) -> [RowRef] {
        guard count > 0, rowTotal > 0 else { return [] }
        let start = startIndex(from)
        var found: [RowRef] = []
        for step in 0..<rowTotal {
            let (block, row) = locate((start + step) % rowTotal)
            let ref = RowRef(blockId: block.id, row: row)
            if !index.isRowComplete(ref, block: block) {
                found.append(ref)
                if found.count == count { break }
            }
        }
        return found
    }

    /// The next row in walk order, crossing blocks. Nil at the very end or for a row not in the field.
    public func row(after row: RowRef) -> RowRef? {
        guard let i = blockIndex[row.blockId], blocks[i].contains(row) else { return nil }
        let next = firstRow[i] + row.row + 1
        guard next < rowTotal else { return nil }
        let (block, r) = locate(next)
        return RowRef(blockId: block.id, row: r)
    }

    /// "Block 2, row 14", or "North 3, row 14" for a named block.
    public func label(_ row: RowRef) -> String {
        block(row.blockId)?.label(row: row.row) ?? "Row \(row.row + 1)"
    }

    /// Trees shaped by anyone, and all trees, across the field's live blocks.
    public func progress(index: MarkIndex) -> (shaped: Int, total: Int) {
        blocks.reduce((shaped: 0, total: 0)) { sum, block in
            (sum.shaped + index.shapedCount(in: block), sum.total + max(0, block.treeCount))
        }
    }

    // MARK: - Walk positions

    static func walksBefore(_ a: Block, _ b: Block) -> Bool {
        if a.gridRow != b.gridRow { return a.gridRow < b.gridRow }
        if a.gridColumn != b.gridColumn { return a.gridColumn < b.gridColumn }
        let names = a.name.compare(b.name, options: [.numeric, .caseInsensitive])
        if names != .orderedSame { return names == .orderedAscending }
        return a.id.uuidString < b.id.uuidString
    }

    private func startIndex(_ from: RowRef?) -> Int {
        guard let from, let i = blockIndex[from.blockId] else { return 0 }
        let rows = max(0, blocks[i].rowCount)
        if from.row >= rows { return (firstRow[i] + rows) % rowTotal }
        return firstRow[i] + max(0, from.row)
    }

    /// The block and row at a position in the walk (0 ..< rowTotal).
    private func locate(_ flat: Int) -> (Block, Int) {
        var low = 0, high = firstRow.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if firstRow[mid] <= flat { low = mid } else { high = mid - 1 }
        }
        // Skip empty blocks that share a start with the next one.
        while low + 1 < firstRow.count, firstRow[low + 1] <= flat { low += 1 }
        return (blocks[low], flat - firstRow[low])
    }
}
