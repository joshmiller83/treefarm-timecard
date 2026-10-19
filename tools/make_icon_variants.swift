import AppKit
import CoreGraphics

// Draws the Time Card icon (a pale fir with a sap-gold clock) in its three looks: the
// default, dark, and tinted (grayscale on black, which iOS tints).
// Usage: swift tools/make_icon_variants.swift <AppIcon.appiconset folder>

struct Look {
    var bgTop: CGColor
    var bgBottom: CGColor
    var tree: CGColor
    var clockEdge: CGColor
    var ring: CGColor
    var face: CGColor
    var hands: CGColor
}

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

func draw(_ look: Look, to url: URL) {
    let s: CGFloat = 1024
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    let g = CGGradient(colorsSpace: cs, colors: [look.bgTop, look.bgBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s), options: [])

    // The fir: three stepped tiers and a trunk, centred at x = 470.
    ctx.setFillColor(look.tree)
    func poly(_ points: [(CGFloat, CGFloat)]) {
        ctx.move(to: CGPoint(x: points[0].0, y: points[0].1))
        for p in points.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
        ctx.closePath()
        ctx.fillPath()
    }
    poly([(470, 153), (640, 383), (300, 383)])
    poly([(372, 383), (567, 383), (705, 553), (235, 553)])
    poly([(323, 553), (617, 553), (770, 733), (170, 733)])
    ctx.fill(CGRect(x: 428, y: 733, width: 84, height: 120))

    // The clock, over the tree's lower right.
    let c = CGPoint(x: 712, y: 723)
    func disc(_ r: CGFloat, _ color: CGColor) {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    disc(208, look.clockEdge)
    disc(182, look.ring)
    disc(148, look.face)
    ctx.setStrokeColor(look.hands)
    ctx.setLineCap(.round)
    ctx.setLineWidth(30)
    ctx.move(to: CGPoint(x: 712, y: 618))
    ctx.addLine(to: c)
    ctx.addLine(to: CGPoint(x: 793, y: 731))
    ctx.strokePath()
    disc(22, look.hands)

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dark = Look(bgTop: rgb(0x16241C), bgBottom: rgb(0x0B120E), tree: rgb(0xE3ECE4), clockEdge: rgb(0x0E1712),
                ring: rgb(0xE2A644), face: rgb(0xF4F7F1), hands: rgb(0x14221A))
// Tinted icons are grayscale on black; iOS applies the person's tint.
let tinted = Look(bgTop: rgb(0x000000), bgBottom: rgb(0x000000), tree: rgb(0xFFFFFF), clockEdge: rgb(0x000000),
                  ring: rgb(0xB4B4B4), face: rgb(0xE6E6E6), hands: rgb(0x2E2E2E))
let light = Look(bgTop: rgb(0x2C7149), bgBottom: rgb(0x1A4B31), tree: rgb(0xECF1EC), clockEdge: rgb(0x1C4E33),
                 ring: rgb(0xE2A644), face: rgb(0xFAFCF9), hands: rgb(0x14221A))
if CommandLine.arguments.count > 2 {
    // A look at the default too, to compare with the shipped icon.
    draw(light, to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
draw(dark, to: out.appendingPathComponent("AppIcon-dark.png"))
draw(tinted, to: out.appendingPathComponent("AppIcon-tinted.png"))
print("wrote dark and tinted icons to \(out.path)")
