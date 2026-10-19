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

@Suite("MarkOps: rows, fills and ranges")
struct MarkOpsRowTests {
    typealias F = TreeFixtures
    let b1 = F.block(1, rows: 5, trees: 4)
    let b2 = F.block(2, rows: 3, trees: 3)

    @Test func markRowTakesEveryFreeTree() {
        let sams = F.mark(b1, 2, 1, shift: F.samShift, user: F.sam)
        let mine = F.mark(b1, 2, 3)
        let change = MarkOps.markRow(F.row(b1, 2), block: b1, ctx: F.ctx(), index: MarkIndex(marks: [sams, mine]))
        #expect(change.added.map(\.position) == [0, 2])
        #expect(change.added.allSatisfy { $0.row == 2 && $0.blockId == b1.id })
        #expect(change.removed.isEmpty)
        #expect(change.skipped == [sams])
    }

    @Test func markRowOutsideTheBlockDoesNothing() {
        #expect(MarkOps.markRow(F.row(b1, 5), block: b1, ctx: F.ctx(), index: MarkIndex(marks: [])).isEmpty)
        #expect(MarkOps.markRow(F.row(b2, 0), block: b1, ctx: F.ctx(), index: MarkIndex(marks: [])).isEmpty)
    }

    @Test func markRowOnAFullRowIsEmpty() {
        let index = MarkIndex(marks: F.marks(b1, rows: 1...1, shift: F.samShift, user: F.sam))
        let change = MarkOps.markRow(F.row(b1, 1), block: b1, ctx: F.ctx(), index: index)
        #expect(change.isEmpty)
        #expect(change.skipped.count == 4)
    }

    @Test func rowTapMarksTheFreeTrees() {
        let index = MarkIndex(marks: [F.mark(b1, 0, 0), F.mark(b1, 0, 1, shift: F.samShift)])
        let change = MarkOps.rowTap(F.row(b1, 0), block: b1, mode: .one, ctx: F.ctx(), index: index)
        #expect(change.added.map(\.position) == [2, 3])
        #expect(change.removed.isEmpty)
        #expect(change.skipped.map(\.position) == [1])
    }

    @Test func rowTapOnARowIAlreadyFinishedClearsMine() {
        let index = MarkIndex(marks: [F.mark(b1, 0, 0), F.mark(b1, 0, 1), F.mark(b1, 0, 2, shift: F.samShift), F.mark(b1, 0, 3)])
        let change = MarkOps.rowTap(F.row(b1, 0), block: b1, mode: .one, ctx: F.ctx(), index: index)
        #expect(change.added.isEmpty)
        #expect(change.removed.map(\.position) == [0, 1, 3])
        #expect(change.skipped.map(\.position) == [2])
    }

    @Test func rowTapInFillModeActsLikeOne() {
        let change = MarkOps.rowTap(F.row(b1, 4), block: b1, mode: .fill, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(change.added.count == 4)
    }

    @Test func rowTapInEraseModeOnlyClears() {
        let index = MarkIndex(marks: [F.mark(b1, 0, 0), F.mark(b1, 0, 1, shift: F.samShift)])
        let change = MarkOps.rowTap(F.row(b1, 0), block: b1, mode: .erase, ctx: F.ctx(), index: index)
        #expect(change.added.isEmpty)
        #expect(change.removed.map(\.position) == [0])
        #expect(change.skipped.map(\.position) == [1])
        let empty = MarkOps.rowTap(F.row(b1, 3), block: b1, mode: .erase, ctx: F.ctx(), index: index)
        #expect(empty.isEmpty)
    }

    @Test func rowTapOnARowSomeoneElseFinishedDoesNothing() {
        let index = MarkIndex(marks: F.marks(b1, rows: 2...2, shift: F.samShift, user: F.sam))
        let change = MarkOps.rowTap(F.row(b1, 2), block: b1, mode: .one, ctx: F.ctx(), index: index)
        #expect(change.isEmpty)
        #expect(change.skipped.count == 4)
    }

    @Test func fillBetweenWalksRowByRow() {
        let change = MarkOps.fillBetween(F.tree(b1, 1, 2), F.tree(b1, 3, 1), block: b1, ctx: F.ctx(), index: MarkIndex(marks: []))
        let trees = change.added.map { [$0.row, $0.position] }
        #expect(trees == [[1, 2], [1, 3], [2, 0], [2, 1], [2, 2], [2, 3], [3, 0], [3, 1]])
    }

    @Test func fillBetweenWorksInEitherTapOrder() {
        let index = MarkIndex(marks: [])
        let forward = MarkOps.fillBetween(F.tree(b1, 1, 2), F.tree(b1, 3, 1), block: b1, ctx: F.ctx(), index: index)
        let backward = MarkOps.fillBetween(F.tree(b1, 3, 1), F.tree(b1, 1, 2), block: b1, ctx: F.ctx(), index: index)
        #expect(forward.added.map(\.tree) == backward.added.map(\.tree))
        let sameRow = MarkOps.fillBetween(F.tree(b1, 0, 3), F.tree(b1, 0, 1), block: b1, ctx: F.ctx(), index: index)
        #expect(sameRow.added.map(\.position) == [1, 2, 3])
    }

    @Test func fillBetweenOneTreeMarksIt() {
        let change = MarkOps.fillBetween(F.tree(b1, 2, 2), F.tree(b1, 2, 2), block: b1, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(change.added.map(\.tree) == [F.tree(b1, 2, 2)])
    }

    @Test func fillBetweenSkipsOtherShiftsTrees() {
        let sams = F.mark(b1, 2, 0, shift: F.samShift, user: F.sam)
        let change = MarkOps.fillBetween(F.tree(b1, 1, 3), F.tree(b1, 2, 1), block: b1, ctx: F.ctx(), index: MarkIndex(marks: [sams]))
        #expect(change.added.map(\.tree) == [F.tree(b1, 1, 3), F.tree(b1, 2, 1)])
        #expect(change.skipped == [sams])
    }

    @Test func fillBetweenDifferentBlocksIsEmpty() {
        let index = MarkIndex(marks: [])
        #expect(MarkOps.fillBetween(F.tree(b1, 0, 0), F.tree(b2, 1, 1), block: b1, ctx: F.ctx(), index: index).isEmpty)
        #expect(MarkOps.fillBetween(F.tree(b2, 0, 0), F.tree(b2, 1, 1), block: b1, ctx: F.ctx(), index: index).isEmpty)
    }

    @Test func fillBetweenStaysInsideTheBlock() {
        let change = MarkOps.fillBetween(F.tree(b1, 4, 2), F.tree(b1, 7, 9), block: b1, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(change.added.map(\.tree) == [F.tree(b1, 4, 2), F.tree(b1, 4, 3)])
    }

    @Test func rangeMarksARectangle() {
        let change = MarkOps.range(block: b1, rows: 1...2, positions: 0...1, add: true, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(change.added.map { [$0.row, $0.position] } == [[1, 0], [1, 1], [2, 0], [2, 1]])
    }

    @Test func rangeUnmarksOnlyMine() {
        let sams = F.mark(b1, 1, 1, shift: F.samShift, user: F.sam)
        let index = MarkIndex(marks: [F.mark(b1, 1, 0), sams, F.mark(b1, 3, 0)])
        let change = MarkOps.range(block: b1, rows: 0...2, positions: 0...3, add: false, ctx: F.ctx(), index: index)
        #expect(change.removed.map(\.tree) == [F.tree(b1, 1, 0)])
        #expect(change.skipped == [sams])
    }

    @Test func rangeIsClippedToTheBlock() {
        let change = MarkOps.range(block: b1, rows: 3...10, positions: 2...20, add: true, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(change.added.map { [$0.row, $0.position] } == [[3, 2], [3, 3], [4, 2], [4, 3]])
        #expect(MarkOps.range(block: b1, rows: 5...9, positions: 0...3, add: true, ctx: F.ctx(), index: MarkIndex(marks: [])).isEmpty)
        #expect(MarkOps.range(block: b1, rows: -3 ... -1, positions: 0...3, add: true, ctx: F.ctx(), index: MarkIndex(marks: [])).isEmpty)
    }

    @Test func wholeBigBlockInOneRange() {
        let big = F.block(7, rows: 300, trees: 300)
        let change = MarkOps.range(block: big, rows: 0...299, positions: 0...299, add: true, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(change.added.count == 90_000)
        #expect(change.added.last?.tree == F.tree(big, 299, 299))
    }
}
