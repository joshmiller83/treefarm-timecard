import SwiftUI
import TreeFarmKit

// The watch's look: the time card's fir, sap and rust on black, big rounded numbers, and
// buttons sized for gloves. On tinted faces and in Always On, color drops away, so every phase
// also has its glyph and its word (docs/watch.md 3.1, 3.12).

enum WatchPalette {
    /// Fir green, as a fill under white text (working, Clock in, Row done).
    static let fir = Color(red: 0x2E / 255, green: 0x7A / 255, blue: 0x4E / 255)
    /// Fir as text and glyphs on black.
    static let firBright = Color(red: 0x7F / 255, green: 0xD1 / 255, blue: 0x9E / 255)
    /// The deep fir of the paper time card, for the screen's glow.
    static let firDeep = Color(red: 0x1D / 255, green: 0x5B / 255, blue: 0x3A / 255)
    /// Sap gold: lunch and breaks.
    static let sap = Color(red: 0xE2 / 255, green: 0xA6 / 255, blue: 0x44 / 255)
    static let sapDeep = Color(red: 0xB5 / 255, green: 0x7A / 255, blue: 0x12 / 255)
    /// Rust: clock-out and refusals.
    static let rust = Color(red: 0xB4 / 255, green: 0x45 / 255, blue: 0x2B / 255)
    static let rustBright = Color(red: 0xEE / 255, green: 0x8D / 255, blue: 0x72 / 255)
    /// Quiet surfaces for secondary buttons and the toast.
    static let surface = Color.white.opacity(0.14)
    static let surfaceStrong = Color.white.opacity(0.2)

    static func accent(_ phase: WatchPhase) -> Color {
        switch phase {
        case .working: firBright
        case .lunch, .onBreak: sap
        case .offClock: firBright
        case .signedOut, .noData: .secondary
        }
    }

    static func glow(_ phase: WatchPhase) -> Color {
        switch phase {
        case .working, .offClock: firDeep
        case .lunch, .onBreak: sapDeep
        case .signedOut, .noData: .clear
        }
    }
}

/// The soft phase-colored light at the top of a shift screen, like the Workout app's.
struct PhaseGlow: View {
    let phase: WatchPhase
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        LinearGradient(colors: [WatchPalette.glow(phase).opacity(dimmed ? 0 : 0.55), .clear],
                       startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// A big, glove-sized button: filled, with a pressed state, and outlined in Always On.
struct GloveButtonStyle: ButtonStyle {
    enum Tone { case fir, rust, sap, quiet }

    var tone: Tone = .fir
    var height: CGFloat
    var cornerRadius: CGFloat = 22

    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background {
                if dimmed {
                    shape.strokeBorder(fill.opacity(0.9), lineWidth: 2)
                } else {
                    shape.fill(fill.opacity(enabled ? 1 : 0.45))
                        .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .center)))
                }
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
    }

    private var fill: Color {
        switch tone {
        case .fir: WatchPalette.fir
        case .rust: WatchPalette.rust
        case .sap: WatchPalette.sapDeep
        case .quiet: WatchPalette.surface
        }
    }

    private var foreground: Color {
        guard enabled else { return .white.opacity(0.6) }
        if dimmed {
            switch tone {
            case .fir: return WatchPalette.firBright
            case .rust: return WatchPalette.rustBright
            case .sap: return WatchPalette.sap
            case .quiet: return .white
            }
        }
        return .white
    }
}

/// A button's glyph and word, shortening through `ViewThatFits` at large text sizes.
struct GloveLabel: View {
    let steps: [String]
    let glyph: String
    var font: Font = .system(.title3, design: .rounded).weight(.semibold)

    var body: some View {
        HStack(spacing: 8) {
            if !glyph.isEmpty {
                Image(systemName: glyph)
                    .font(font.weight(.bold))
                    .imageScale(.medium)
            }
            ViewThatFits(in: .horizontal) {
                ForEach(steps, id: \.self) { step in
                    Text(step).font(font).lineLimit(1).fixedSize()
                }
                Text(steps.last ?? "").font(font).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Phase

/// "🍃 WORKING" in the phase's color, with its glyph so it reads on a tinted face.
struct PhaseTag: View {
    let phase: WatchPhase
    /// The whole line when it says more than the phase ("Lunch · since 12:01").
    var title: String?
    /// Only the glyph (VoiceOver still reads the phase): the small watch's tight top row,
    /// where the timer sits right after it.
    var glyphOnly = false

    var body: some View {
        HStack(spacing: 5) {
            if glyphOnly {
                Image(systemName: WatchDisplay.phaseGlyph(phase))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .accessibilityLabel(title ?? WatchDisplay.phaseTitle(phase))
            } else {
                Image(systemName: WatchDisplay.phaseGlyph(phase))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                Text(title ?? WatchDisplay.phaseTitle(phase))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(WatchPalette.accent(phase))
        .accessibilityElement(children: .combine)
    }

}

/// The small dot that says a tap is on its way to the phone.
struct SendingDot: View {
    let visible: Bool

    var body: some View {
        Circle()
            .fill(.white.opacity(visible ? 0.75 : 0))
            .frame(width: 6, height: 6)
            .accessibilityLabel(visible ? "Sending" : "")
            .accessibilityHidden(!visible)
    }
}

// MARK: - Toast

/// The phone's answer, over the bottom of the timer area, never over the primary button.
/// Two lines at most; the whole sentence goes to VoiceOver. It never takes a tap: where it
/// lies over buttons (the Controls page's top row), a glove's tap goes through to them.
struct ToastView: View {
    let toast: WatchToast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: glyph)
                .foregroundStyle(tint)
                .font(.system(.footnote).weight(.bold))
            Text(toast.text)
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.text)
        .accessibilityIdentifier("toast")
        .allowsHitTesting(false)
    }

    private var glyph: String {
        switch toast.kind {
        case .success: "checkmark.circle.fill"
        case .refusal: "exclamationmark.circle.fill"
        case .saved: WatchDisplay.queueGlyph
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .success: WatchPalette.firBright
        case .refusal: WatchPalette.rustBright
        case .saved: WatchPalette.sap
        case .info: .white
        }
    }
}

extension View {
    /// Shows the model's toast at `alignment`, sliding in and out without sub-second loops.
    func watchToast(_ toast: WatchToast?, alignment: Alignment = .bottom) -> some View {
        overlay(alignment: alignment) {
            if let toast {
                ToastView(toast: toast)
                    .transition(.opacity.combined(with: .move(edge: alignment == .top ? .top : .bottom)))
                    .id(toast)
            }
        }
        .animation(.easeOut(duration: 0.25), value: toast)
    }
}

extension WatchToast: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(text)
    }
}

// MARK: - The queue badge

/// `iphone.slash` and the count of taps waiting (not in flight). Visible in Always On, never
/// private: it says nothing about pay. Tapping it opens the Queue sheet.
struct QueueBadge: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: WatchDisplay.queueGlyph)
                    .font(.system(size: 12, weight: .bold))
                Text("\(count)")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(WatchPalette.sap, in: Capsule())
            // A glove-sized target around the small capsule.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The target overhangs the row instead of making it taller, so the screens keep their fit.
        .padding(.vertical, -11)
        .accessibilityLabel(WatchDisplay.waitingLine(count: count))
        .accessibilityIdentifier("queueBadge")
    }
}

/// A full-width notice: "Clock-out waiting for iPhone", "Recording stopped".
struct Banner: View {
    let text: String
    var glyph: String = WatchDisplay.queueGlyph
    var tint: Color = WatchPalette.sap

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph).font(.system(.caption2).weight(.bold))
            Text(text)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
