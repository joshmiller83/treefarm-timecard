import SwiftUI
import UIKit

/// Zilla Slab for headings, IBM Plex Mono for numbers, the system font for everything
/// else. Custom fonts are made with `relativeTo:` so they follow Dynamic Type.
enum Typeface {
    static let headingSemiBold = "ZillaSlab-SemiBold"
    static let headingBold = "ZillaSlab-Bold"
    static let numberMedium = "IBMPlexMono-Medium"
    static let numberSemiBold = "IBMPlexMono-SemiBold"

    static let all = [headingSemiBold, headingBold, numberMedium, numberSemiBold]

    /// True when every bundled font is registered (via `UIAppFonts`).
    static var allRegistered: Bool {
        all.allSatisfy { UIFont(name: $0, size: 12) != nil }
    }
}

extension Font {
    // Headings (Zilla Slab)
    static let tcLargeTitle = Font.custom(Typeface.headingBold, size: 34, relativeTo: .largeTitle)
    static let tcTitle = Font.custom(Typeface.headingBold, size: 28, relativeTo: .title)
    static let tcTitle2 = Font.custom(Typeface.headingSemiBold, size: 22, relativeTo: .title2)
    static let tcHeadline = Font.custom(Typeface.headingSemiBold, size: 19, relativeTo: .headline)

    // Numbers (IBM Plex Mono)
    /// The big running clock on the status card.
    static let tcTimer = Font.custom(Typeface.numberSemiBold, size: 52, relativeTo: .largeTitle)
    /// Stat values: hours, trees, pay.
    static let tcStat = Font.custom(Typeface.numberSemiBold, size: 24, relativeTo: .title2)
    /// Numbers inside body text and lists.
    static let tcNumber = Font.custom(Typeface.numberMedium, size: 17, relativeTo: .body)
    static let tcNumberSmall = Font.custom(Typeface.numberMedium, size: 13, relativeTo: .caption)
}

/// The sizes numbers come in.
enum NumberSize {
    case timer, stat, body, small

    var font: Font {
        switch self {
        case .timer: .tcTimer
        case .stat: .tcStat
        case .body: .tcNumber
        case .small: .tcNumberSmall
        }
    }
}

extension Text {
    /// "48 trees", "3.03 hrs", "1:45/tree": the number in Plex Mono, the words after it in the
    /// system font at the same size, so only digits look like digits.
    static func numberPhrase(_ phrase: String, _ size: NumberSize = .body, weight: Font.Weight = .regular) -> Text {
        let split = phrase.firstIndex(of: " ") ?? phrase.endIndex
        let number = Text(phrase[..<split]).font(size.font).monospacedDigit()
        guard split < phrase.endIndex else { return number }
        return number + Text(phrase[split...]).font(size.wordFont.weight(weight))
    }
}

extension NumberSize {
    /// The system font that sits beside each number size.
    var wordFont: Font {
        switch self {
        case .timer: .title
        case .stat: .title3
        case .body: .body
        case .small: .footnote
        }
    }
}

extension View {
    /// Plex Mono with tabular digits, so ticking numbers don't jiggle.
    func numberStyle(_ size: NumberSize = .body) -> some View {
        font(size.font).monospacedDigit()
    }

    /// Zilla Slab title in ink.
    func headingStyle(_ font: Font = .tcTitle2) -> some View {
        self.font(font).foregroundStyle(Palette.ink)
    }
}
