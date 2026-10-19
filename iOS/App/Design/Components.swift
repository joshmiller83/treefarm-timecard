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

    nonisolated static let minHeight: CGFloat = 54

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
            .opacity(configuration.isPressed ? 0.82 : 1)
            .pressScale(configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    /// A disabled button is drawn as one, in both modes: a hairline-grey fill and muted words
    /// (fir at half opacity still looked like a button you could press in dark mode).
    private var foreground: Color {
        guard isEnabled else { return Palette.muted }
        switch kind {
        case .primary, .destructive: return Palette.firInk
        case .secondary: return Palette.ink
        }
    }

    private var background: Color {
        guard isEnabled else { return Palette.line }
        switch kind {
        case .primary: return Palette.fir
        case .secondary: return Palette.surface
        case .destructive: return Palette.rustFill
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

/// The small shrink of a pressed button, left out with Reduce Motion.
struct PressScale: ViewModifier {
    var pressed: Bool
    var amount: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scaleEffect(pressed && !reduceMotion ? amount : 1)
    }
}

extension View {
    func pressScale(_ pressed: Bool, _ amount: CGFloat = 0.98) -> some View {
        modifier(PressScale(pressed: pressed, amount: amount))
    }
}

extension AnyTransition {
    /// Slides in from an edge, or only fades with Reduce Motion.
    static func slide(from edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// The house empty or waiting state: an icon in a soft fir square, a Zilla Slab title and a
/// line of help, on a surface card. Used wherever there's nothing to show yet.
struct EmptyStateCard: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.firText)
                .frame(width: 56, height: 56)
                .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(title).headingStyle(.tcTitle2)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 20)
        .accessibilityElement(children: .combine)
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
            // All caps grow loud fast: they stop at AX2, with the Large Content Viewer past it.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityShowsLargeContentViewer()
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
        PillContent(text: text, tone: tone)
            // A pill is a label, not a paragraph: it stops growing at AX2.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children: .combine)
            .accessibilityShowsLargeContentViewer { Text(text) }
    }

    /// Inside the size cap, so the dot grows with the words up to where they stop.
    private struct PillContent: View {
        var text: String
        var tone: Tone
        @ScaledMetric(relativeTo: .subheadline) private var dot: CGFloat = 8

        var body: some View {
            HStack(spacing: 6) {
                Circle().fill(tone.dot).frame(width: dot, height: dot)
                Text(text).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tone.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tone.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(tone.dot.opacity(0.25), lineWidth: 1))
        }
    }
}

// MARK: Segmented choices

/// Two or three big choices side by side (Crew | Fields | Season, Lunch | Break, This week |
/// Last week | …): glove-sized segments, the chosen one fir green. When the words wouldn't fit
/// on one line each (the largest text sizes) the segments go one under another, so a word
/// never breaks ("Lun/ch"). Used by every tab, so a choice looks the same everywhere.
struct GloveSegmented<Value: Hashable>: View {
    var options: [(value: Value, title: String, identifier: String)]
    @Binding var selection: Value

    /// Each option names its own accessibility identifier.
    init(options: [(value: Value, title: String, identifier: String)], selection: Binding<Value>) {
        self.options = options
        self._selection = selection
    }

    /// Identifiers are "<identifier>-<title>", e.g. "report-range-This week".
    init(options: [(value: Value, title: String)], selection: Binding<Value>, identifier: String) {
        self.options = options.map { ($0.value, $0.title, "\(identifier)-\($0.title)") }
        self._selection = selection
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) { segments(oneLine: true) }
            VStack(spacing: 4) { segments(oneLine: false) }
        }
        .padding(4)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        // Like the system's segmented controls, the words stop growing a step into the
        // accessibility sizes (a long press shows them large), so short choices such as
        // Crew | Fields | Season stay side by side instead of filling the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func segments(oneLine: Bool) -> some View {
        ForEach(options.indices, id: \.self) { i in
            let option = options[i]
            let selected = option.value == selection
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { selection = option.value }
            } label: {
                Text(option.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(oneLine ? 1 : nil)
                    .minimumScaleFactor(oneLine ? 0.75 : 1)
                    .foregroundStyle(selected ? Palette.firInk : Palette.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, oneLine ? 0 : 8)
                    .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.fir)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityShowsLargeContentViewer()
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(option.identifier)
        }
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
/// Says something to VoiceOver once: a message that just appeared on screen. The same words
/// within a second (a view and its action both asking) are said once.
@MainActor
enum Announcer {
    private static var last: (text: String, at: Date)?

    static func say(_ text: String?, after delay: Duration = .milliseconds(250)) {
        guard let text, !text.isEmpty else { return }
        let now = Date()
        if let last, last.text == text, now.timeIntervalSince(last.at) < 1 { return }
        last = (text, now)
        Task { @MainActor in
            // After VoiceOver has read the button that was tapped.
            try? await Task.sleep(for: delay)
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// A problem under a form, said to VoiceOver as it appears.
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
        .task(id: text) { Announcer.say(text) }
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
            ErrorMessage(text: "That email and password don’t match.")
        }
        .padding()
    }
    .screenBackground()
}
