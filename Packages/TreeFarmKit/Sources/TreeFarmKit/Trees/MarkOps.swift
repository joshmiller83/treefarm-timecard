import Foundation

/// How a tap on the map acts: one tree at a time, fill from one tree to another, or erase.
public enum TapMode: String, Sendable, CaseIterable {
    case one, fill, erase
}

/// Every way to mark or unmark trees. Each returns a `MarkChange` and changes nothing
/// itself. A tree held by another shift is never removed or overwritten: it comes
/// back in `skipped` so the caller can say who shaped it.
public enum MarkOps {
    /// Own mark → remove it; free tree → mark it; another shift's tree → skipped.
    public static func toggle(_ tree: TreeRef, ctx: MarkContext, index: MarkIndex) -> MarkChange {
        guard let held = index.mark(at: tree) else { return MarkChange(added: [newMark(tree, ctx)]) }
        return held.shiftId == ctx.shiftId ? MarkChange(removed: [erased(held, ctx)]) : MarkChange(skipped: [held])
    }

    /// Marks the free trees. Trees this shift already holds are left as they are.
    public static func mark(_ trees: [TreeRef], ctx: MarkContext, index: MarkIndex) -> MarkChange {
        var change = MarkChange()
        var seen = Set<TreeRef>()
        for tree in trees where seen.insert(tree).inserted {
            if let held = index.mark(at: tree) {
                if held.shiftId != ctx.shiftId { change.skipped.append(held) }
            } else {
                change.added.append(newMark(tree, ctx))
            }
        }
        return change
    }

    /// Removes this shift's marks on the trees and nobody else's.
    public static func unmark(_ trees: [TreeRef], ctx: MarkContext, index: MarkIndex) -> MarkChange {
        var change = MarkChange()
        var seen = Set<TreeRef>()
        for tree in trees where seen.insert(tree).inserted {
            guard let held = index.mark(at: tree) else { continue }
            if held.shiftId == ctx.shiftId {
                change.removed.append(erased(held, ctx))
            } else {
                change.skipped.append(held)
            }
        }
        return change
    }

    /// "Mark row 14" from the lock screen or Siri: every free tree in the row.
    public static func markRow(_ row: RowRef, block: Block, ctx: MarkContext, index: MarkIndex) -> MarkChange {
        mark(trees(in: row, block: block), ctx: ctx, index: index)
    }

    /// A tap on a row number. Erase mode, or a row with nothing free and some of this
    /// shift's trees, clears this shift's trees; otherwise it marks the free ones.
    public static func rowTap(_ row: RowRef, block: Block, mode: TapMode, ctx: MarkContext, index: MarkIndex) -> MarkChange {
        let trees = trees(in: row, block: block)
        let hasFree = trees.contains { index.mark(at: $0) == nil }
        let hasMine = trees.contains { index.mark(at: $0)?.shiftId == ctx.shiftId }
        if mode == .erase || (!hasFree && hasMine) {
            return unmark(trees, ctx: ctx, index: index)
        }
        return mark(trees, ctx: ctx, index: index)
    }

    /// Marks everything from one tree to the other, row by row the way you walk the
    /// block, whichever was tapped first. Trees in different blocks do nothing.
    public static func fillBetween(_ a: TreeRef, _ b: TreeRef, block: Block, ctx: MarkContext, index: MarkIndex) -> MarkChange {
        guard a.blockId == block.id, b.blockId == block.id else { return MarkChange() }
        let (first, last) = (a.row, a.position) <= (b.row, b.position) ? (a, b) : (b, a)
        var trees: [TreeRef] = []
        for row in clip(first.row...last.row, to: block.rowCount) {
            let from = row == first.row ? first.position : 0
            let to = row == last.row ? last.position : block.treesPerRow - 1
            guard from <= to else { continue }
            for position in clip(from...to, to: block.treesPerRow) {
                trees.append(TreeRef(blockId: block.id, row: row, position: position))
            }
        }
        return mark(trees, ctx: ctx, index: index)
    }

    /// Typed row and tree numbers (0-based here), clipped to the block.
    public static func range(block: Block, rows: ClosedRange<Int>, positions: ClosedRange<Int>, add: Bool,
                             ctx: MarkContext, index: MarkIndex) -> MarkChange {
        var trees: [TreeRef] = []
        for row in clip(rows, to: block.rowCount) {
            for position in clip(positions, to: block.treesPerRow) {
                trees.append(TreeRef(blockId: block.id, row: row, position: position))
            }
        }
        return add ? mark(trees, ctx: ctx, index: index) : unmark(trees, ctx: ctx, index: index)
    }

    static func trees(in row: RowRef, block: Block) -> [TreeRef] {
        guard block.contains(row) else { return [] }
        return (0..<block.treesPerRow).map { TreeRef(blockId: block.id, row: row.row, position: $0) }
    }

    /// The part of `range` inside `0..<count`, possibly empty.
    static func clip(_ range: ClosedRange<Int>, to count: Int) -> Range<Int> {
        let lower = max(0, range.lowerBound)
        let upper = min(count, range.upperBound + 1)
        return lower < upper ? lower..<upper : 0..<0
    }

    static func newMark(_ tree: TreeRef, _ ctx: MarkContext) -> TreeMark {
        TreeMark(seasonId: ctx.seasonId, tree: tree, shiftId: ctx.shiftId, userId: ctx.userId, markedAt: ctx.now)
    }

    static func erased(_ mark: TreeMark, _ ctx: MarkContext) -> TreeMark {
        var gone = mark
        gone.deletedAt = ctx.now
        gone.updatedAt = ctx.now
        return gone
    }
}
