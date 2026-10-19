import SwiftUI
import TimeCardCore
import UIKit

/// Buttons that sit on the colored status card. Like `GloveButtonStyle`, every one is at
/// least 54 pt tall with a clear pressed state, so they're easy to hit with gloves on.
struct CardButtonStyle: ButtonStyle {
    enum Kind {
        /// Translucent white on fir: Lunch, Other break.
        case onFir
        /// White outline on fir: Clock out.
        case outlineOnFir
        /// Solid white on fir: "Tap again to clock out".
        case confirmOnFir
        /// Sap outline on the break card: Clock out.
        case outlineOnSap
        /// Solid sap ink on the break card: "Tap again to clock out".
        case confirmOnSap
        /// A quieter, smaller-text button on fir (Change start time).
        case chipOnFir
        /// The same on the break card.
        case chipOnSap
    }

    var kind: Kind
    var minHeight: CGFloat = GloveButtonStyle.minHeight
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(isChip ? .subheadline.weight(.semibold) : .headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, isChip ? 10 : 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(background, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1.5))
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }
    private var isChip: Bool { kind == .chipOnFir || kind == .chipOnSap }

    private var foreground: Color {
        switch kind {
        case .onFir, .outlineOnFir, .chipOnFir: Palette.firInk
        case .confirmOnFir: ClockColors.alarm
        case .outlineOnSap, .chipOnSap: Palette.sapInk
        case .confirmOnSap: Palette.sapSoft
        }
    }

    private var background: Color {
        switch kind {
        case .onFir, .chipOnFir: Color.white.opacity(0.14)
        case .outlineOnFir, .outlineOnSap, .chipOnSap: .clear
        case .confirmOnFir: Palette.firInk
        case .confirmOnSap: Palette.sapInk
        }
    }

    private var border: Color {
        switch kind {
        case .onFir, .chipOnFir: Color.white.opacity(0.3)
        case .outlineOnFir: Color.white.opacity(0.55)
        case .confirmOnFir: Palette.firInk
        case .outlineOnSap, .chipOnSap: Palette.sap
        case .confirmOnSap: Palette.sapInk
        }
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    static func card(_ kind: CardButtonStyle.Kind) -> CardButtonStyle { CardButtonStyle(kind: kind) }
}

/// A few colors only the Clock tab uses, from the web time card.
enum ClockColors {
    /// The pulsing "on the clock" light.
    static let pulse = Color(red: 0xA8 / 255, green: 0xEB / 255, blue: 0xC0 / 255)
    /// Deep rust that reads on white: "Tap again to clock out".
    static let alarm = Color(red: 0x8E / 255, green: 0x2F / 255, blue: 0x18 / 255)

    /// The toast sits on `Palette.ink`: near-black in light mode, pale green in dark mode.
    /// Its icons flip with it. Done: mint on dark (about 12:1), fir on pale (about 7:1).
    static let toastDone = adaptive(light: 0xA8EBC0, dark: 0x1D5B3A)
    /// Problem: sap gold on dark (about 7:1), rust on pale (about 5.5:1).
    static let toastProblem = adaptive(light: 0xE2A644, dark: 0xA2391F)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// The status card's pill: small caps, letter-spaced, with a light that pulses while working.
struct ClockPill: View {
    var text: String
    var tone: Tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    enum Tone { case off, working, onBreak }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dot)
                .frame(width: 9, height: 9)
                .background {
                    if tone == .working && !reduceMotion {
                        Circle()
                            .stroke(ClockColors.pulse.opacity(pulsing ? 0 : 0.7), lineWidth: pulsing ? 8 : 0)
                            .scaleEffect(pulsing ? 2.2 : 1)
                            .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: pulsing)
                    }
                }
                .accessibilityHidden(true)
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(Capsule().strokeBorder(border, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("status-pill")
        .onAppear { pulsing = true }
    }

    private var dot: Color {
        switch tone {
        case .off: Palette.muted
        case .working: ClockColors.pulse
        case .onBreak: Palette.sap
        }
    }

    private var ink: Color {
        switch tone {
        case .off: Palette.muted
        case .working: Palette.firInk
        case .onBreak: Palette.sapInk
        }
    }

    private var border: Color {
        switch tone {
        case .off: Palette.line
        case .working: Color.white.opacity(0.35)
        case .onBreak: Palette.sap
        }
    }
}

/// A card heading in Zilla Slab with something small on the right; at the largest text
/// sizes the small thing goes underneath, so neither squeezes into a ragged column.
struct CardHeading<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                heading
                trailing
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                heading
                Spacer(minLength: 8)
                trailing
            }
        }
    }

    private var heading: some View {
        Text(title)
            .headingStyle(.tcTitle2)
            .accessibilityAddTraits(.isHeader)
    }
}

extension CardHeading where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// A thin progress bar in fir on a soft track.
struct FieldProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.firSoft)
                Capsule()
                    .fill(Palette.fir)
                    .frame(width: max(fraction > 0 ? 8 : 0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
