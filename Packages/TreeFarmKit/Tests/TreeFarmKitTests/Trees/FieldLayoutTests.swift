import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import TreeFarmKit

/// A map with uneven strips, a gap in the column numbers, and across and down blocks.
/// Strip 0: A across 5×4 (col 0), B down 3×6 (col 2), C across 2×2 (col 7). Strip 1: D across 10×3.
/// With the M zoom (26×15 cells, 26 labels, 6 inset, 14 gap, 24 strip gap, 34 header):
///   A frame (0,0,142,121)   grid (32,40,104,75)
///   B frame (156,0,116,160) grid (188,40,78,90)   down: 24 of footer below its outline
///   C frame (286,0,90,76)   grid (318,40,52,30)
///   D frame (0,160,116,196) grid (32,200,78,150)
enum MapFixture {
    typealias F = TreeFixtures
    static let a = F.block(1, name: "A", gridRow: 0, gridColumn: 0, rows: 5, trees: 4)
    static let b = F.block(2, name: "B", gridRow: 0, gridColumn: 2, rows: 3, trees: 6, direction: .down)
    static let c = F.block(3, name: "C", gridRow: 0, gridColumn: 7, rows: 2, trees: 2)
    static let d = F.block(4, name: "D", gridRow: 1, gridColumn: 0, rows: 10, trees: 3)
    static let gone = F.block(5, name: "Gone", gridRow: 0, gridColumn: 1, rows: 50, trees: 50, deleted: true)
    static var blocks: [Block] { [d, c, gone, b, a] }
    static var layout: FieldLayout { FieldLayout(blocks: blocks, metrics: .m) }
}

@Suite("FieldLayout")
struct FieldLayoutTests {
    typealias F = TreeFixtures
    typealias M = MapFixture

    @Test func zoomPresetsMatchTheArtifact() {
        #expect(MapMetrics.xs.cell == CGSize(width: 12, height: 7))
        #expect(MapMetrics.s.cell == CGSize(width: 18, height: 10))
        #expect(MapMetrics.m.cell == CGSize(width: 26, height: 15))
        #expect(MapMetrics.l.cell == CGSize(width: 36, height: 22))
        for z in [MapMetrics.xs, .s, .m, .l] {
            #expect(z.rowLabelWidth == 26)
            #expect(z.inset == 6)
            #expect(z.blockGap == 14)
            #expect(z.headerHeight == 34)
            #expect(z.stripGap == 24)
            #expect(!z.isOverview)
        }
    }

    @Test func blocksSitInStripsLeftToRight() {
        let frames = M.layout.frames
        #expect(frames.map(\.block.name) == ["A", "B", "C", "D"])
        #expect(frames.map(\.frame) == [
            CGRect(x: 0, y: 0, width: 142, height: 121),
            CGRect(x: 156, y: 0, width: 116, height: 160),
            CGRect(x: 286, y: 0, width: 90, height: 76),
            CGRect(x: 0, y: 160, width: 116, height: 196),
        ])
        #expect(frames.map(\.grid) == [
            CGRect(x: 32, y: 40, width: 104, height: 75),
            CGRect(x: 188, y: 40, width: 78, height: 90),
            CGRect(x: 318, y: 40, width: 52, height: 30),
            CGRect(x: 32, y: 200, width: 78, height: 150),
        ])
        #expect(frames[0].outline == CGRect(x: 26, y: 34, width: 116, height: 87))
        #expect(frames.map(\.columns) == [4, 3, 2, 3])
        #expect(frames.map(\.lines) == [5, 6, 2, 10])
    }

    @Test func mapIsAsWideAsItsWidestStripAndHoldsEveryStrip() {
        #expect(M.layout.size == CGSize(width: 376, height: 380))
    }

    @Test func downBlocksSwapColumnsAndLines() throws {
        let b = try #require(M.layout.frames.first { $0.block.id == M.b.id })
        #expect(b.columns == M.b.rowCount)
        #expect(b.lines == M.b.treesPerRow)
    }

    @Test func cellRectsForAcrossAndDownBlocks() {
        let layout = M.layout
        #expect(layout.cellRect(F.tree(M.a, 2, 3)) == CGRect(x: 110, y: 70, width: 26, height: 15))
        #expect(layout.cellRect(F.tree(M.b, 1, 4)) == CGRect(x: 214, y: 100, width: 26, height: 15))
        #expect(layout.cellRect(F.tree(M.d, 9, 2)) == CGRect(x: 84, y: 335, width: 26, height: 15))
        #expect(layout.cellRect(F.tree(M.a, 5, 0)) == nil)
        #expect(layout.cellRect(F.tree(M.a, 0, 4)) == nil)
        #expect(layout.cellRect(F.tree(M.gone, 0, 0)) == nil)
    }

    @Test func rowHeadersSitLeftOrAbove() {
        let layout = M.layout
        #expect(layout.rowHeaderRect(F.row(M.a, 2)) == CGRect(x: 0, y: 70, width: 26, height: 15))
        #expect(layout.rowHeaderRect(F.row(M.b, 1)) == CGRect(x: 214, y: 0, width: 26, height: 34))
        #expect(layout.rowHeaderRect(F.row(M.a, 5)) == nil)
        #expect(layout.rowHeaderRect(F.row(M.gone, 0)) == nil)
    }

    @Test func emptyFieldHasNoSize() {
        let layout = FieldLayout(blocks: [], metrics: .m)
        #expect(layout.frames.isEmpty)
        #expect(layout.size == .zero)
    }

    @Test func oneByOneBlock() {
        let tiny = F.block(1, rows: 1, trees: 1)
        let layout = FieldLayout(blocks: [tiny], metrics: .xs)
        #expect(layout.frames.first?.frame == CGRect(x: 0, y: 0, width: 50, height: 53))
        #expect(layout.size == CGSize(width: 50, height: 77))
        #expect(layout.cellRect(F.tree(tiny, 0, 0)) == CGRect(x: 32, y: 40, width: 12, height: 7))
    }

    @Test func threeHundredSquareBlock() {
        let big = F.block(1, rows: 300, trees: 300)
        let layout = FieldLayout(blocks: [big], metrics: .l)
        #expect(layout.size == CGSize(width: 26 + 300 * 36 + 12, height: 34 + 300 * 22 + 12 + 24))
        #expect(layout.cellRect(F.tree(big, 299, 299)) == CGRect(x: 32 + 299 * 36, y: 40 + 299 * 22, width: 36, height: 22))
    }

    // MARK: Overview

    @Test func overviewFitsTheWidestStripInTheWidth() {
        // Josh's field: 14 blocks of 61 rows × 10 trees across, in one strip, on a 390-point phone.
        let blocks = (0..<14).map { F.block($0 + 1, gridColumn: $0, rows: 61, trees: 10) }
        let metrics = MapMetrics.overview(blocks: blocks, width: 390)
        #expect(metrics.isOverview)
        #expect(metrics.cell == CGSize(width: 1.75, height: 1.75))
        #expect(metrics.rowLabelWidth == 0)
        let layout = FieldLayout(blocks: blocks, metrics: metrics)
        #expect(layout.size.width <= 390)
        #expect(layout.size.width == 14 * (4 + 17.5) + 13 * 5)
    }

    @Test func overviewSizesByTheStripNeedingTheSmallestCells() {
        let top = (0..<3).map { F.block($0 + 1, gridRow: 0, gridColumn: $0, rows: 5, trees: 10) }
        let wide = F.block(9, gridRow: 1, gridColumn: 0, rows: 5, trees: 50)
        let metrics = MapMetrics.overview(blocks: top + [wide], width: 400)
        #expect(metrics.cell.width == 7.75)
        #expect(FieldLayout(blocks: top + [wide], metrics: metrics).size.width <= 400)
    }

    @Test func overviewAtANarrowWidthClampsToOneAndAHalf() {
        let blocks = (0..<14).map { F.block($0 + 1, gridColumn: $0, rows: 61, trees: 10) }
        #expect(MapMetrics.overview(blocks: blocks, width: 100).cell == CGSize(width: 1.5, height: 1.5))
    }

    @Test func overviewOfOneSmallBlockCapsAtTwelve() {
        #expect(MapMetrics.overview(blocks: [F.block(1, rows: 2, trees: 2)], width: 390).cell.width == 12)
        #expect(MapMetrics.overview(blocks: [], width: 390).cell.width == 12)
    }

    @Test func overviewIgnoresDeletedBlocks() {
        let live = F.block(1, rows: 2, trees: 10)
        let gone = F.block(2, gridColumn: 1, rows: 2, trees: 300, deleted: true)
        #expect(MapMetrics.overview(blocks: [live, gone], width: 390) == MapMetrics.overview(blocks: [live], width: 390))
    }

    @Test func overviewHasNoRowHeaders() {
        let metrics = MapMetrics.overview(blocks: M.blocks, width: 390)
        #expect(FieldLayout(blocks: M.blocks, metrics: metrics).rowHeaderRect(F.row(M.a, 0)) == nil)
    }
}

@Suite("FieldLayout hit tests")
struct FieldLayoutHitTests {
    typealias F = TreeFixtures
    typealias M = MapFixture
    let layout = M.layout

    func hit(_ x: CGFloat, _ y: CGFloat) -> MapHit? { layout.hitTest(CGPoint(x: x, y: y)) }

    @Test func treesInsideTheGrid() {
        #expect(hit(111, 71) == .tree(F.tree(M.a, 2, 3)))
        #expect(hit(215, 101) == .tree(F.tree(M.b, 1, 4)))
        #expect(hit(40, 210) == .tree(F.tree(M.d, 0, 0)))
        #expect(hit(109, 349) == .tree(F.tree(M.d, 9, 2)))
    }

    @Test func cellEdgesBelongToTheCellThatStartsThere() {
        #expect(hit(32, 40) == .tree(F.tree(M.a, 0, 0)))
        #expect(hit(58, 40) == .tree(F.tree(M.a, 0, 1)))
        #expect(hit(57.99, 54.99) == .tree(F.tree(M.a, 0, 0)))
        #expect(hit(58, 55) == .tree(F.tree(M.a, 1, 1)))
        #expect(hit(135.99, 114.99) == .tree(F.tree(M.a, 4, 3)))
    }

    @Test func theBorderPaddingSnapsToTheNearestTree() {
        #expect(hit(139, 50) == .tree(F.tree(M.a, 0, 3)))   // right of the grid, inside the border
        #expect(hit(29, 50) == .tree(F.tree(M.a, 0, 0)))    // left of the grid, inside the border
        #expect(hit(25, 50) == .row(F.row(M.a, 0)))         // left of the border is the label gutter
        #expect(hit(50, 36) == .tree(F.tree(M.a, 0, 0)))    // above the grid, inside the border
        #expect(hit(50, 120) == .tree(F.tree(M.a, 4, 0)))   // below the grid, inside the border
    }

    @Test func rowLabelGutterOfAnAcrossBlock() {
        #expect(hit(10, 72) == .row(F.row(M.a, 2)))
        #expect(hit(0, 40) == .row(F.row(M.a, 0)))
        #expect(hit(10, 38) == .row(F.row(M.a, 0)))   // 2 points of slack above
        #expect(hit(10, 37) == nil)
        #expect(hit(10, 116) == .row(F.row(M.a, 4)))  // 2 points of slack below
        #expect(hit(10, 117) == nil)
    }

    @Test func headerAboveAnAcrossBlockIsNotARow() {
        #expect(hit(50, 10) == nil)
        #expect(hit(10, 10) == nil)
    }

    @Test func columnHeaderOfADownBlockIsARow() {
        #expect(hit(219, 10) == .row(F.row(M.b, 1)))
        #expect(hit(188, 0) == .row(F.row(M.b, 0)))
        #expect(hit(270, 20) == .row(F.row(M.b, 2)))  // header over the right padding clamps to the last row
    }

    @Test func downBlocksHaveNoLabelGutterButHaveAFooter() {
        #expect(hit(160, 60) == nil)
        #expect(hit(190, 146) == .row(F.row(M.b, 0)))
        #expect(hit(250, 159) == .row(F.row(M.b, 2)))
        #expect(hit(250, 160) == nil)
    }

    @Test func gapsAndEmptyStripSpaceHitNothing() {
        #expect(hit(142, 50) == nil)   // the gap right of A
        #expect(hit(150, 50) == nil)
        #expect(hit(50, 125) == nil)   // under A, which is shorter than its strip
        #expect(hit(330, 100) == nil)  // under C
        #expect(hit(50, 150) == nil)   // the gap between strips
        #expect(hit(200, 250) == nil)  // right of D in the second strip
    }

    @Test func outsideTheMapHitsNothing() {
        #expect(hit(-1, 50) == nil)
        #expect(hit(50, -1) == nil)
        #expect(hit(376, 50) == nil)
        #expect(hit(5000, 5000) == nil)
    }

    @Test func overviewTapsPickABlock() throws {
        let metrics = MapMetrics.overview(blocks: M.blocks, width: 390)
        let layout = FieldLayout(blocks: M.blocks, metrics: metrics)
        let a = try #require(layout.frame(of: M.a.id))
        let d = try #require(layout.frame(of: M.d.id))
        #expect(layout.hitTest(CGPoint(x: a.frame.midX, y: a.frame.midY)) == .block(M.a.id))
        #expect(layout.hitTest(CGPoint(x: a.frame.minX + 1, y: a.frame.minY + 1)) == .block(M.a.id))
        #expect(layout.hitTest(CGPoint(x: a.frame.maxX + 1, y: a.frame.midY)) == .block(M.a.id))  // half the gap
        #expect(layout.hitTest(CGPoint(x: d.grid.minX, y: d.grid.minY)) == .block(M.d.id))
        #expect(layout.hitTest(CGPoint(x: 1000, y: 1000)) == nil)
    }

    @Test func lastTreeOfAThreeHundredSquareBlock() throws {
        let big = F.block(1, rows: 300, trees: 300, direction: .down)
        let layout = FieldLayout(blocks: [big], metrics: .xs)
        let cell = try #require(layout.cellRect(F.tree(big, 299, 299)))
        #expect(layout.hitTest(CGPoint(x: cell.midX, y: cell.midY)) == .tree(F.tree(big, 299, 299)))
        #expect(layout.hitTest(CGPoint(x: cell.midX, y: 5)) == .row(F.row(big, 299)))
    }

    @Test func everyCellHitsItsOwnTree() throws {
        for block in [M.a, M.b, M.c, M.d] {
            for row in 0..<block.rowCount {
                for position in 0..<block.treesPerRow {
                    let tree = F.tree(block, row, position)
                    let cell = try #require(layout.cellRect(tree))
                    #expect(layout.hitTest(CGPoint(x: cell.midX, y: cell.midY)) == .tree(tree))
                    #expect(layout.hitTest(cell.origin) == .tree(tree))
                }
            }
        }
    }

    @Test func everyRowHeaderHitsItsRow() throws {
        for block in [M.a, M.b, M.c, M.d] {
            for row in 0..<block.rowCount {
                let rect = try #require(layout.rowHeaderRect(F.row(block, row)))
                #expect(layout.hitTest(CGPoint(x: rect.midX, y: rect.midY)) == .row(F.row(block, row)))
            }
        }
    }
}
