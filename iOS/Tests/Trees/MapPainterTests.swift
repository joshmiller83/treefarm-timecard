import CoreGraphics
import Foundation
import Testing
import TimeCardCore
import UIKit
@testable import TimeCard

@MainActor
@Suite("Map drawing")
struct MapPainterTests {
    private func scene(_ f: TreeMapFixture) -> MapScene {
        MapScene(layout: f.model.layout, index: f.model.data!.index, markingShiftId: f.model.markingShift?.id,
                 noteTrees: [], anchor: nil, focus: nil)
    }

    /// Draws `rect` of the map into a bitmap (1 point = 1 pixel) and returns the color at `point`.
    private func color(at point: CGPoint, drawing rect: CGRect, scene: MapScene,
                       traits: UITraitCollection = UITraitCollection(userInterfaceStyle: .light)) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let width = Int(rect.width), height = Int(rect.height)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Flip so y grows downward, like UIKit.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(rect)
        MapPainter(scene: scene, palette: MapPalette(traits: traits)).draw(rect, in: ctx)
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let x = Int(point.x - rect.minX), y = Int(point.y - rect.minY)
        let i = (y * width + x) * 4
        return (CGFloat(data[i]) / 255, CGFloat(data[i + 1]) / 255, CGFloat(data[i + 2]) / 255)
    }

    @Test func thisShiftIsGoldAndEarlierIsGreen() {
        let f = TreeMapFixture()
        f.model.toggle(f.tree(f.block1, row: 6, tree: 2))
        let scene = scene(f)
        let tile = CGRect(x: 0, y: 0, width: 256, height: 256)
        let gold = color(at: f.point(f.block1, row: 6, tree: 2), drawing: tile, scene: scene)
        #expect(gold.r > gold.b + 0.3, "sap gold")
        let green = color(at: f.point(f.block1, row: 1, tree: 2), drawing: tile, scene: scene)
        #expect(green.g > green.r + 0.1 && green.g > green.b, "fir green")
        let ring = color(at: f.point(f.block1, row: 9, tree: 2), drawing: tile, scene: scene)
        #expect(ring.r > 0.9 && ring.g > 0.9, "a ring's middle stays empty")
    }

    @Test func rowBandsCoverTheNumberAndEveryTree() throws {
        let f = TreeMapFixture()
        let scene = scene(f)
        let row = RowRef(blockId: f.block1.id, row: 4)
        let band = try #require(scene.band(of: row))
        #expect(band.contains(f.rowNumber(f.block1, row: 5)))
        #expect(band.contains(f.point(f.block1, row: 5, tree: 1)))
        #expect(band.contains(f.point(f.block1, row: 5, tree: 12)))
        #expect(!band.contains(f.point(f.block1, row: 6, tree: 1)))

        let down = RowRef(blockId: f.block3.id, row: 1)
        let column = try #require(scene.band(of: down))
        #expect(column.contains(f.rowNumber(f.block3, row: 2)))
        #expect(column.contains(f.point(f.block3, row: 2, tree: 4)))
        #expect(!column.contains(f.point(f.block3, row: 3, tree: 1)))
        #expect(scene.band(of: RowRef(blockId: f.block1.id, row: 99)) == nil)
    }

    /// WCAG contrast between two colors.
    private func contrast(_ a: CGColor, _ b: CGColor) -> CGFloat {
        func luminance(_ c: CGColor) -> CGFloat {
            let rgb = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)!.components!
            let lin = rgb.prefix(3).map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test(arguments: [false, true])
    func increaseContrastMakesRingsAndOutlinesReadOutdoors(dark: Bool) {
        let normal = MapPalette(traits: MapPalette.traits(dark: dark, highContrast: false))
        let high = MapPalette(traits: MapPalette.traits(dark: dark, highContrast: true))
        #expect(!normal.highContrast && high.highContrast)
        for background in [high.surface, high.stripe] {
            #expect(contrast(high.empty, background) >= 3, "not-yet rings reach 3:1")
            #expect(contrast(high.line, background) >= 3, "block outlines reach 3:1")
        }
        #expect(contrast(high.empty, high.surface) > contrast(normal.empty, normal.surface))
        #expect(normal.done == high.done, "the green and gold dots keep their look")
        #expect(MapPainter.ringWidth(cell: 15, highContrast: true) > MapPainter.ringWidth(cell: 15, highContrast: false))
        for cell: CGFloat in [10, 15, 22] {
            #expect(MapPainter.ringWidth(cell: cell, highContrast: false) == 2, "S, M and L rings are 2 pt")
        }
    }

    /// Outdoors with default settings, rings and outlines already reach 3:1, and shaped dots
    /// stand out on a dark map.
    @Test(arguments: [false, true])
    func theDefaultMapReadsInSunlight(dark: Bool) {
        let normal = MapPalette(traits: MapPalette.traits(dark: dark, highContrast: false))
        for background in [normal.surface, normal.stripe] {
            #expect(contrast(normal.empty, background) >= 3, "not-yet rings reach 3:1")
            #expect(contrast(normal.line, background) >= 3, "block outlines reach 3:1")
            #expect(contrast(normal.done, background) >= 3, "shaped dots reach 3:1")
        }
    }

    @Test func differentiateWithoutColorPutsAHoleInThisShiftsDots() {
        let f = TreeMapFixture()
        f.model.setZoom(.l)
        f.model.toggle(f.tree(f.block1, row: 6, tree: 2))
        var scene = scene(f)
        let tile = CGRect(x: 0, y: 0, width: 512, height: 512)
        let middle = f.point(f.block1, row: 6, tree: 2)
        let plain = color(at: middle, drawing: tile, scene: scene)
        #expect(plain.r > plain.b + 0.3, "solid gold")
        scene.pips = true
        let pip = color(at: middle, drawing: tile, scene: scene)
        #expect(pip.r > 0.9 && pip.g > 0.9 && pip.b > 0.9, "the middle shows the map behind it")
        let earlier = color(at: f.point(f.block1, row: 1, tree: 2), drawing: tile, scene: scene)
        #expect(earlier.g > earlier.r + 0.1, "earlier dots stay solid")
    }

    @Test func aTileOfTheWholeFarmDrawsQuickly() {
        let f = TreeMapFixture()
        let big = Field(farmId: f.farm.id, name: "Big Field", sortOrder: -1)
        f.snapshot.apply(.field(big))
        for i in 0..<14 {
            let block = Block(fieldId: big.id, name: "\(i + 1)", gridRow: 0, gridColumn: i, rowCount: 61, treesPerRow: 10)
            f.snapshot.apply(.block(block))
            for row in 0..<61 where i < 2 {
                for position in 0..<10 {
                    f.snapshot.apply(.treeMark(TreeMark(seasonId: f.season.id, tree: TreeRef(blockId: block.id, row: row, position: position),
                                                        shiftId: f.samShift.id, userId: f.sam.userId, markedAt: f.now)))
                }
            }
        }
        f.sync()
        f.model.chosenFieldId = big.id
        // One tile is drawn on the main thread as the map scrolls in: it has to fit in a couple
        // of frames. The best of a few runs, so a busy test machine doesn't decide the result.
        let clock = ContinuousClock()
        let tile = CGRect(x: 0, y: 0, width: TreeMapScrollView.tileSide, height: TreeMapScrollView.tileSide)
        let width = Int(tile.width)
        let ctx = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let palette = MapPalette(traits: UITraitCollection(userInterfaceStyle: .light))
        for zoom in MapZoom.allCases {
            f.model.setZoom(zoom)
            let painter = MapPainter(scene: scene(f), palette: palette)
            let best = (0..<5).map { _ in clock.measure { painter.draw(tile, in: ctx) } }.min()!
            #expect(best < .milliseconds(30), "\(zoom) took \(best)")
        }
    }
}
