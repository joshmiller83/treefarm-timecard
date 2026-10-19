import Foundation

/// Who holds each tree this season. Built from the live marks of ONE season;
/// the caller filters by season. When two live marks claim one tree (two
/// offline devices, say), the earliest `markedAt` wins and ties go to the
/// smaller id, so every device settles on the same owner.
public struct MarkIndex: Sendable {
    private var byRow: [RowRef: [Int: TreeMark]] = [:]
    private var byShift: [UUID: Set<TreeRef>] = [:]
    /// Live marks that lost a tree to an earlier claim, kept so the next in line takes the
    /// tree if the winner goes (only trees two phones marked offline have any).
    private var losers: [TreeRef: [TreeMark]] = [:]

    public init(marks: [TreeMark]) {
        for mark in marks where mark.isLive { insert(mark) }
    }

    /// Folds in a new version of one mark: a live one claims its tree (or waits behind an
    /// earlier claim), a deleted one lets go. The app's store keeps its index up to date this
    /// way instead of rebuilding it from thousands of marks on every read.
    public mutating func apply(_ mark: TreeMark) {
        if mark.isLive { insert(mark) } else { remove(mark) }
    }

    public func mark(at tree: TreeRef) -> TreeMark? {
        byRow[tree.rowRef]?[tree.position]
    }

    /// The shift's marks in tree order (block id, then row, then position).
    public func marks(onShift shiftId: UUID) -> [TreeMark] {
        (byShift[shiftId] ?? []).compactMap(mark(at:)).sorted { a, b in
            if a.blockId != b.blockId { return a.blockId.uuidString < b.blockId.uuidString }
            if a.row != b.row { return a.row < b.row }
            return a.position < b.position
        }
    }

    /// Trees on the shift that sit inside a live block's current bounds.
    public func count(onShift shiftId: UUID, blocks: [Block]) -> Int {
        let live = Dictionary(blocks.filter { $0.deletedAt == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return (byShift[shiftId] ?? []).reduce(0) { n, tree in
            n + (live[tree.blockId]?.contains(tree) == true ? 1 : 0)
        }
    }

    /// Trees shaped by anyone inside the block's current bounds.
    public func shapedCount(in block: Block) -> Int {
        (0..<max(0, block.rowCount)).reduce(0) { n, row in
            n + held(RowRef(blockId: block.id, row: row), treesPerRow: block.treesPerRow)
        }
    }

    /// Every position in the row is shaped, by anyone.
    public func isRowComplete(_ row: RowRef, block: Block) -> Bool {
        block.contains(row) && held(row, treesPerRow: block.treesPerRow) == block.treesPerRow
    }

    /// Positions in the row nobody has shaped yet. Empty for a row outside the block.
    public func freePositions(in row: RowRef, block: Block) -> [Int] {
        guard block.contains(row) else { return [] }
        let marks = byRow[row] ?? [:]
        return (0..<block.treesPerRow).filter { marks[$0] == nil }
    }

    /// A copy with the change's removals and additions applied. A removal only
    /// clears the tree if the index still holds that same mark.
    public func applying(_ change: MarkChange) -> MarkIndex {
        var next = self
        for mark in change.removed { next.remove(mark) }
        for mark in change.added where mark.isLive { next.insert(mark) }
        return next
    }

    // MARK: - Storage

    private func held(_ row: RowRef, treesPerRow: Int) -> Int {
        guard let marks = byRow[row] else { return 0 }
        if marks.count <= treesPerRow, marks.keys.allSatisfy({ (0..<treesPerRow).contains($0) }) { return marks.count }
        return marks.keys.filter { (0..<treesPerRow).contains($0) }.count
    }

    private mutating func insert(_ mark: TreeMark) {
        let row = mark.tree.rowRef
        if let current = byRow[row]?[mark.position] {
            if current.id != mark.id {
                guard Self.claim(mark, beats: current) else {
                    losers[mark.tree, default: []].removeAll { $0.id == mark.id }
                    losers[mark.tree, default: []].append(mark)
                    return
                }
                losers[mark.tree, default: []].append(current)
            }
            byShift[current.shiftId]?.remove(current.tree)
        }
        losers[mark.tree]?.removeAll { $0.id == mark.id }
        if losers[mark.tree]?.isEmpty == true { losers[mark.tree] = nil }
        byRow[row, default: [:]][mark.position] = mark
        byShift[mark.shiftId, default: []].insert(mark.tree)
    }

    private mutating func remove(_ mark: TreeMark) {
        let row = mark.tree.rowRef
        guard let current = byRow[row]?[mark.position], current.id == mark.id else {
            losers[mark.tree]?.removeAll { $0.id == mark.id }
            if losers[mark.tree]?.isEmpty == true { losers[mark.tree] = nil }
            return
        }
        byRow[row]?[mark.position] = nil
        if byRow[row]?.isEmpty == true { byRow[row] = nil }
        byShift[current.shiftId]?.remove(current.tree)
        // The next earliest claim on the tree takes it.
        if var waiting = losers[mark.tree], let next = waiting.min(by: { Self.claim($0, beats: $1) }) {
            waiting.removeAll { $0.id == next.id }
            losers[mark.tree] = waiting.isEmpty ? nil : waiting
            byRow[row, default: [:]][mark.position] = next
            byShift[next.shiftId, default: []].insert(next.tree)
        }
    }

    /// First commit wins: the earlier mark, then the smaller id.
    static func claim(_ a: TreeMark, beats b: TreeMark) -> Bool {
        if a.markedAt != b.markedAt { return a.markedAt < b.markedAt }
        return a.id.uuidString < b.id.uuidString
    }
}

/// Who is marking: the shift being marked and its owner, the active season, and the time.
public struct MarkContext: Sendable {
    public var shiftId: UUID
    public var userId: UUID
    public var seasonId: UUID
    public var now: Date

    public init(shiftId: UUID, userId: UUID, seasonId: UUID, now: Date) {
        self.shiftId = shiftId
        self.userId = userId
        self.seasonId = seasonId
        self.now = now
    }
}

/// What an edit did. `removed` marks come back with `deletedAt = now`, ready to sync.
/// `skipped` holds the marks of OTHER shifts on trees the edit left alone.
public struct MarkChange: Equatable, Sendable {
    public var added: [TreeMark]
    public var removed: [TreeMark]
    public var skipped: [TreeMark]

    public init(added: [TreeMark] = [], removed: [TreeMark] = [], skipped: [TreeMark] = []) {
        self.added = added
        self.removed = removed
        self.skipped = skipped
    }

    /// Nothing was added or removed. Skipped trees alone don't count as a change.
    public var isEmpty: Bool { added.isEmpty && removed.isEmpty }

    /// The change that undoes this one: removed marks come back live (same id and
    /// `markedAt`, `updatedAt = now`) and added marks are removed.
    public func inverse(now: Date) -> MarkChange {
        MarkChange(
            added: removed.map { var m = $0; m.deletedAt = nil; m.updatedAt = now; return m },
            removed: added.map { var m = $0; m.deletedAt = now; m.updatedAt = now; return m }
        )
    }
}
