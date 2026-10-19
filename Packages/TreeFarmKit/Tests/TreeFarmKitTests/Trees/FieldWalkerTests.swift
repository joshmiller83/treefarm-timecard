import Foundation
import Testing
@testable import TreeFarmKit

@Suite("FieldWalker")
struct FieldWalkerTests {
    typealias F = TreeFixtures

    // Strip 0: blocks 1 and 2 (columns 0 and 5, a gap). Strip 1: block 3.
    let b1 = F.block(1, gridRow: 0, gridColumn: 0, rows: 3, trees: 2)
    let b2 = F.block(2, gridRow: 0, gridColumn: 5, rows: 2, trees: 2)
    let b3 = F.block(3, gridRow: 1, gridColumn: 0, rows: 2, trees: 3)
    var walker: FieldWalker { FieldWalker(blocks: [b3, b2, b1]) }

    @Test func walksBlocksByStripThenColumn() {
        #expect(walker.blocks.map(\.id) == [b1.id, b2.id, b3.id])
    }

    @Test func sameGridSpotFallsBackToName() {
        let a = F.block(4, name: "10", gridRow: 0, gridColumn: 0)
        let b = F.block(5, name: "9", gridRow: 0, gridColumn: 0)
        let c = F.block(6, name: "North", gridRow: 0, gridColumn: 0)
        #expect(FieldWalker(blocks: [c, a, b]).blocks.map(\.name) == ["9", "10", "North"])
    }

    @Test func ignoresDeletedBlocks() {
        let gone = F.block(4, gridRow: 0, gridColumn: 1, deleted: true)
        let walker = FieldWalker(blocks: [b1, gone, b2])
        #expect(walker.blocks.map(\.id) == [b1.id, b2.id])
        #expect(walker.block(gone.id) == nil)
        #expect(walker.block(b2.id) == b2)
    }

    @Test func listsEveryRowInWalkOrder() {
        let rows = walker.rows().map { [Int($0.blockId == b1.id ? 1 : $0.blockId == b2.id ? 2 : 3), $0.row] }
        #expect(rows == [[1, 0], [1, 1], [1, 2], [2, 0], [2, 1], [3, 0], [3, 1]])
    }

    @Test func rowAfterCrossesBlocksAndStrips() {
        #expect(walker.row(after: F.row(b1, 0)) == F.row(b1, 1))
        #expect(walker.row(after: F.row(b1, 2)) == F.row(b2, 0))
        #expect(walker.row(after: F.row(b2, 1)) == F.row(b3, 0))
        #expect(walker.row(after: F.row(b3, 1)) == nil)
        #expect(walker.row(after: F.row(F.block(9), 0)) == nil)
        #expect(walker.row(after: F.row(b1, 7)) == nil)
    }

    @Test func labelsSayBlockForNumberedBlocks() {
        let named = F.block(4, name: "North 3")
        let walker = FieldWalker(blocks: [b1, named, F.block(5, name: "Block 7")])
        #expect(walker.label(F.row(b1, 13)) == "Block 1, row 14")
        #expect(walker.label(F.row(named, 0)) == "North 3, row 1")
        #expect(walker.label(RowRef(blockId: F.id(5), row: 1)) == "Block 7, row 2")
        #expect(walker.label(F.row(F.block(9), 4)) == "Row 5")
    }

    @Test func blockNamesForPeople() {
        #expect(F.block(1, name: " 12 ").displayName == "Block 12")
        #expect(F.block(1, name: "").displayName == "Block")
        #expect(F.block(1, name: "3B").displayName == "3B")
        #expect(F.block(1, name: "2").label(TreeRef(blockId: F.id(1), row: 13, position: 2)) == "Block 2, row 14, tree 3")
    }

    @Test func progressCountsLiveBlocksInBounds() {
        var gone = F.block(4, rows: 10, trees: 10)
        let marks = F.marks(b1, rows: 0...1) + [F.mark(b3, 1, 2, shift: F.samShift), F.mark(b3, 5, 0)] + F.marks(gone, rows: 0...0)
        gone.deletedAt = F.t0
        let walker = FieldWalker(blocks: [b1, b2, b3, gone])
        let progress = walker.progress(index: MarkIndex(marks: marks))
        #expect(progress.shaped == 5)
        #expect(progress.total == 6 + 4 + 6)
    }

    @Test func emptyFieldHasNothingToWalk() {
        let walker = FieldWalker(blocks: [])
        #expect(walker.rows().isEmpty)
        #expect(walker.nextRows(from: nil, count: 3, index: MarkIndex(marks: [])).isEmpty)
        #expect(walker.progress(index: MarkIndex(marks: [])) == (0, 0))
    }

    // MARK: nextRows

    @Test func fromNilStartsAtTheFirstRow() {
        let next = walker.nextRows(from: nil, count: 3, index: MarkIndex(marks: []))
        #expect(next == [F.row(b1, 0), F.row(b1, 1), F.row(b1, 2)])
    }

    @Test func startsAtTheGivenRowItself() {
        let next = walker.nextRows(from: F.row(b1, 1), count: 2, index: MarkIndex(marks: []))
        #expect(next == [F.row(b1, 1), F.row(b1, 2)])
    }

    @Test func skipsCompleteRowsIncludingTheStartRow() {
        let index = MarkIndex(marks: F.marks(b1, rows: 1...1, shift: F.samShift))
        let next = walker.nextRows(from: F.row(b1, 1), count: 3, index: index)
        #expect(next == [F.row(b1, 2), F.row(b2, 0), F.row(b2, 1)])
    }

    @Test func partlyShapedRowsAreStillOpen() {
        let index = MarkIndex(marks: [F.mark(b1, 0, 0)])
        #expect(walker.nextRows(from: nil, count: 1, index: index) == [F.row(b1, 0)])
    }

    @Test func crossesIntoTheNextBlockAndStrip() {
        let index = MarkIndex(marks: F.marks(b2, rows: 0...0))
        let next = walker.nextRows(from: F.row(b1, 2), count: 3, index: index)
        #expect(next == [F.row(b1, 2), F.row(b2, 1), F.row(b3, 0)])
    }

    @Test func wrapsAroundOnceToEarlierOpenRows() {
        // Everything after block 1 row 1 is done; rows 0 and 1 of block 1 are open.
        let done = F.marks(b1, rows: 2...2) + F.marks(b2, rows: 0...1) + F.marks(b3, rows: 0...1)
        let index = MarkIndex(marks: done)
        let next = walker.nextRows(from: F.row(b3, 0), count: 3, index: index)
        #expect(next == [F.row(b1, 0), F.row(b1, 1)])
    }

    @Test func wrapsWithoutRepeatingTheStart() {
        let next = walker.nextRows(from: F.row(b3, 1), count: 10, index: MarkIndex(marks: []))
        #expect(next.count == 7)
        #expect(next.first == F.row(b3, 1))
        #expect(next[1] == F.row(b1, 0))
        #expect(Set(next).count == 7)
    }

    @Test func returnsFewerNearTheEnd() {
        let done = F.marks(b1, rows: 0...2) + F.marks(b2, rows: 0...1) + F.marks(b3, rows: 0...0)
        let next = walker.nextRows(from: nil, count: 3, index: MarkIndex(marks: done))
        #expect(next == [F.row(b3, 1)])
    }

    @Test func aFinishedFieldHasNoNextRows() {
        let done = F.marks(b1, rows: 0...2) + F.marks(b2, rows: 0...1) + F.marks(b3, rows: 0...1, shift: F.samShift)
        #expect(walker.nextRows(from: F.row(b2, 0), count: 3, index: MarkIndex(marks: done)).isEmpty)
        #expect(walker.nextRows(from: nil, count: 3, index: MarkIndex(marks: done)).isEmpty)
    }

    @Test func zeroCountIsEmpty() {
        #expect(walker.nextRows(from: nil, count: 0, index: MarkIndex(marks: [])).isEmpty)
    }

    @Test func deletedBlocksAreSkipped() {
        let gone = F.block(4, gridRow: 0, gridColumn: 1, rows: 2, trees: 2, deleted: true)
        let walker = FieldWalker(blocks: [b1, gone, b2])
        let index = MarkIndex(marks: F.marks(b1, rows: 0...2))
        #expect(walker.nextRows(from: F.row(b1, 2), count: 2, index: index) == [F.row(b2, 0), F.row(b2, 1)])
    }

    @Test func aStartInADeletedBlockStartsAtTheTop() {
        let gone = F.block(4, gridRow: 0, gridColumn: 1, rows: 2, trees: 2, deleted: true)
        let walker = FieldWalker(blocks: [b1, gone, b2])
        #expect(walker.nextRows(from: F.row(gone, 1), count: 1, index: MarkIndex(marks: [])) == [F.row(b1, 0)])
    }

    @Test func aStartPastAShrunkBlockMovesToTheNextBlock() {
        #expect(walker.nextRows(from: F.row(b1, 40), count: 1, index: MarkIndex(marks: [])) == [F.row(b2, 0)])
        #expect(walker.nextRows(from: F.row(b3, 40), count: 1, index: MarkIndex(marks: [])) == [F.row(b1, 0)])
    }

    @Test func lastRowOfTheLastBlock() {
        #expect(walker.nextRows(from: F.row(b3, 1), count: 1, index: MarkIndex(marks: [])) == [F.row(b3, 1)])
    }

    @Test func bigFieldStaysQuick() {
        let blocks = (0..<14).map { F.block($0 + 10, gridRow: $0 / 7, gridColumn: $0 % 7, rows: 300, trees: 300) }
        let walker = FieldWalker(blocks: blocks)
        let done = F.marks(blocks[0], rows: 0...298)
        let next = walker.nextRows(from: nil, count: 3, index: MarkIndex(marks: done))
        #expect(next == [F.row(blocks[0], 299), F.row(blocks[1], 0), F.row(blocks[1], 1)])
        #expect(walker.progress(index: MarkIndex(marks: done)) == (89_700, 14 * 90_000))
    }
}
