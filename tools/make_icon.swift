import AppKit
import CoreGraphics

// Draws the Time Card app icon: a fir tree inside a clock ring.
// Usage: swift tools/make_icon.swift iOS/App/Assets.xcassets/AppIcon.appiconset

struct Palette {
    var bgTop: CGColor?
    var bgBottom: CGColor?
    var ring: CGColor
    var ticks: CGColor
    var tree: CGColor
    var treeShade: CGColor
    var trunk: CGColor
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func roundedTriangle(_ ctx: CGContext, apex: CGPoint, left: CGPoint, right: CGPoint, radius: CGFloat) {
    let p = CGMutablePath()
    let mid = CGPoint(x: (left.x + right.x) / 2, y: left.y)
    p.move(to: mid)
    p.addArc(tangent1End: right, tangent2End: apex, radius: radius)
    p.addArc(tangent1End: apex, tangent2End: left, radius: radius)
    p.addArc(tangent1End: left, tangent2End: right, radius: radius)
    p.closeSubpath()
    ctx.addPath(p)
}

func draw(size: Int, palette: Palette, to url: URL) {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so y grows downward, like design tools.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    let k = s / 1024

    if let top = palette.bgTop, let bottom = palette.bgBottom {
        let g = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])
    }

    // Clock ring.
    let center = CGPoint(x: 512 * k, y: 520 * k)
    let r: CGFloat = 352 * k
    ctx.setStrokeColor(palette.ring)
    ctx.setLineWidth(30 * k)
    ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Twelve ticks inside the ring; the quarter hours are longer.
    ctx.setStrokeColor(palette.ticks)
    ctx.setLineCap(.round)
    for i in 0..<12 {
        let a = CGFloat(i) / 12 * .pi * 2 - .pi / 2
        let major = i % 3 == 0
        // The tree points at 12 and the trunk stands at 6, so those two have no tick.
        if i == 0 || i == 6 { continue }
        let r0 = r - (major ? 74 : 54) * k
        let r1 = r - 34 * k
        ctx.setLineWidth((major ? 20 : 12) * k)
        ctx.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
        ctx.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
        ctx.strokePath()
    }

    // Trunk.
    ctx.setFillColor(palette.trunk)
    let trunk = CGRect(x: 476 * k, y: 700 * k, width: 72 * k, height: 112 * k)
    ctx.addPath(CGPath(roundedRect: trunk, cornerWidth: 12 * k, cornerHeight: 12 * k, transform: nil))
    ctx.fillPath()

    // Three tiers of the fir, bottom first so upper tiers overlap.
    let tiers: [(apexY: CGFloat, baseY: CGFloat, half: CGFloat)] = [
        (430, 730, 250),
        (330, 590, 200),
        (228, 450, 148),
    ]
    for (i, t) in tiers.enumerated() {
        ctx.setFillColor(i % 2 == 0 ? palette.tree : palette.treeShade)
        roundedTriangle(ctx, apex: CGPoint(x: 512 * k, y: t.apexY * k),
                        left: CGPoint(x: (512 - t.half) * k, y: t.baseY * k),
                        right: CGPoint(x: (512 + t.half) * k, y: t.baseY * k), radius: 30 * k)
        ctx.fillPath()
    }

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let light = Palette(bgTop: rgb(0x2B7D52), bgBottom: rgb(0x154A2E), ring: rgb(0xE2A644), ticks: rgb(0xF5E6C6, 0.9),
                    tree: rgb(0xF7F2E4), treeShade: rgb(0xE9E0C8), trunk: rgb(0xB57A12))
let dark = Palette(bgTop: rgb(0x16241C), bgBottom: rgb(0x0B120E), ring: rgb(0xE2A644), ticks: rgb(0xF3D9A4, 0.75),
                   tree: rgb(0x88CFA4), treeShade: rgb(0x74BD92), trunk: rgb(0xB57A12))
// Tinted icons are supplied as grayscale on black; iOS applies the tint.
let tinted = Palette(bgTop: rgb(0x000000), bgBottom: rgb(0x000000), ring: rgb(0xBDBDBD), ticks: rgb(0x9E9E9E),
                     tree: rgb(0xFFFFFF), treeShade: rgb(0xEDEDED), trunk: rgb(0x8A8A8A))

draw(size: 1024, palette: light, to: out.appendingPathComponent("AppIcon-light.png"))
draw(size: 1024, palette: dark, to: out.appendingPathComponent("AppIcon-dark.png"))
draw(size: 1024, palette: tinted, to: out.appendingPathComponent("AppIcon-tinted.png"))
print("wrote icons to \(out.path)")
