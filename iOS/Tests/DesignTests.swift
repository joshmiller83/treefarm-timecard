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
}
