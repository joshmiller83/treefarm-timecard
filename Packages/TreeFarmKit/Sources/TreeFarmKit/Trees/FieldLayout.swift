import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// Map geometry for the SwiftUI Canvas. Pure math, so the view only draws and the
// tests can check every point. CGRect and friends come from CoreGraphics on Apple
// platforms and from Foundation on Linux.

/// Sizes for one zoom level. Ports the artifact's ZOOMS and its "All" fit-to-width overview.
public struct MapMetrics: Equatable, Sendable {
    /// One tree's cell: width along a line, height between lines.
    public var cell: CGSize
    /// Row numbers to the left of an across block.
    public var rowLabelWidth: CGFloat
    /// Padding between a block's border and its trees.
    public var inset: CGFloat
    /// Space between blocks in a strip.
    public var blockGap: CGFloat
    /// Space under each strip. It holds a down block's bottom row numbers.
    public var stripGap: CGFloat
    /// The block name and the tree (across) or row (down) numbers above each block.
    public var headerHeight: CGFloat
    /// The fit-to-width overview: tiny square cells, no labels, a tap picks a block.
    public var isOverview: Bool

    public init(cell: CGSize, rowLabelWidth: CGFloat, inset: CGFloat, blockGap: CGFloat, stripGap: CGFloat, headerHeight: CGFloat, isOverview: Bool) {
        self.cell = cell
        self.rowLabelWidth = rowLabelWidth
        self.inset = inset
        self.blockGap = blockGap
        self.stripGap = stripGap
        self.headerHeight = headerHeight
        self.isOverview = isOverview
    }

    public static let xs = zoom(12, 7)
    public static let s = zoom(18, 10)
    public static let m = zoom(26, 15)
    public static let l = zoom(36, 22)

    private static func zoom(_ w: CGFloat, _ h: CGFloat) -> MapMetrics {
        MapMetrics(cell: CGSize(width: w, height: h), rowLabelWidth: 26, inset: 6, blockGap: 14, stripGap: 24, headerHeight: 34, isOverview: false)
    }

    /// Square cells sized so the widest strip fits `width` (in quarter points, 1.5...12), with no labels.
    public static func overview(blocks: [Block], width: CGFloat) -> MapMetrics {
        var metrics = MapMetrics(cell: .zero, rowLabelWidth: 0, inset: 2, blockGap: 5, stripGap: 4, headerHeight: 18, isOverview: true)
        var side: CGFloat = 12
        for strip in FieldLayout.strips(blocks) {
            let n = CGFloat(strip.count)
            let columns = strip.reduce(0) { $0 + FieldLayout.shape($1).columns }
            let room = width - 4 - n * 2 * metrics.inset - (n - 1) * metrics.blockGap
            side = min(side, room / CGFloat(max(1, columns)))
        }
        side = max(1.5, min(12, (side * 4).rounded(.down) / 4))
        metrics.cell = CGSize(width: side, height: side)
        return metrics
    }
}

/// What a tap on the map landed on.
public enum MapHit: Equatable, Sendable {
    case tree(TreeRef)
    case row(RowRef)
    case block(UUID)
}

/// Where one block sits on the map.
public struct BlockFrame: Equatable, Sendable {
    public var block: Block
    /// Everything that belongs to the block: label gutter, header, border, and a down block's footer.
    public var frame: CGRect
    /// The block's rounded border.
    public var outline: CGRect
    /// The trees: `columns × lines` cells.
    public var grid: CGRect
    /// Cells across: trees per row (across) or rows (down).
    public var columns: Int
    /// Cells down: rows (across) or trees per row (down).
    public var lines: Int

    public var isDown: Bool { block.direction == .down }
}

/// Blocks sit in strips: one strip per gridRow (top to bottom), blocks left to right
/// by gridColumn in a strip. A strip is as tall as its tallest block; the map is as
/// wide as its widest strip. "down" blocks swap columns and lines.
public struct FieldLayout: Sendable {
    public var metrics: MapMetrics
    public var frames: [BlockFrame]
    public var size: CGSize

    public init(blocks: [Block], metrics: MapMetrics) {
        self.metrics = metrics
        let m = metrics
        var frames: [BlockFrame] = []
        var width: CGFloat = 0
        var y: CGFloat = 0
        for strip in Self.strips(blocks) {
            var x: CGFloat = 0
            var tallest = 0
            for block in strip {
                let (columns, lines) = Self.shape(block)
                let outline = CGRect(x: x + m.rowLabelWidth, y: y + m.headerHeight,
                                     width: CGFloat(columns) * m.cell.width + 2 * m.inset,
                                     height: CGFloat(lines) * m.cell.height + 2 * m.inset)
                let footer = block.direction == .down && !m.isOverview ? m.stripGap : 0
                let frame = CGRect(x: x, y: y, width: m.rowLabelWidth + outline.width, height: m.headerHeight + outline.height + footer)
                frames.append(BlockFrame(block: block, frame: frame, outline: outline,
                                         grid: outline.insetBy(dx: m.inset, dy: m.inset), columns: columns, lines: lines))
                x += frame.width + m.blockGap
                tallest = max(tallest, lines)
            }
            width = max(width, x - m.blockGap)
            y += m.headerHeight + 2 * m.inset + CGFloat(tallest) * m.cell.height + m.stripGap
        }
        self.frames = frames
        self.size = frames.isEmpty ? .zero : CGSize(width: width, height: y)
    }

    public func frame(of blockId: UUID) -> BlockFrame? {
        frames.first { $0.block.id == blockId }
    }

    public func cellRect(_ tree: TreeRef) -> CGRect? {
        guard let f = frame(of: tree.blockId), f.block.contains(tree) else { return nil }
        let column = f.isDown ? tree.row : tree.position
        let line = f.isDown ? tree.position : tree.row
        return CGRect(x: f.grid.minX + CGFloat(column) * metrics.cell.width, y: f.grid.minY + CGFloat(line) * metrics.cell.height,
                      width: metrics.cell.width, height: metrics.cell.height)
    }

    /// Where a row's number sits: left of an across block's row, above a down block's column. Nil in the overview.
    public func rowHeaderRect(_ row: RowRef) -> CGRect? {
        guard !metrics.isOverview, let f = frame(of: row.blockId), f.block.contains(row) else { return nil }
        if f.isDown {
            return CGRect(x: f.grid.minX + CGFloat(row.row) * metrics.cell.width, y: f.frame.minY, width: metrics.cell.width, height: metrics.headerHeight)
        }
        return CGRect(x: f.frame.minX, y: f.grid.minY + CGFloat(row.row) * metrics.cell.height, width: metrics.rowLabelWidth, height: metrics.cell.height)
    }

    /// What a point on the map lands on. In the overview any point on or near a block
    /// picks the block. Otherwise: a tree inside the border (the padding snaps to the
    /// nearest tree), a row in an across block's label gutter or a down block's
    /// column header and footer, and nil for gaps, headers of across blocks and outside.
    public func hitTest(_ point: CGPoint) -> MapHit? {
        if metrics.isOverview {
            let reach = frames.first { $0.frame.insetBy(dx: -metrics.blockGap / 2, dy: -metrics.stripGap / 2).contains(point) }
            return reach.map { .block($0.block.id) }
        }
        guard let f = frames.first(where: { $0.frame.contains(point) }), f.columns > 0, f.lines > 0 else { return nil }
        let (x, y) = (point.x, point.y)
        let line = Self.clamp(((y - f.grid.minY) / metrics.cell.height).rounded(.down), f.lines)
        if x < f.outline.minX {
            guard !f.isDown, y >= f.grid.minY - 2, y < f.grid.maxY + 2 else { return nil }
            return .row(RowRef(blockId: f.block.id, row: line))
        }
        let column = Self.clamp(((x - f.grid.minX) / metrics.cell.width).rounded(.down), f.columns)
        if y < f.outline.minY || y >= f.outline.maxY {
            return f.isDown ? .row(RowRef(blockId: f.block.id, row: column)) : nil
        }
        return .tree(f.isDown ? TreeRef(blockId: f.block.id, row: column, position: line)
                              : TreeRef(blockId: f.block.id, row: line, position: column))
    }

    private static func clamp(_ value: CGFloat, _ count: Int) -> Int {
        Int(max(0, min(value, CGFloat(count - 1))))
    }

    // MARK: - Strips

    /// Live blocks grouped by gridRow, top to bottom, each strip in walk order.
    static func strips(_ blocks: [Block]) -> [[Block]] {
        let live = blocks.filter { $0.deletedAt == nil }.sorted(by: FieldWalker.walksBefore)
        var strips: [[Block]] = []
        for block in live {
            if let last = strips.last?.last, last.gridRow == block.gridRow {
                strips[strips.count - 1].append(block)
            } else {
                strips.append([block])
            }
        }
        return strips
    }

    static func shape(_ block: Block) -> (columns: Int, lines: Int) {
        let rows = max(0, block.rowCount), trees = max(0, block.treesPerRow)
        return block.direction == .down ? (rows, trees) : (trees, rows)
    }
}
