import SwiftUI

/// The time card's colors for the lock screen and the Dynamic Island. The widget extension
/// can't read the app's asset catalog, so the values are spelled out here, matching
/// App/Resources/Assets.xcassets/Colors: fir green for work, sap gold for breaks, on paper
/// in a light lock screen and on deep fir in a dark one.
struct LiveColors: Equatable {
    var background: Color
    var ink: Color
    var muted: Color
    /// The big timer.
    var timer: Color
    var pillFill: Color
    var pillInk: Color
    var dot: Color
    var track: Color
    var progress: Color
    /// Row buttons and Back to work.
    var primary: Color
    var onPrimary: Color
    /// The small ROW / BLOCK 3 words on the row buttons: a little softer than the number in
    /// the light look, full white on the dark one's lighter green so they stay readable.
    var onPrimaryCaption: Color
    /// The Break button.
    var secondary: Color
    var onSecondary: Color
    /// The Undo buttons and the checkmark beside "Row 14 marked".
    var undoFill: Color
    var check: Color

    static func lockScreen(_ scheme: ColorScheme, onBreak: Bool) -> LiveColors {
        scheme == .dark ? dark(onBreak: onBreak) : light(onBreak: onBreak)
    }

    /// The Dynamic Island is always black.
    static func island(onBreak: Bool) -> LiveColors {
        var c = dark(onBreak: onBreak)
        c.background = .black
        return c
    }

    static func light(onBreak: Bool) -> LiveColors {
        LiveColors(
            background: Color(liveHex: 0xF4F7F1),
            ink: Color(liveHex: 0x14221A),
            muted: Color(liveHex: 0x4F6356),
            timer: onBreak ? Color(liveHex: 0x7A4F06) : Color(liveHex: 0x1D5B3A),
            pillFill: onBreak ? Color(liveHex: 0xF5E6C6) : Color(liveHex: 0xD9EADD),
            pillInk: onBreak ? Color(liveHex: 0x573803) : Color(liveHex: 0x1D5B3A),
            dot: onBreak ? Color(liveHex: 0xB57A12) : Color(liveHex: 0x1D5B3A),
            track: Color(liveHex: 0xD3DED4),
            progress: Color(liveHex: 0x1D5B3A),
            primary: Color(liveHex: 0x1D5B3A),
            onPrimary: .white,
            onPrimaryCaption: Color(liveHex: 0xD2DED8),
            secondary: Color(liveHex: 0xF5E6C6),
            onSecondary: Color(liveHex: 0x573803),
            undoFill: Color(liveHex: 0xE2ECE3),
            check: Color(liveHex: 0x1D5B3A))
    }

    static func dark(onBreak: Bool) -> LiveColors {
        LiveColors(
            background: Color(liveHex: 0x111D16),
            ink: Color(liveHex: 0xE3ECE4),
            muted: Color(liveHex: 0x9DB0A3),
            timer: onBreak ? Color(liveHex: 0xE2A644) : Color(liveHex: 0x88CFA4),
            pillFill: onBreak ? Color(liveHex: 0x3A2C10) : Color(liveHex: 0x1E3528),
            pillInk: onBreak ? Color(liveHex: 0xF3D9A4) : Color(liveHex: 0x9FDAB5),
            dot: onBreak ? Color(liveHex: 0xE2A644) : Color(liveHex: 0x5DBB85),
            track: Color(liveHex: 0x2B3A31),
            progress: Color(liveHex: 0x5DBB85),
            primary: Color(liveHex: 0x2E7A4E),
            onPrimary: .white,
            onPrimaryCaption: .white,
            secondary: Color(liveHex: 0x3A2C10),
            onSecondary: Color(liveHex: 0xF3D9A4),
            undoFill: Color(liveHex: 0x24382C),
            check: Color(liveHex: 0x88CFA4))
    }
}

/// IBM Plex Mono for numbers, as in the app. The app registers it through `UIAppFonts`; the
/// extension registers the app's copy at launch (`WidgetFonts`). If that ever fails, the
/// system font stands in, still with even digits.
enum LiveFonts {
    static let numberName = "IBMPlexMono-SemiBold"

    static func number(_ size: CGFloat) -> Font {
        .custom(numberName, fixedSize: size)
    }
}

extension Color {
    init(liveHex hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
