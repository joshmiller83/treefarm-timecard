import Foundation
import Testing
@testable import TreeFarmKit

@Suite("BlockEdit: checks")
struct BlockEditCheckTests {
    typealias F = TreeFixtures
    let block = F.block(1, rows: 10, trees: 5)

    func note(_ row: Int, _ position: Int, deleted: Bool = false) -> TreeNote {
        TreeNote(farmId: F.farmId, tree: F.tree(block, row, position), authorId: F.me, authorName: "Josh", body: "Leader broken",
                 createdAt: F.t0, deletedAt: deleted ? F.t0 : nil)
    }

    @Test func validSizesPass() {
        #expect(BlockEdit.validate(name: "North 3", rows: 1, treesPerRow: 1) == nil)
        #expect(BlockEdit.validate(name: "2", rows: 300, treesPerRow: 300) == nil)
    }

    @Test func sizesOutsideTheLimitsAreRefused() {
        #expect(BlockEdit.validate(name: "2", rows: 0, treesPerRow: 10) == "Rows in block has to be a number from 1 to 300.")
        #expect(BlockEdit.validate(name: "2", rows: 301, treesPerRow: 10) == "Rows in block has to be a number from 1 to 300.")
        #expect(BlockEdit.validate(name: "2", rows: 10, treesPerRow: 0) == "Trees per row has to be a number from 1 to 300.")
        #expect(BlockEdit.validate(name: "2", rows: 10, treesPerRow: 301) == "Trees per row has to be a number from 1 to 300.")
    }

    @Test func namesMustBeThereAndShort() {
        #expect(BlockEdit.validate(name: "   ", rows: 10, treesPerRow: 10) == "Give the block a name.")
        #expect(BlockEdit.validate(name: String(repeating: "x", count: 41), rows: 10, treesPerRow: 10) == "Block names can be up to 40 characters.")
        #expect(BlockEdit.validate(name: " " + String(repeating: "x", count: 40) + " ", rows: 10, treesPerRow: 10) == nil)
    }

    @Test func resizeThatKeepsEveryMarkIsFine() {
        let marks = [F.mark(block, 4, 2), F.mark(block, 9, 4, deleted: true)]
        #expect(BlockEdit.checkResize(block, rows: 5, treesPerRow: 3, marks: marks, notes: [note(4, 2), note(9, 9, deleted: true)]) == nil)
        #expect(BlockEdit.checkResize(block, rows: 300, treesPerRow: 300, marks: marks, notes: []) == nil)
    }

    @Test func resizeThatStrandsMarksIsRefused() {
        let marks = [F.mark(block, 9, 0), F.mark(block, 8, 0, shift: F.samShift), F.mark(block, 0, 4),
                     F.mark(F.block(2), 9, 9)]  // another block's mark doesn't count
        #expect(BlockEdit.checkResize(block, rows: 8, treesPerRow: 4, marks: marks, notes: [])
                == "3 shaped trees would fall outside that size. Erase them first, or keep the size.")
        #expect(BlockEdit.checkResize(block, rows: 9, treesPerRow: 5, marks: marks, notes: [])
                == "1 shaped tree would fall outside that size. Erase it first, or keep the size.")
    }

    @Test func marksFromEarlierSeasonsStillCount() {
        var old = F.mark(block, 9, 0)
        old.seasonId = UUID()
        #expect(BlockEdit.checkResize(block, rows: 5, treesPerRow: 5, marks: [old], notes: []) != nil)
    }

    @Test func resizeThatStrandsNotesSaysSo() {
        #expect(BlockEdit.checkResize(block, rows: 5, treesPerRow: 5, marks: [], notes: [note(7, 0)])
                == "1 tree note would fall outside that size. Delete it first, or keep the size.")
        #expect(BlockEdit.checkResize(block, rows: 5, treesPerRow: 5, marks: [], notes: [note(7, 0), note(8, 1)])
                == "2 tree notes would fall outside that size. Delete them first, or keep the size.")
    }

    @Test func resizeThatStrandsBothNamesBoth() {
        #expect(BlockEdit.checkResize(block, rows: 5, treesPerRow: 5, marks: [F.mark(block, 6, 0)], notes: [note(7, 0)])
                == "1 shaped tree and 1 tree note would fall outside that size. Erase the trees and delete the notes first, or keep the size.")
    }

    @Test func resizeToABadSizeIsRefused() {
        #expect(BlockEdit.checkResize(block, rows: 0, treesPerRow: 5, marks: [], notes: []) == "Rows in block has to be a number from 1 to 300.")
    }

    @Test func removingAnEmptyBlockIsFine() {
        #expect(BlockEdit.checkRemove(block, marks: [F.mark(block, 0, 0, deleted: true), F.mark(F.block(2), 0, 0)], notes: [note(0, 0, deleted: true)]) == nil)
    }

    @Test func removingABlockWithMarksOrNotesIsRefused() {
        #expect(BlockEdit.checkRemove(block, marks: [F.mark(block, 0, 0)], notes: [])
                == "This block has 1 shaped tree, so it can’t be removed. Erase it first.")
        #expect(BlockEdit.checkRemove(block, marks: F.marks(block, rows: 0...1), notes: [])
                == "This block has 10 shaped trees, so it can’t be removed. Erase them first.")
        #expect(BlockEdit.checkRemove(block, marks: [], notes: [note(0, 0), note(1, 1)])
                == "This block has 2 tree notes, so it can’t be removed. Delete them first.")
        #expect(BlockEdit.checkRemove(block, marks: [F.mark(block, 0, 0)], notes: [note(0, 0)])
                == "This block has 1 shaped tree and 1 tree note, so it can’t be removed. Erase the trees and delete the notes first.")
    }

    @Test func removalCountsMarksOutsideTheBoundsToo() {
        #expect(BlockEdit.checkRemove(block, marks: [F.mark(block, 50, 0)], notes: []) != nil)
    }
}

@Suite("BlockEdit: placement")
struct BlockEditPlacementTests {
    typealias F = TreeFixtures

    func spot(_ b: Block) -> [Int] { [b.gridRow, b.gridColumn] }
    func new(_ n: Int = 99) -> Block { F.block(n, name: "New", gridRow: 42, gridColumn: 42) }

    @Test func firstBlockInAnEmptyField() {
        let placed = BlockEdit.place(new: new(), .first, among: [])
        #expect(placed.map(spot) == [[0, 0]])
        #expect(placed.first?.id == F.id(99))
        #expect(placed.first?.name == "New")
    }

    @Test func rightOfABlockShiftsLaterBlocksRight() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let b = F.block(2, gridRow: 0, gridColumn: 1)
        let c = F.block(3, gridRow: 0, gridColumn: 2)
        let d = F.block(4, gridRow: 1, gridColumn: 0)
        let placed = BlockEdit.place(new: new(), .rightOf(a.id), among: [d, c, b, a])
        #expect(placed.map(\.id) == [F.id(99), b.id, c.id])
        #expect(placed.map(spot) == [[0, 1], [0, 2], [0, 3]])
    }

    @Test func aGapInColumnsStopsTheShift() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let b = F.block(2, gridRow: 0, gridColumn: 1)
        let c = F.block(3, gridRow: 0, gridColumn: 5)
        let placed = BlockEdit.place(new: new(), .rightOf(a.id), among: [a, b, c])
        #expect(placed.map(\.id) == [F.id(99), b.id])
        #expect(placed.map(spot) == [[0, 1], [0, 2]])
    }

    @Test func rightOfTheLastBlockMovesNothingElse() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let b = F.block(2, gridRow: 0, gridColumn: 3)
        let placed = BlockEdit.place(new: new(), .rightOf(b.id), among: [a, b])
        #expect(placed.map(spot) == [[0, 4]])
    }

    @Test func rightOfABlockInALowerStrip() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let d = F.block(4, gridRow: 2, gridColumn: 0)
        let e = F.block(5, gridRow: 2, gridColumn: 1)
        let placed = BlockEdit.place(new: new(), .rightOf(d.id), among: [a, d, e])
        #expect(placed.map(spot) == [[2, 1], [2, 2]])
        #expect(placed.last?.id == e.id)
    }

    @Test func newRowBelowGoesUnderTheLastStrip() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let d = F.block(4, gridRow: 3, gridColumn: 2)
        #expect(BlockEdit.place(new: new(), .newRowBelow, among: [a, d]).map(spot) == [[4, 0]])
        #expect(BlockEdit.place(new: new(), .newRowBelow, among: []).map(spot) == [[0, 0]])
    }

    @Test func firstWhenBlocksExistGoesTopLeft() {
        let a = F.block(1, gridRow: 1, gridColumn: 0)
        let b = F.block(2, gridRow: 1, gridColumn: 1)
        let placed = BlockEdit.place(new: new(), .first, among: [b, a])
        #expect(placed.map(\.id) == [F.id(99), a.id, b.id])
        #expect(placed.map(spot) == [[1, 0], [1, 1], [1, 2]])
    }

    @Test func deletedBlocksAreNotMovedOrCounted() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let gone = F.block(2, gridRow: 0, gridColumn: 1, deleted: true)
        let low = F.block(3, gridRow: 9, gridColumn: 0, deleted: true)
        #expect(BlockEdit.place(new: new(), .rightOf(a.id), among: [a, gone, low]).map(spot) == [[0, 1]])
        #expect(BlockEdit.place(new: new(), .newRowBelow, among: [a, gone, low]).map(spot) == [[1, 0]])
    }

    @Test func unknownNeighborFallsBackToANewRow() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        #expect(BlockEdit.place(new: new(), .rightOf(UUID()), among: [a]).map(spot) == [[1, 0]])
    }

    @Test func theNewBlockIsNeverItsOwnNeighbor() {
        let a = F.block(1, gridRow: 0, gridColumn: 0)
        let moving = F.block(2, gridRow: 0, gridColumn: 1)
        let placed = BlockEdit.place(new: moving, .rightOf(a.id), among: [a, moving])
        #expect(placed.map(\.id) == [moving.id])
        #expect(placed.map(spot) == [[0, 1]])
    }
}
