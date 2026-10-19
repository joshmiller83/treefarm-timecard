import SwiftUI

// MARK: Buttons

/// Big buttons for gloved hands: at least 54 pt tall, full width, a clear pressed state.
struct GloveButtonStyle: ButtonStyle {
    enum Kind {
        /// Fir green: the one thing to do next.
        case primary
        /// Surface with a line border: the other choices.
        case secondary
        /// Rust: sign out, delete, clock out.
        case destructive
    }

    static let minHeight: CGFloat = 54

    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Self.minHeight)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: Palette.firInk
        case .secondary: Palette.ink
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.fir
        case .secondary: Palette.surface
        case .destructive: Palette.rust
        }
    }
}

extension ButtonStyle where Self == GloveButtonStyle {
    static var glovePrimary: GloveButtonStyle { GloveButtonStyle(kind: .primary) }
    static var gloveSecondary: GloveButtonStyle { GloveButtonStyle(kind: .secondary) }
    static var gloveDestructive: GloveButtonStyle { GloveButtonStyle(kind: .destructive) }
}

// MARK: Cards

/// A surface card: 1 pt line border, 14 pt corners.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// The calm green-grey page behind everything.
    func screenBackground() -> some View {
        background(Palette.bg.ignoresSafeArea())
    }
}

/// A small all-caps label above a group of content.
struct SectionLabel: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Status pill

/// The rounded status tag: "Working", "On lunch", "Off the clock", "Offline".
struct StatusPill: View {
    enum Tone {
        case working, onBreak, off, alert

        var fill: Color {
            switch self {
            case .working: Palette.firSoft
            case .onBreak: Palette.sapSoft
            case .off: Palette.stripe
            case .alert: Palette.rust.opacity(0.14)
            }
        }

        var ink: Color {
            switch self {
            case .working: Palette.firText
            case .onBreak: Palette.sapInk
            case .off: Palette.muted
            case .alert: Palette.rust
            }
        }

        var dot: Color {
            switch self {
            case .working: Palette.fir
            case .onBreak: Palette.sap
            case .off: Palette.muted
            case .alert: Palette.rust
            }
        }
    }

    var text: String
    var tone: Tone

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.dot).frame(width: 8, height: 8)
            Text(text).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(tone.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tone.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(tone.dot.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Text fields

/// A tall, bordered text field that's easy to hit with a thumb.
struct GloveFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: GloveButtonStyle.minHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

extension TextFieldStyle where Self == GloveFieldStyle {
    static var glove: GloveFieldStyle { GloveFieldStyle() }
}

/// A message in rust with an icon, for errors under a form.
struct ErrorMessage: View {
    var text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(Palette.rust)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("form-error")
    }
}

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pine Hollow").headingStyle(.tcTitle)
            HStack {
                StatusPill(text: "Working", tone: .working)
                StatusPill(text: "On lunch", tone: .onBreak)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("This shift")
                Text("6:42:10").numberStyle(.timer).foregroundStyle(Palette.ink)
                Text("212 trees").numberStyle(.stat).foregroundStyle(Palette.firText)
            }
            .card()
            Button("Clock in") {}.buttonStyle(.glovePrimary)
            Button("Take a break") {}.buttonStyle(.gloveSecondary)
            Button("Clock out") {}.buttonStyle(.gloveDestructive)
            TextField("Email", text: .constant("")).textFieldStyle(.glove)
            ErrorMessage(text: "That email and password don't match.")
        }
        .padding()
    }
    .screenBackground()
}
