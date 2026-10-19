import Foundation
import Testing
@testable import TreeFarmKit

@Suite("MarkIndex")
struct MarkIndexTests {
    typealias F = TreeFixtures
    let b1 = F.block(1, rows: 5, trees: 4)
    let b2 = F.block(2, rows: 3, trees: 2)

    @Test func emptyIndexHoldsNothing() {
        let index = MarkIndex(marks: [])
        #expect(index.mark(at: F.tree(b1, 0, 0)) == nil)
        #expect(index.marks(onShift: F.myShift).isEmpty)
        #expect(index.shapedCount(in: b1) == 0)
        #expect(!index.isRowComplete(F.row(b1, 0), block: b1))
        #expect(index.freePositions(in: F.row(b1, 0), block: b1) == [0, 1, 2, 3])
    }

    @Test func findsTheMarkOnATree() {
        let m = F.mark(b1, 2, 3)
        let index = MarkIndex(marks: [m])
        #expect(index.mark(at: F.tree(b1, 2, 3)) == m)
        #expect(index.mark(at: F.tree(b1, 3, 2)) == nil)
        #expect(index.mark(at: F.tree(b2, 2, 3)) == nil)
    }

    @Test func ignoresDeletedMarks() {
        let index = MarkIndex(marks: [F.mark(b1, 0, 0, deleted: true)])
        #expect(index.mark(at: F.tree(b1, 0, 0)) == nil)
        #expect(index.shapedCount(in: b1) == 0)
    }

    @Test func earliestMarkWinsWhenTwoClaimOneTree() {
        let late = F.mark(b1, 1, 1, shift: F.myShift, at: 500)
        let early = F.mark(b1, 1, 1, shift: F.samShift, user: F.sam, at: 100)
        #expect(MarkIndex(marks: [late, early]).mark(at: F.tree(b1, 1, 1)) == early)
        #expect(MarkIndex(marks: [early, late]).mark(at: F.tree(b1, 1, 1)) == early)
        // The loser is gone from its shift too.
        #expect(MarkIndex(marks: [late, early]).marks(onShift: F.myShift).isEmpty)
    }

    @Test func sameTimeTieGoesToTheSmallerId() {
        let a = F.mark(b1, 0, 0, shift: F.myShift, at: 100, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let b = F.mark(b1, 0, 0, shift: F.samShift, at: 100, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        #expect(MarkIndex(marks: [a, b]).mark(at: F.tree(b1, 0, 0))?.id == b.id)
        #expect(MarkIndex(marks: [b, a]).mark(at: F.tree(b1, 0, 0))?.id == b.id)
    }

    @Test func listsAShiftsMarksInTreeOrder() {
        let marks = [F.mark(b1, 2, 0), F.mark(b1, 0, 3), F.mark(b1, 0, 1), F.mark(b1, 4, 0, shift: F.samShift)]
        let mine = MarkIndex(marks: marks).marks(onShift: F.myShift)
        #expect(mine.map(\.tree) == [F.tree(b1, 0, 1), F.tree(b1, 0, 3), F.tree(b1, 2, 0)])
    }

    @Test func countsOnlyMarksInsideLiveBlocks() {
        var gone = F.block(3, rows: 2, trees: 2)
        let marks = [
            F.mark(b1, 0, 0), F.mark(b1, 4, 3),
            F.mark(b1, 5, 0),            // past the last row
            F.mark(b1, 0, 4),            // past the last tree
            F.mark(b2, 0, 0),
            F.mark(gone, 0, 0),          // block deleted below
            F.mark(F.block(9), 0, 0),    // block not passed in
            F.mark(b1, 1, 1, shift: F.samShift),
        ]
        gone.deletedAt = F.t0
        let index = MarkIndex(marks: marks)
        #expect(index.count(onShift: F.myShift, blocks: [b1, b2, gone]) == 3)
        #expect(index.count(onShift: F.samShift, blocks: [b1, b2, gone]) == 1)
        #expect(index.count(onShift: UUID(), blocks: [b1, b2]) == 0)
    }

    @Test func shapedCountUsesTheBlocksCurrentBounds() {
        let index = MarkIndex(marks: [F.mark(b1, 0, 0), F.mark(b1, 4, 3, shift: F.samShift), F.mark(b1, 9, 0), F.mark(b2, 0, 0)])
        #expect(index.shapedCount(in: b1) == 2)
        var smaller = b1
        smaller.rowCount = 4
        #expect(index.shapedCount(in: smaller) == 1)
    }

    @Test func rowIsCompleteWhenAnyoneShapedEveryTree() {
        let marks = [F.mark(b1, 1, 0), F.mark(b1, 1, 1), F.mark(b1, 1, 2, shift: F.samShift), F.mark(b1, 1, 3, shift: F.samShift),
                     F.mark(b1, 2, 0), F.mark(b1, 2, 1), F.mark(b1, 2, 2)]
        let index = MarkIndex(marks: marks)
        #expect(index.isRowComplete(F.row(b1, 1), block: b1))
        #expect(!index.isRowComplete(F.row(b1, 2), block: b1))
        #expect(index.freePositions(in: F.row(b1, 2), block: b1) == [3])
        #expect(index.freePositions(in: F.row(b1, 1), block: b1) == [])
    }

    @Test func marksPastTheRowEndDontCompleteARow() {
        let marks = [F.mark(b1, 0, 0), F.mark(b1, 0, 1), F.mark(b1, 0, 2), F.mark(b1, 0, 4)]
        let index = MarkIndex(marks: marks)
        #expect(!index.isRowComplete(F.row(b1, 0), block: b1))
        #expect(index.freePositions(in: F.row(b1, 0), block: b1) == [3])
    }

    @Test func rowsOutsideTheBlockAreNeverComplete() {
        let index = MarkIndex(marks: [])
        #expect(!index.isRowComplete(F.row(b1, 5), block: b1))
        #expect(index.freePositions(in: F.row(b1, 5), block: b1) == [])
        #expect(index.freePositions(in: F.row(b2, 0), block: b1) == [])
    }

    @Test func oneByOneBlock() {
        let tiny = F.block(4, rows: 1, trees: 1)
        let index = MarkIndex(marks: [F.mark(tiny, 0, 0)])
        #expect(index.isRowComplete(F.row(tiny, 0), block: tiny))
        #expect(index.shapedCount(in: tiny) == 1)
    }

    @Test func bigBlockCountsQuickly() {
        let big = F.block(5, rows: 300, trees: 300)
        let marks = F.marks(big, rows: 0...149)
        let index = MarkIndex(marks: marks)
        #expect(index.shapedCount(in: big) == 45_000)
        #expect(index.isRowComplete(F.row(big, 149), block: big))
        #expect(!index.isRowComplete(F.row(big, 150), block: big))
        #expect(index.count(onShift: F.myShift, blocks: [big]) == 45_000)
    }

    @Test func applyingAChangeAddsAndRemoves() {
        let keep = F.mark(b1, 0, 0)
        var drop = F.mark(b1, 0, 1)
        let index = MarkIndex(marks: [keep, drop])
        drop.deletedAt = F.t0.addingTimeInterval(10)
        let added = F.mark(b1, 3, 3)
        let next = index.applying(MarkChange(added: [added], removed: [drop], skipped: []))
        #expect(next.mark(at: keep.tree) == keep)
        #expect(next.mark(at: drop.tree) == nil)
        #expect(next.mark(at: added.tree) == added)
        #expect(next.marks(onShift: F.myShift).count == 2)
        // The original is untouched.
        #expect(index.mark(at: drop.tree) != nil)
    }

    @Test func applyingLeavesAnotherMarkOnTheSameTreeAlone() {
        let sams = F.mark(b1, 2, 2, shift: F.samShift, user: F.sam)
        let index = MarkIndex(marks: [sams])
        var stale = F.mark(b1, 2, 2)  // a removal for a mark the index doesn't hold
        stale.deletedAt = F.t0
        let next = index.applying(MarkChange(added: [], removed: [stale], skipped: []))
        #expect(next.mark(at: sams.tree) == sams)
    }

    @Test func applyingAnAddKeepsTheEarlierClaim() {
        let sams = F.mark(b1, 2, 2, shift: F.samShift, user: F.sam, at: 0)
        let index = MarkIndex(marks: [sams])
        let next = index.applying(MarkChange(added: [F.mark(b1, 2, 2, at: 50)], removed: [], skipped: []))
        #expect(next.mark(at: sams.tree) == sams)
        #expect(next.marks(onShift: F.myShift).isEmpty)
    }

    @Test func keptUpToDateItMatchesARebuild() {
        let block = UUID()
        let shiftA = UUID(), shiftB = UUID(), user = UUID(), season = UUID()
        let t0 = Date(timeIntervalSince1970: 1_000)
        func mark(_ row: Int, _ p: Int, shift: UUID, at: TimeInterval) -> TreeMark {
            TreeMark(seasonId: season, tree: TreeRef(blockId: block, row: row, position: p), shiftId: shift, userId: user, markedAt: t0 + at)
        }
        let early = mark(0, 0, shift: shiftA, at: 0)
        let late = mark(0, 0, shift: shiftB, at: 5)
        var index = MarkIndex(marks: [])
        index.apply(late)
        index.apply(early)
        #expect(index.mark(at: early.tree)?.id == early.id, "the earlier claim wins")
        var gone = early
        gone.deletedAt = t0 + 10
        index.apply(gone)
        #expect(index.mark(at: early.tree)?.id == late.id, "the next claim takes the tree")
        #expect(index.count(onShift: shiftB, blocks: [Block(id: block, fieldId: UUID(), name: "1", gridRow: 0, gridColumn: 0, rowCount: 5, treesPerRow: 5)]) == 1)
        var moved = late
        moved.shiftId = shiftA
        index.apply(moved)
        #expect(index.marks(onShift: shiftB).isEmpty)
        #expect(index.marks(onShift: shiftA).map(\.id) == [late.id])
    }
}
