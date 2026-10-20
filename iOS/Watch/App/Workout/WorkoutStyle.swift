import SwiftUI
import WatchKit

/// The workout screens' sizes by watch (docs/watch.md 3.1): gloves need targets well above the
/// default 44 pt. 40, 41 and 42 mm are small; 44, 45 and 46 mm medium; 49 mm large.
enum WorkoutSize: Equatable, Sendable {
    case small, medium, large

    /// By height: the 42 mm (187×223) and 44 mm (184×224) watches differ by one point.
    init(screen: CGSize) {
        self = screen.height < 224 ? .small : screen.height < 250 ? .medium : .large
    }

    @MainActor static var current: WorkoutSize { WorkoutSize(screen: WKInterfaceDevice.current().screenBounds.size) }

    /// The primary button (Double Tap): Done, Allow Health.
    var primaryHeight: CGFloat { switch self { case .small: 60; case .medium: 64; case .large: 68 } }
    /// Full-width secondary buttons: Record again.
    var secondaryHeight: CGFloat { switch self { case .small: 48; case .medium: 52; case .large: 54 } }
    /// The big worked time on the summary.
    var bigNumber: CGFloat { switch self { case .small: 30; case .medium: 40; case .large: 42 } }
}

extension EnvironmentValues {
    /// Set by tests and previews; otherwise the screens size for the watch they run on.
    @Entry var workoutSizeOverride: WorkoutSize?
}

extension View {
    /// Lays the workout screens out for another watch size (tests, previews).
    func workoutSize(_ size: WorkoutSize) -> some View {
        environment(\.workoutSizeOverride, size)
    }
}

/// The app's colors on the watch's black: fir green for working and Done, sap gold for waiting,
/// rust for what stopped. Each also has its own glyph and word, since tinted faces lose color.
enum WorkoutPalette {
    /// Fir (#1D5B3A): fills, with white ink.
    static let fir = Color(red: 0x1D / 255, green: 0x5B / 255, blue: 0x3A / 255)
    /// Fir text on black (#88CFA4).
    static let firText = Color(red: 0x88 / 255, green: 0xCF / 255, blue: 0xA4 / 255)
    /// Sap gold (#B57A12) with near-black ink.
    static let sap = Color(red: 0xB5 / 255, green: 0x7A / 255, blue: 0x12 / 255)
    static let sapInk = Color(red: 0x1B / 255, green: 0x14 / 255, blue: 0x03 / 255)
    /// Sap text on black (#E2A644).
    static let sapText = Color(red: 0xE2 / 255, green: 0xA6 / 255, blue: 0x44 / 255)
    /// Rust (#B4452B) fills and rust text on black (#EE8D72).
    static let rust = Color(red: 0xB4 / 255, green: 0x45 / 255, blue: 0x2B / 255)
    static let rustText = Color(red: 0xEE / 255, green: 0x8D / 255, blue: 0x72 / 255)
    /// Heart rate and energy, as in Apple's Workout app.
    static let heart = Color(red: 1, green: 0.27, blue: 0.36)
    static let energy = Color(red: 1, green: 0.62, blue: 0.04)
}

/// A full-width button sized for gloves. In Always On it turns into an outline, so the screen
/// stays dark and the label stays readable. [UI-R5]
struct WorkoutButtonStyle: ButtonStyle {
    var fill: Color
    var ink: Color = .white
    var height: CGFloat

    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(dimmed ? fill.mix(with: .white, by: 0.45) : ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: height / 2.6, style: .continuous)
                    .fill(dimmed ? Color.clear : fill)
                    .strokeBorder(fill.mix(with: .white, by: dimmed ? 0.3 : 0), lineWidth: dimmed ? 2 : 0)
            }
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(RoundedRectangle(cornerRadius: height / 2.6, style: .continuous))
    }
}
