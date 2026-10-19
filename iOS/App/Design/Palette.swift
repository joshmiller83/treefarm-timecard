import SwiftUI

/// The time card's colors, carried over from the web artifact. Each is an asset-catalog
/// color set with a light and a dark value (App/Resources/Assets.xcassets/Colors).
enum Palette {
    /// Screen background.
    static let bg = Color("Bg")
    /// Cards and grouped surfaces.
    static let surface = Color("Surface")
    /// Main text.
    static let ink = Color("Ink")
    /// Secondary text and captions.
    static let muted = Color("Muted")
    /// Hairlines and card borders.
    static let line = Color("Line")
    /// Fir green: primary actions, "working".
    static let fir = Color("Fir")
    /// The working status card: fir in light mode, a deeper fir in dark mode so white text
    /// and the translucent buttons on it stay above 4.5:1.
    static let firCard = Color("FirCard")
    /// Text and icons on fir.
    static let firInk = Color("FirInk")
    /// Soft fir fill (status pill, selected rows).
    static let firSoft = Color("FirSoft")
    /// Fir-colored text that stays readable in dark mode.
    static let firText = Color("FirText")
    /// Sap gold: breaks and lunch.
    static let sap = Color("Sap")
    static let sapSoft = Color("SapSoft")
    static let sapInk = Color("SapInk")
    /// Rust: destructive actions and errors (as text and icons).
    static let rust = Color("Rust")
    /// Rust as a fill under white text (destructive buttons): deeper than `rust` in dark
    /// mode, where the text color is too light to carry white.
    static let rustFill = Color("RustFill")
    /// The printed time card stays paper-white in both modes.
    static let paper = Color("Paper")
    static let paperInk = Color("PaperInk")
    /// A tree nobody has shaped yet, on the map.
    static let treeEmpty = Color("TreeEmpty")
    /// Alternating row stripes.
    static let stripe = Color("Stripe")
    /// Block outlines on the map.
    static let blockLine = Color("BlockLine")

    /// Every token by asset name, for tests and previews.
    static let all: [(name: String, color: Color)] = [
        ("Bg", bg), ("Surface", surface), ("Ink", ink), ("Muted", muted), ("Line", line),
        ("Fir", fir), ("FirCard", firCard), ("FirInk", firInk), ("FirSoft", firSoft), ("FirText", firText),
        ("Sap", sap), ("SapSoft", sapSoft), ("SapInk", sapInk), ("Rust", rust), ("RustFill", rustFill),
        ("Paper", paper), ("PaperInk", paperInk), ("TreeEmpty", treeEmpty), ("Stripe", stripe), ("BlockLine", blockLine),
    ]
}
