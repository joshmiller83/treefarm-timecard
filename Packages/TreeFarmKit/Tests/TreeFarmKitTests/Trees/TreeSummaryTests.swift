import Foundation
import Testing
@testable import TreeFarmKit

@Suite("TreeSummary")
struct TreeSummaryTests {
    typealias F = TreeFixtures

    @Test(arguments: [
        ([], ""),
        ([0], "1"),
        ([0, 1, 2, 3, 6, 8, 9], "1–4, 7, 9–10"),
        ([9, 8, 0, 3, 2, 1, 6], "1–4, 7, 9–10"),
        ([4, 4, 5], "5–6"),
        ([0, 2, 4, 6, 8], "1, 3, 5, 7, …"),
        ([0, 2, 4, 6], "1, 3, 5, 7"),
    ] as [([Int], String)])
    func rangesReadOneBased(positions: [Int], text: String) {
        #expect(TreeSummary.ranges(positions) == text)
    }

    @Test func fullRowsRunTogetherAndPartRowsListTheirTrees() {
        let b1 = F.block(1, gridColumn: 0, rows: 20, trees: 4)
        let b2 = F.block(2, gridColumn: 1, rows: 5, trees: 4)
        let marks = F.marks(b1, rows: 0...11) + [F.mark(b1, 12, 0), F.mark(b1, 12, 1), F.mark(b1, 12, 2), F.mark(b1, 12, 3, deleted: true)]
            + F.marks(b2, rows: 0...0)
        let text = TreeSummary.text(marks: marks.shuffled(), blocks: [b2, b1])
        #expect(text == "Block 1: rows 1–12, row 13 (trees 1–3) · Block 2: row 1")
    }

    @Test func oneTreeIsSingular() {
        let b = F.block(1, name: "North 3", rows: 5, trees: 4)
        #expect(TreeSummary.text(marks: [F.mark(b, 2, 3)], blocks: [b]) == "North 3: row 3 (tree 4)")
    }

    @Test func aPartRowBreaksARunOfFullRows() {
        let b = F.block(1, rows: 10, trees: 2)
        let marks = F.marks(b, rows: 0...1) + [F.mark(b, 2, 1)] + F.marks(b, rows: 3...4) + F.marks(b, rows: 6...6)
        #expect(TreeSummary.text(marks: marks, blocks: [b]) == "Block 1: rows 1–2, row 3 (tree 2), rows 4–5, row 7")
    }

    @Test func longListsStopAfterSixParts() {
        let b = F.block(1, rows: 20, trees: 2)
        let marks = stride(from: 0, to: 16, by: 2).flatMap { F.marks(b, rows: $0...$0) }
        #expect(TreeSummary.text(marks: marks, blocks: [b]) == "Block 1: row 1, row 3, row 5, row 7, row 9, row 11 and more")
    }

    @Test func ignoresTreesOutsideBlocksAndDeletedBlocks() {
        let b = F.block(1, rows: 2, trees: 2)
        let gone = F.block(2, gridColumn: 1, deleted: true)
        let marks = [F.mark(b, 5, 0), F.mark(b, 0, 7), F.mark(gone, 0, 0), F.mark(F.block(3), 0, 0)]
        #expect(TreeSummary.text(marks: marks, blocks: [b, gone]) == "")
        #expect(TreeSummary.text(marks: [], blocks: [b]) == "")
    }

    @Test func blocksFollowWalkOrderAcrossStrips() {
        let top = F.block(1, name: "North", gridRow: 0, gridColumn: 3)
        let low = F.block(2, name: "South", gridRow: 1, gridColumn: 0)
        let text = TreeSummary.text(marks: [F.mark(low, 0, 0), F.mark(top, 0, 0)], blocks: [low, top])
        #expect(text == "North: row 1 (tree 1) · South: row 1 (tree 1)")
    }

    @Test func oneByOneBlockReadsAsAFullRow() {
        let tiny = F.block(1, rows: 1, trees: 1)
        #expect(TreeSummary.text(marks: [F.mark(tiny, 0, 0)], blocks: [tiny]) == "Block 1: row 1")
    }
}
