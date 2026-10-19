import Foundation
import Testing
@testable import TreeFarmKit

@Suite("MarkOps: single trees")
struct MarkOpsTreeTests {
    typealias F = TreeFixtures
    let b1 = F.block(1, rows: 5, trees: 4)

    @Test func togglingAFreeTreeMarksItOnTheShift() throws {
        let ctx = F.ctx()
        let change = MarkOps.toggle(F.tree(b1, 2, 1), ctx: ctx, index: MarkIndex(marks: []))
        let added = try #require(change.added.first)
        #expect(change.added.count == 1)
        #expect(change.removed.isEmpty && change.skipped.isEmpty)
        #expect(added.tree == F.tree(b1, 2, 1))
        #expect(added.shiftId == ctx.shiftId)
        #expect(added.userId == ctx.userId)
        #expect(added.seasonId == ctx.seasonId)
        #expect(added.markedAt == ctx.now)
        #expect(added.updatedAt == ctx.now)
        #expect(added.isLive)
    }

    @Test func togglingMyOwnMarkRemovesIt() throws {
        let mine = F.mark(b1, 2, 1)
        let ctx = F.ctx()
        let change = MarkOps.toggle(mine.tree, ctx: ctx, index: MarkIndex(marks: [mine]))
        let removed = try #require(change.removed.first)
        #expect(change.added.isEmpty)
        #expect(removed.id == mine.id)
        #expect(removed.deletedAt == ctx.now)
        #expect(removed.updatedAt == ctx.now)
        #expect(removed.markedAt == mine.markedAt)
    }

    @Test func anotherShiftsTreeIsSkippedNotTouched() {
        let sams = F.mark(b1, 2, 1, shift: F.samShift, user: F.sam)
        let change = MarkOps.toggle(sams.tree, ctx: F.ctx(), index: MarkIndex(marks: [sams]))
        #expect(change.isEmpty)
        #expect(change.skipped == [sams])
    }

    @Test func myEarlierShiftCountsAsAnotherShift() {
        let yesterday = F.mark(b1, 0, 0, shift: UUID(), user: F.me)
        let change = MarkOps.toggle(yesterday.tree, ctx: F.ctx(), index: MarkIndex(marks: [yesterday]))
        #expect(change.isEmpty)
        #expect(change.skipped == [yesterday])
    }

    @Test func markAddsOnlyFreeTrees() {
        let mine = F.mark(b1, 0, 0)
        let sams = F.mark(b1, 0, 1, shift: F.samShift, user: F.sam)
        let trees = [F.tree(b1, 0, 0), F.tree(b1, 0, 1), F.tree(b1, 0, 2), F.tree(b1, 0, 2), F.tree(b1, 0, 3)]
        let change = MarkOps.mark(trees, ctx: F.ctx(), index: MarkIndex(marks: [mine, sams]))
        #expect(change.added.map(\.tree) == [F.tree(b1, 0, 2), F.tree(b1, 0, 3)])
        #expect(change.removed.isEmpty)
        #expect(change.skipped == [sams])
    }

    @Test func unmarkRemovesOnlyThisShiftsMarks() {
        let mine = F.mark(b1, 0, 0)
        let sams = F.mark(b1, 0, 1, shift: F.samShift, user: F.sam)
        let trees = [F.tree(b1, 0, 0), F.tree(b1, 0, 1), F.tree(b1, 0, 2)]
        let change = MarkOps.unmark(trees, ctx: F.ctx(), index: MarkIndex(marks: [mine, sams]))
        #expect(change.removed.map(\.id) == [mine.id])
        #expect(change.added.isEmpty)
        #expect(change.skipped == [sams])
    }

    @Test func nothingToDoIsEmpty() {
        #expect(MarkOps.mark([], ctx: F.ctx(), index: MarkIndex(marks: [])).isEmpty)
        #expect(MarkOps.unmark([F.tree(b1, 0, 0)], ctx: F.ctx(), index: MarkIndex(marks: [])).isEmpty)
    }

    @Test func inverseOfAMixedChangeUndoesIt() throws {
        let mine = F.mark(b1, 1, 0, at: 10)
        let sams = F.mark(b1, 1, 1, shift: F.samShift, user: F.sam)
        let before = MarkIndex(marks: [mine, sams])
        let ctx = F.ctx(at: 100)
        // Erase my tree, then mark two more in one change.
        let erase = MarkOps.unmark([mine.tree], ctx: ctx, index: before)
        let add = MarkOps.mark([F.tree(b1, 1, 2), F.tree(b1, 1, 3), sams.tree], ctx: ctx, index: before.applying(erase))
        let mixed = MarkChange(added: add.added, removed: erase.removed, skipped: add.skipped)
        let after = before.applying(mixed)
        #expect(after.mark(at: mine.tree) == nil)
        #expect(after.marks(onShift: F.myShift).count == 2)

        let later = F.t0.addingTimeInterval(200)
        let undo = mixed.inverse(now: later)
        #expect(undo.skipped.isEmpty)
        let back = try #require(undo.added.first)
        #expect(undo.added.count == 1)
        #expect(back.id == mine.id)
        #expect(back.deletedAt == nil)
        #expect(back.markedAt == mine.markedAt)
        #expect(back.updatedAt == later)
        #expect(Set(undo.removed.map(\.id)) == Set(add.added.map(\.id)))
        #expect(undo.removed.allSatisfy { $0.deletedAt == later && $0.updatedAt == later })

        let restored = after.applying(undo)
        #expect(restored.mark(at: mine.tree)?.id == mine.id)
        #expect(restored.mark(at: sams.tree) == sams)
        #expect(restored.marks(onShift: F.myShift).map(\.tree) == [mine.tree])
    }
}
