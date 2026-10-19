import UIKit

/// UIKit-level styling SwiftUI doesn't reach: navigation titles in Zilla Slab and ink.
@MainActor
enum Appearance {
    static func configure() {
        let ink = UIColor(named: "Ink") ?? .label
        var large: [NSAttributedString.Key: Any] = [.foregroundColor: ink]
        var inline: [NSAttributedString.Key: Any] = [.foregroundColor: ink]
        if let font = UIFont(name: Typeface.headingBold, size: 34) {
            large[.font] = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font)
        }
        if let font = UIFont(name: Typeface.headingSemiBold, size: 19) {
            inline[.font] = UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)
        }
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = large
        bar.titleTextAttributes = inline
    }
}
