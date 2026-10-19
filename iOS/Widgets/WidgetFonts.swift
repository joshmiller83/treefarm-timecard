import CoreText
import Foundation
import UIKit

/// Makes IBM Plex Mono available to the extension's views. The font files ship once, in the
/// app (App/Resources/Fonts); the extension sits inside the app's bundle, so it registers
/// them from there instead of carrying a second copy.
enum WidgetFonts {
    static let files = ["IBMPlexMono/IBMPlexMono-SemiBold.ttf", "IBMPlexMono/IBMPlexMono-Medium.ttf"]

    static func register() {
        guard UIFont(name: LiveFonts.numberName, size: 12) == nil else { return }
        // …/TimeCard.app/PlugIns/TimeCardWidgets.appex → …/TimeCard.app
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        for base in [Bundle.main.bundleURL, app] {
            for file in files {
                let url = base.appendingPathComponent("Fonts").appendingPathComponent(file)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            if UIFont(name: LiveFonts.numberName, size: 12) != nil { return }
        }
    }
}
