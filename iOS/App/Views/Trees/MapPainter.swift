import CoreGraphics
import CoreText
import os
import SwiftUI
import TimeCardCore
import UIKit

/// The map's "not yet" rings and block outlines. Outdoors, in sunlight, they reach at least
/// 3:1 against the map in both themes (WCAG 1.4.11) by default, and the asset catalog's High
/// Contrast appearances make them stronger still with Increase Contrast.
enum MapColors {
    static let treeEmpty = UIColor(named: "TreeEmpty") ?? .gray
    static let blockLine = UIColor(named: "BlockLine") ?? .gray
}

extension Color {
    /// "Not shaped yet" rings, stronger with Increase Contrast.
    static let mapTreeEmpty = Color(uiColor: MapColors.treeEmpty)
    /// Shaped trees as the map draws them: fir, or text fir on a dark map.
    static let mapDone = Color(uiColor: UIColor { traits in
        (UIColor(named: traits.userInterfaceStyle == .dark ? "FirText" : "Fir") ?? .systemGreen).resolvedColor(with: traits)
    })
}

/// The map's colors, resolved for light or dark and the contrast setting, as Core Graphics colors.
struct MapPalette {
    var empty: CGColor
    var done: CGColor
    var mine: CGColor
    var muted: CGColor
    var ink: CGColor
    var stripe: CGColor
    var line: CGColor
    var firText: CGColor
    var note: CGColor
    var focus: CGColor
    var surface: CGColor
    /// Increase Contrast is on: rings and outlines draw heavier too.
    var highContrast: Bool

    init(traits: UITraitCollection) {
        func color(_ name: String) -> CGColor {
            (UIColor(named: name) ?? .gray).resolvedColor(with: traits).cgColor
        }
        empty = MapColors.treeEmpty.resolvedColor(with: traits).cgColor
        // Shaped trees: fir, or the lighter text fir on a dark map, where fir is too dim.
        done = color(traits.userInterfaceStyle == .dark ? "FirText" : "Fir")
        mine = color("Sap")
        muted = color("Muted")
        ink = color("Ink")
        stripe = color("Stripe")
        line = MapColors.blockLine.resolvedColor(with: traits).cgColor
        firText = color("FirText")
        note = color("Rust")
        focus = color("Ink")
        surface = color("Surface")
        highContrast = traits.accessibilityContrast == .high
    }

    /// Light or dark, normal or Increase Contrast.
    static func traits(dark: Bool, highContrast: Bool) -> UITraitCollection {
        UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: highContrast ? .high : .normal),
        ])
    }
}

/// Everything one frame of the map shows. The painter only reads it.
struct MapScene {
    var layout: FieldLayout
    var index: MarkIndex
    /// Marks on this shift draw gold; every other mark draws green.
    var markingShiftId: UUID?
    /// Trees with notes get a small corner marker.
    var noteTrees: Set<TreeRef>
    /// Fill mode's first tree.
    var anchor: TreeRef?
    /// The tree whose card is open.
    var focus: TreeRef?
    /// Differentiate Without Color: this shift's dots get a hole in the middle, so they
    /// read apart from earlier ones by shape as well as gold and green.
    var pips = false

    static let empty = MapScene(layout: FieldLayout(blocks: [], metrics: .m), index: MarkIndex(marks: []),
                                markingShiftId: nil, noteTrees: [], anchor: nil, focus: nil)

    /// The strip of the map one row lives in: its number, its trees and (down blocks) its footer.
    func band(of row: RowRef) -> CGRect? {
        guard let f = layout.frame(of: row.blockId), f.block.contains(row) else { return nil }
        let m = layout.metrics
        if f.isDown {
            let x = f.grid.minX + CGFloat(row.row) * m.cell.width
            return CGRect(x: x - 1, y: f.frame.minY, width: m.cell.width + 2, height: f.frame.height)
        }
        let y = f.grid.minY + CGFloat(row.row) * m.cell.height
        return CGRect(x: f.frame.minX, y: y - 1, width: f.frame.width, height: m.cell.height + 2)
    }
}

/// Draws any rectangle of the map, the way the artifact's canvas did: blocks as rounded
/// outlines with striped columns, trees as rings (not yet), green dots (shaped earlier) and
/// gold dots (this shift), row and tree numbers around each block, note markers in the corner.
/// Only the cells inside the rectangle are visited, so a tile of a huge field stays cheap.
struct MapPainter: @unchecked Sendable {
    var scene: MapScene
    var palette: MapPalette

    private var metrics: MapMetrics { scene.layout.metrics }

    func draw(_ rect: CGRect, in ctx: CGContext) {
        for frame in scene.layout.frames where frame.frame.insetBy(dx: -40, dy: -4).intersects(rect) {
            drawBlock(frame, rect: rect, ctx: ctx)
        }
    }

    // MARK: One block

    private func drawBlock(_ f: BlockFrame, rect: CGRect, ctx: CGContext) {
        let m = metrics
        let cw = m.cell.width, ch = m.cell.height
        drawName(f, ctx: ctx)

        if !m.isOverview {
            // Every other column gets a soft stripe, and a faint guide every ten lines.
            ctx.setFillColor(palette.stripe)
            for c in visible(columns: f, rect) where c % 2 == 1 {
                ctx.fill(CGRect(x: f.grid.minX + CGFloat(c) * cw, y: f.grid.minY - 2, width: cw, height: CGFloat(f.lines) * ch + 4))
            }
            ctx.setStrokeColor(palette.line.copy(alpha: 0.45) ?? palette.line)
            ctx.setLineWidth(1)
            var g = 10
            while g < f.lines {
                let y = f.grid.minY + CGFloat(g) * ch + 0.5
                ctx.move(to: CGPoint(x: f.grid.minX, y: y))
                ctx.addLine(to: CGPoint(x: f.grid.maxX, y: y))
                g += 10
            }
            ctx.strokePath()
        }

        let radius: CGFloat = m.isOverview ? 3 : 8
        ctx.addPath(CGPath(roundedRect: f.outline.insetBy(dx: 0.75, dy: 0.75), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(palette.line)
        ctx.setLineWidth(m.isOverview ? 1 : (palette.highContrast ? 2 : 1.5))
        ctx.strokePath()

        drawTrees(f, rect: rect, ctx: ctx)
        if !m.isOverview {
            drawNumbers(f, rect: rect, ctx: ctx)
            drawNotes(f, rect: rect, ctx: ctx)
            if let anchor = scene.anchor, anchor.blockId == f.block.id { ring(anchor, color: palette.mine, width: 2.5, ctx: ctx) }
            if let focus = scene.focus, focus.blockId == f.block.id { ring(focus, color: palette.focus, width: 2, ctx: ctx) }
        }
    }

    private func drawTrees(_ f: BlockFrame, rect: CGRect, ctx: CGContext) {
        let m = metrics
        let cw = m.cell.width, ch = m.cell.height
        let small = min(cw, ch)
        let rad = max(1.8, small * 0.37)
        let radEmpty = max(1.4, rad * 0.68)
        let square = m.isOverview ? max(1, cw - (cw >= 4 ? 1 : 0.35)) : 0
        let pip = scene.pips && !m.isOverview ? max(1, rad * 0.4) : 0
        let empty = CGMutablePath(), done = CGMutablePath(), mine = CGMutablePath(), pips = CGMutablePath()
        let columns = visible(columns: f, rect), lines = visible(lines: f, rect)
        for c in columns {
            for l in lines {
                let tree = f.isDown ? TreeRef(blockId: f.block.id, row: c, position: l) : TreeRef(blockId: f.block.id, row: l, position: c)
                let x = f.grid.minX + CGFloat(c) * cw, y = f.grid.minY + CGFloat(l) * ch
                let mark = scene.index.mark(at: tree)
                let isMine = mark != nil && mark?.shiftId == scene.markingShiftId
                let path = mark == nil ? empty : (isMine ? mine : done)
                if m.isOverview {
                    path.addRect(CGRect(x: x, y: y, width: square, height: square))
                } else {
                    let r = mark == nil ? radEmpty : rad
                    path.addEllipse(in: CGRect(x: x + cw / 2 - r, y: y + ch / 2 - r, width: 2 * r, height: 2 * r))
                    if pip > 0, isMine {
                        pips.addEllipse(in: CGRect(x: x + cw / 2 - pip, y: y + ch / 2 - pip, width: 2 * pip, height: 2 * pip))
                    }
                }
            }
        }
        if m.isOverview {
            ctx.setFillColor(palette.empty.copy(alpha: 0.45) ?? palette.empty)
            ctx.addPath(empty)
            ctx.fillPath()
        } else {
            ctx.setStrokeColor(palette.empty)
            ctx.setLineWidth(Self.ringWidth(cell: small, highContrast: palette.highContrast))
            ctx.addPath(empty)
            ctx.strokePath()
        }
        ctx.setFillColor(palette.done)
        ctx.addPath(done)
        ctx.fillPath()
        ctx.setFillColor(palette.mine)
        ctx.addPath(mine)
        ctx.fillPath()
        if pip > 0 {
            ctx.setFillColor(palette.surface)
            ctx.addPath(pips)
            ctx.fillPath()
        }
    }

    /// A "not yet" ring's stroke: 2 pt at S, M and L so it reads in sunlight, thinner at XS where
    /// the rings are tiny, and heavier with Increase Contrast.
    static func ringWidth(cell: CGFloat, highContrast: Bool) -> CGFloat {
        let base: CGFloat = cell < 9 ? 1.2 : 2
        return highContrast ? base + 0.4 : base
    }

    // MARK: Labels

    private func drawName(_ f: BlockFrame, ctx: CGContext) {
        let m = metrics
        let name = f.block.displayName
        if m.isOverview {
            let font = UIFont.systemFont(ofSize: 10, weight: .bold)
            let room = f.outline.width + m.blockGap
            let short = name.size(withAttributes: [.font: font]).width <= room ? name : f.block.name
            text(short, font: font, color: palette.ink, x: f.outline.minX, baseline: f.frame.minY + 12, align: .left, ctx: ctx)
        } else {
            let font = UIFont(name: Typeface.headingSemiBold, size: 14) ?? .systemFont(ofSize: 13, weight: .semibold)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: f.frame.minX, y: f.frame.minY, width: f.frame.width + m.blockGap - 2, height: m.headerHeight - 14))
            text(name, font: font, color: palette.ink, x: f.outline.minX + 1, baseline: f.frame.minY + 14, align: .left, ctx: ctx)
            ctx.restoreGState()
        }
    }

    private func drawNumbers(_ f: BlockFrame, rect: CGRect, ctx: CGContext) {
        let m = metrics
        let cw = m.cell.width, ch = m.cell.height
        let small = min(cw, ch)
        let size: CGFloat = small >= 14 ? 11 : 9.5
        let regular = UIFont(name: Typeface.numberMedium, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
        let bold = UIFont(name: Typeface.numberSemiBold, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        let caption = UIFont.systemFont(ofSize: size - 0.5, weight: .semibold)
        let topBaseline = f.frame.minY + 29

        // Across the top: tree numbers (across blocks) or row numbers (down blocks, bold when done).
        for c in visible(columns: f, rect.insetBy(dx: -cw, dy: 0)) {
            let full = f.isDown && scene.index.isRowComplete(RowRef(blockId: f.block.id, row: c), block: f.block)
            if !full && cw < 16 && !(c == 0 || (c + 1) % 5 == 0) { continue }
            let x = f.grid.minX + CGFloat(c) * cw + cw / 2
            text("\(c + 1)", font: full ? bold : regular, color: full ? palette.firText : palette.muted, x: x, baseline: topBaseline, align: .center, ctx: ctx)
            if f.isDown {
                text("\(c + 1)", font: full ? bold : regular, color: full ? palette.firText : palette.muted, x: x, baseline: f.outline.maxY + 15, align: .center, ctx: ctx)
            }
        }
        text(f.isDown ? "Tree" : "Row", font: caption, color: palette.muted, x: f.outline.minX - 3, baseline: topBaseline, align: .right, ctx: ctx)

        // Down the left: row numbers (across blocks, bold when done) or tree numbers (down blocks).
        var every = ch >= 13 ? 1 : (ch >= 8 ? 5 : 10)
        if f.isDown { every = max(5, every) }
        for l in visible(lines: f, rect.insetBy(dx: 0, dy: -ch)) {
            let last = l == f.lines - 1 && (every == 1 || (l + 1) % every >= Int(Double(every) * 0.6))
            guard l == 0 || (l + 1) % every == 0 || last else { continue }
            let full = !f.isDown && scene.index.isRowComplete(RowRef(blockId: f.block.id, row: l), block: f.block)
            let y = f.grid.minY + CGFloat(l) * ch + ch / 2 + size * 0.36
            text("\(l + 1)", font: full ? bold : regular, color: full ? palette.firText : palette.muted, x: f.outline.minX - 3, baseline: y, align: .right, ctx: ctx)
        }
    }

    private func drawNotes(_ f: BlockFrame, rect: CGRect, ctx: CGContext) {
        guard !scene.noteTrees.isEmpty else { return }
        let m = metrics
        let side = max(3, min(8, min(m.cell.width, m.cell.height) * 0.42))
        let path = CGMutablePath()
        for tree in scene.noteTrees where tree.blockId == f.block.id {
            guard let cell = scene.layout.cellRect(tree), cell.intersects(rect) else { continue }
            let corner = CGPoint(x: cell.maxX - 0.5, y: cell.minY + 0.5)
            path.move(to: corner)
            path.addLine(to: CGPoint(x: corner.x - side, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + side))
            path.closeSubpath()
        }
        ctx.setFillColor(palette.note)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func ring(_ tree: TreeRef, color: CGColor, width: CGFloat, ctx: CGContext) {
        guard let cell = scene.layout.cellRect(tree) else { return }
        let box = cell.insetBy(dx: 1, dy: 0.5)
        ctx.addPath(CGPath(roundedRect: box, cornerWidth: min(4, box.height / 3), cornerHeight: min(4, box.height / 3), transform: nil))
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }

    // MARK: Helpers

    private func visible(columns f: BlockFrame, _ rect: CGRect) -> Range<Int> {
        span(rect.minX - f.grid.minX, rect.maxX - f.grid.minX, step: metrics.cell.width, count: f.columns)
    }

    private func visible(lines f: BlockFrame, _ rect: CGRect) -> Range<Int> {
        span(rect.minY - f.grid.minY, rect.maxY - f.grid.minY, step: metrics.cell.height, count: f.lines)
    }

    private func span(_ low: CGFloat, _ high: CGFloat, step: CGFloat, count: Int) -> Range<Int> {
        guard step > 0, count > 0 else { return 0..<0 }
        let first = max(0, Int((low / step).rounded(.down)))
        let last = min(count, Int((high / step).rounded(.up)))
        return first < last ? first..<last : 0..<0
    }

    private enum Align { case left, center, right }

    /// Draws a label from the shared cache of laid-out lines (row and tree numbers repeat on
    /// every tile), with Core Text, so tiles can be drawn off the main thread.
    private func text(_ s: String, font: UIFont, color: CGColor, x: CGFloat, baseline: CGFloat, align: Align, ctx: CGContext) {
        let (line, width) = MapLabels.shared.line(s, font: font, color: color)
        let left = switch align {
        case .left: x
        case .center: x - width / 2
        case .right: x - width
        }
        ctx.saveGState()
        // The map's context runs y downward; Core Text draws y upward.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: left, y: baseline)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

/// Laid-out map labels ("14", "Row", "Block 2"), kept so each is shaped once, not on every
/// tile it appears on. Shared by tiles drawn on any thread.
final class MapLabels: @unchecked Sendable {
    static let shared = MapLabels()

    private struct Key: Hashable {
        var text: String
        var font: String
        var size: CGFloat
        var color: [CGFloat]
    }

    /// Lines are immutable once made, so sharing them across threads is safe.
    private struct Entry: @unchecked Sendable {
        var line: CTLine
        var width: CGFloat
    }

    private let cache = OSAllocatedUnfairLock<[Key: Entry]>(initialState: [:])

    func line(_ text: String, font: UIFont, color: CGColor) -> (CTLine, CGFloat) {
        let key = Key(text: text, font: font.fontName, size: font.pointSize, color: color.components ?? [])
        if let hit = cache.withLock({ $0[key] }) { return (hit.line, hit.width) }
        let attributed = NSAttributedString(string: text, attributes: [.font: font as CTFont, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let entry = Entry(line: line, width: width)
        cache.withLock { cache in
            if cache.count > 4000 { cache.removeAll() }
            cache[key] = entry
        }
        return (line, width)
    }
}
