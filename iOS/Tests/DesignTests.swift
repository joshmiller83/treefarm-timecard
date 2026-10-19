import SwiftUI
import Testing
import UIKit
@testable import TimeCard

@MainActor
@Suite("Design system")
struct DesignTests {
    @Test func bundledFontsAreRegistered() {
        for name in Typeface.all {
            #expect(UIFont(name: name, size: 17) != nil, "\(name) isn't registered; check UIAppFonts")
        }
        #expect(Typeface.allRegistered)
    }

    @Test func everyColorTokenHasLightAndDarkValues() throws {
        for (name, _) in Palette.all {
            let color = try #require(UIColor(named: name), "missing color set \(name)")
            let light = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            let dark = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            if !["FirInk", "Paper", "PaperInk"].contains(name) {
                #expect(light != dark, "\(name) should change in dark mode")
            }
        }
    }

    @Test func firMatchesTheArtifact() throws {
        let fir = try #require(UIColor(named: "Fir")).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        fir.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(Int((r * 255).rounded()) == 0x1D)
        #expect(Int((g * 255).rounded()) == 0x5B)
        #expect(Int((b * 255).rounded()) == 0x3A)
    }

    @Test func buttonsAreGloveSized() {
        #expect(GloveButtonStyle.minHeight >= 54)
    }

    /// Every text color on every fill it's used on, at 4.5:1 or more in light and dark.
    static let textOnFill: [(text: String, fill: String)] = [
        ("Ink", "Bg"), ("Ink", "Surface"), ("Ink", "Stripe"), ("Ink", "FirSoft"),
        ("Muted", "Bg"), ("Muted", "Surface"), ("Muted", "Stripe"),
        ("FirText", "Bg"), ("FirText", "Surface"), ("FirText", "FirSoft"), ("FirText", "Stripe"),
        ("FirInk", "Fir"), ("FirInk", "FirCard"), ("FirInk", "RustFill"),
        ("SapInk", "SapSoft"), ("SapSoft", "SapInk"),
        ("Rust", "Bg"), ("Rust", "Surface"),
        ("PaperInk", "Paper"),
    ]

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func textOnEveryFillPassesAA(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        for (text, fill) in Self.textOnFill {
            let t = try #require(UIColor(named: text)).resolvedColor(with: traits)
            let f = try #require(UIColor(named: fill)).resolvedColor(with: traits)
            let ratio = Self.contrast(t, f)
            #expect(ratio >= 4.5, "\(text) on \(fill) is \(String(format: "%.2f", ratio)):1 in \(style == .dark ? "dark" : "light") mode")
        }
    }

    /// The app's tint (and AccentColor, used before SwiftUI's tint applies) is text-colored:
    /// toolbar Save and Cancel, menus and pickers read on Bg and Surface in both modes.
    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func theTintReadsAsText(style: UIUserInterfaceStyle) throws {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let accent = try #require(UIColor(named: "AccentColor")).resolvedColor(with: traits)
        for fill in ["Bg", "Surface"] {
            let f = try #require(UIColor(named: fill)).resolvedColor(with: traits)
            #expect(Self.contrast(accent, f) >= 4.5, "AccentColor on \(fill)")
        }
    }

    /// WCAG contrast between two opaque colors.
    static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        func luminance(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            let lin = [r, g, b].map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
