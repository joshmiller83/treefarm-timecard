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
    private func color(at point: CGPoint, drawing rect: CGRect, scene: MapScene) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let width = Int(rect.width), height = Int(rect.height)
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Flip so y grows downward, like UIKit.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(rect)
        MapPainter(scene: scene, palette: MapPalette(traits: UITraitCollection(userInterfaceStyle: .light))).draw(rect, in: ctx)
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
        let clock = ContinuousClock()
        for zoom in MapZoom.allCases {
            f.model.setZoom(zoom)
            let scene = scene(f)
            let elapsed = clock.measure {
                _ = color(at: CGPoint(x: 10, y: 10), drawing: CGRect(x: 0, y: 0, width: 256, height: 256), scene: scene)
            }
            #expect(elapsed < .milliseconds(250), "\(zoom) took \(elapsed)")
        }
    }
}
