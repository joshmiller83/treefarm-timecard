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
