import SwiftUI

/// The time card's colors on a watch face, which is black: the app's dark-mode fir and sap
/// (App/Resources/Assets.xcassets), spelled out because the extension can't read the iPhone's
/// asset catalog. Full-color faces show them; tinted faces keep only what's `.widgetAccentable()`.
enum ComplicationStyle {
    /// Words, timers and glyphs while working ("FirText" in the dark).
    static let fir = Color(complicationHex: 0x88CFA4)
    /// The working ring: a deeper fir, so the row number in the middle stands out.
    static let firRing = Color(complicationHex: 0x5DBB85)
    /// Lunch and breaks ("Sap" in the dark).
    static let sap = Color(complicationHex: 0xE2A644)
    /// A frozen ring's track.
    static let track = Color.white.opacity(0.18)

    static func tint(_ tone: ComplicationFace.Tone) -> Color {
        switch tone {
        case .working, .offClock: fir
        case .onBreak: sap
        case .none: .secondary
        }
    }

    /// The Smart Stack card behind the rectangular widget (faces drop it): deep fir while
    /// working, deep sap on a break, the app's night background otherwise.
    static func background(_ tone: ComplicationFace.Tone) -> LinearGradient {
        let (top, bottom): (UInt32, UInt32) = switch tone {
        case .working: (0x24633F, 0x10291B)
        case .onBreak: (0x4A3712, 0x1E1708)
        case .offClock: (0x1C3125, 0x0F1612)
        case .none: (0x1F2622, 0x0F1612)
        }
        return LinearGradient(colors: [Color(complicationHex: top), Color(complicationHex: bottom)], startPoint: .top, endPoint: .bottom)
    }

    /// Timers: the system's rounded face with even digits. A custom font can break
    /// `Text(timerInterval:)` in the Smart Stack.
    static func timer(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(complicationHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Digits sit well inside a font's line box; trim the empty top and bottom so a big number
    /// takes only the room it shows (the lock screen's timers do the same).
    func trimmedLineBox(_ size: CGFloat) -> some View {
        padding(.top, -0.2 * size).padding(.bottom, -0.16 * size)
    }
}
