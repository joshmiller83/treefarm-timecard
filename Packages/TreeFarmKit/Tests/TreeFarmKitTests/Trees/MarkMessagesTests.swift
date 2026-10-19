import Foundation
import Testing
@testable import TreeFarmKit

@Suite("MarkMessages")
struct MarkMessagesTests {
    typealias F = TreeFixtures
    let block = F.block(2, rows: 61, trees: 10)

    @Test func fixedLines() {
        #expect(MarkMessages.needShift == "Clock in or add a shift first. Trees are saved with a shift.")
        #expect(MarkMessages.undid == "Undid your last change.")
        #expect(MarkMessages.fillOneBlock == "Pick the first and last tree in the same block. Tap the first tree again to start over.")
    }

    @Test func oneTreeTaps() {
        let tree = F.tree(block, 13, 3)
        let free = MarkIndex(marks: [])
        let marked = MarkOps.toggle(tree, ctx: F.ctx(), index: free)
        #expect(MarkMessages.tap(marked, tree: tree, block: block) == "Marked Block 2, row 14, tree 4.")
        let unmarked = MarkOps.toggle(tree, ctx: F.ctx(), index: free.applying(marked))
        #expect(MarkMessages.tap(unmarked, tree: tree, block: block) == "Unmarked Block 2, row 14, tree 4.")
        let erasedNothing = MarkOps.unmark([tree], ctx: F.ctx(), index: free)
        #expect(MarkMessages.tap(erasedNothing, tree: tree, block: block) == "Block 2, row 14, tree 4 isn’t marked on this shift.")
    }

    @Test func treeShapedOnAnotherShift() {
        let tree = F.tree(block, 0, 0)
        let index = MarkIndex(marks: [F.mark(block, 0, 0, shift: F.samShift, user: F.sam)])
        let change = MarkOps.toggle(tree, ctx: F.ctx(), index: index)
        #expect(MarkMessages.tap(change, tree: tree, block: block, shapedOn: "Oct 16") == "Block 2, row 1, tree 1 was shaped on Oct 16.")
        #expect(MarkMessages.tap(change, tree: tree, block: block) == "Block 2, row 1, tree 1 was shaped on another day.")
    }

    @Test func rowTaps() {
        let row = F.row(block, 13)
        let free = MarkIndex(marks: [])
        let marked = MarkOps.rowTap(row, block: block, mode: .one, ctx: F.ctx(), index: free)
        #expect(MarkMessages.rowTap(marked, row: row, block: block, mode: .one)
                == "Marked 10 trees in Block 2, row 14. Tap the row number again to clear it.")
        let cleared = MarkOps.rowTap(row, block: block, mode: .one, ctx: F.ctx(), index: free.applying(marked))
        #expect(MarkMessages.rowTap(cleared, row: row, block: block, mode: .one) == "Cleared 10 trees from Block 2, row 14.")
        let nothing = MarkOps.rowTap(row, block: block, mode: .erase, ctx: F.ctx(), index: free)
        #expect(MarkMessages.rowTap(nothing, row: row, block: block, mode: .erase) == "Nothing in Block 2, row 14 is marked on this shift.")
        let others = MarkIndex(marks: F.marks(block, rows: 13...13, shift: F.samShift))
        let taken = MarkOps.rowTap(row, block: block, mode: .one, ctx: F.ctx(), index: others)
        #expect(MarkMessages.rowTap(taken, row: row, block: block, mode: .one) == "Every tree in Block 2, row 14 was shaped on another day.")
    }

    @Test func rowTapSingular() {
        let row = F.row(block, 0)
        let index = MarkIndex(marks: (0..<9).map { F.mark(block, 0, $0, shift: F.samShift) })
        let change = MarkOps.rowTap(row, block: block, mode: .one, ctx: F.ctx(), index: index)
        #expect(MarkMessages.rowTap(change, row: row, block: block, mode: .one)
                == "Marked 1 tree in Block 2, row 1. Tap the row number again to clear it.")
    }

    @Test func fills() {
        let a = F.tree(block, 3, 4), b = F.tree(block, 1, 2)
        let change = MarkOps.fillBetween(a, b, block: block, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(MarkMessages.fill(change, from: a, to: b) == "Marked 23 trees, from row 2, tree 3 to row 4, tree 5.")
        #expect(MarkMessages.fill(MarkChange(), from: a, to: b) == "Nothing new to mark there.")
    }

    @Test func typedRanges() {
        let add = MarkOps.range(block: block, rows: 2...4, positions: 0...9, add: true, ctx: F.ctx(), index: MarkIndex(marks: []))
        #expect(MarkMessages.range(add, block: block, rows: 2...4, add: true) == "Marked 30 trees in Block 2, rows 3–5.")
        let index = MarkIndex(marks: []).applying(add)
        let remove = MarkOps.range(block: block, rows: 2...2, positions: 0...0, add: false, ctx: F.ctx(), index: index)
        #expect(MarkMessages.range(remove, block: block, rows: 2...2, add: false) == "Unmarked 1 tree in Block 2, row 3.")
        #expect(MarkMessages.range(MarkChange(), block: block, rows: 2...2, add: true) == "Those trees were already marked.")
        #expect(MarkMessages.range(MarkChange(), block: block, rows: 2...2, add: false) == "None of those trees are marked on this shift.")
    }

    @Test func typedNumbersOutsideTheBlock() {
        let north = F.block(3, name: "North", rows: 61, trees: 10)
        #expect(MarkMessages.checkRange(block: north, rows: 0...60, positions: 0...9) == nil)
        #expect(MarkMessages.checkRange(block: north, rows: 0...61, positions: 0...9) == "Rows in North go from 1 to 61.")
        #expect(MarkMessages.checkRange(block: north, rows: -1...3, positions: 0...9) == "Rows in North go from 1 to 61.")
        #expect(MarkMessages.checkRange(block: north, rows: 0...3, positions: 0...10) == "Trees go from 1 to 10 in each row of North.")
    }

    // MARK: The map's other lines (moved here from the app)

    @Test func fillAndZoomHints() {
        #expect(MarkMessages.fillStart(F.tree(block, 13, 3), in: block) == "Start: Block 2, row 14, tree 4. Now tap the last tree.")
        #expect(MarkMessages.zoomedInto(block) == "Showing Block 2. Tap All to see the whole field again.")
    }

    @Test func notesSomeoneElseOwnsOrDeleted() {
        #expect(MarkMessages.noteGone == "That note was deleted.")
        #expect(MarkMessages.notePermission(.edit) == "Only the person who wrote a note, or an admin, can change it.")
        #expect(MarkMessages.notePermission(.delete) == "Only the person who wrote a note, or an admin, can delete it.")
    }

    @Test func aRowsStatusForVoiceOver() {
        #expect(MarkMessages.rowStatus(F.row(block, 13), in: block, "all 10 trees shaped") == "Block 2, row 14: all 10 trees shaped.")
    }

    @Test func treesLostToAnotherPhoneAreOneSentencePerRow() {
        let block = Block(fieldId: UUID(), name: "2", gridRow: 0, gridColumn: 0, rowCount: 20, treesPerRow: 10)
        #expect(MarkMessages.shapedFirst(by: "Sam", count: 10, row: 0, in: block) == "Sam shaped 10 trees in Block 2, row 1 first. They came off your shift.")
        #expect(MarkMessages.shapedFirst(by: nil, count: 1, row: 13, in: nil) == "Someone else shaped 1 tree in row 14 first. It came off your shift.")
    }

    @Test func undoSaysWhichTreesItLeftAlone() {
        let mark = TreeMark(seasonId: UUID(), tree: TreeRef(blockId: UUID(), row: 1, position: 3), shiftId: UUID(), userId: UUID(), markedAt: Date())
        #expect(MarkMessages.undidExcept([mark], by: "Sam") == "Undid your last change, except tree 4 in row 2, which Sam shaped since.")
        #expect(MarkMessages.undidExcept([mark, mark, mark], by: nil) == "Undid your last change, except 3 trees someone else shaped since.")
    }
}
