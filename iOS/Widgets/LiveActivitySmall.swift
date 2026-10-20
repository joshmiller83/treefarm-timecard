import AppIntents
import SwiftUI
import TimeCardCore

// The Live Activity's `.small` family: the card Apple Watch shows in its Smart Stack, and
// CarPlay's layout (with its button turned off). 152 × 69.5 pt on a 40 mm watch, the smallest
// to design for, up to 198 × 81.5 pt on an Ultra 3 (docs/watch.md 4.4).
//
// One control only, as the HIG asks: the next row's button while working, Back to work on a
// break. It carries `.handGestureShortcut(.primaryAction)`, so Double Tap presses it from the
// Smart Stack. Undo and Break stay off the card. The button runs the same `LiveActivityIntent`
// as the lock screen, on the iPhone: a phone-in-reach convenience, with no outbox. The watch
// app is the reliable path.
//
// Only system fonts here: a custom font is reported to break `Text(timerInterval:)` on the
// watch. Built into the widget extension, which draws it, and the app, whose tests render it.

/// What the small card says, from the same `LiveSnapshot` as the lock screen. Every word and
/// glyph comes from `WatchDisplay`, so the card reads like the watch app beside it.
struct LiveActivitySmallDisplay: Equatable {
    /// The card's one control.
    enum Control: Equatable {
        /// Marks the row the card shows (never "the next row", which may have moved).
        case markRow(RowChip)
        case backToWork
        /// Nothing to mark: every row in the field is shaped. The card says so instead.
        case none
    }

    var isOnBreak: Bool
    /// `leaf.fill`, `cup.and.saucer.fill`, `pause.fill`.
    var glyph: String
    /// Line 1, then shorter for a narrow card: "Working · Block 2" → "Block 2".
    var titles: [String]
    /// What VoiceOver hears for line 1, however much of it fits: the whole title.
    var headerAccessibilityLabel: String
    /// Line 2: "Next Row 14 · 38 trees", "Since 12:01", or "Open Time Card" once the activity
    /// goes stale (10 minutes before iOS ends it at 8 hours), as on the lock screen.
    var detail: String
    /// Beside line 2 when stale: `arrow.clockwise`.
    var detailGlyph: String?
    /// Line 2 read aloud when it differs: "Open Time Card to keep this timer".
    var detailAccessibilityLabel: String?
    /// Worked time while working; the break's own time on a break.
    var timerStart: Date
    /// How many characters the timer may reach before the activity ends ("10:00:00" is 8).
    var timerCharacters: Int
    var control: Control
    /// "Row 14 done" → "Row 14" → "14", "Back to work" → "Back".
    var controlLabels: [String]
    var controlGlyph: String
    /// "Mark row 14 in block 2 shaped".
    var controlAccessibilityLabel: String
    /// Shown instead of a button: "Every row in North Field is shaped."
    var message: String?

    /// The lock screen's words for a stale activity (`LiveHeaderLine`).
    static let staleLine = "Open Time Card"
    static let staleGlyph = "arrow.clockwise"
    static let staleAccessibilityLabel = "Open Time Card to keep this timer"

    /// `calendar` reads "Since 12:01": the phone's own zone, as the lock screen's times do.
    init(_ s: LiveSnapshot, isStale: Bool = false, calendar: FarmCalendar = FarmCalendar(timeZone: .current, weekStart: .monday)) {
        let lockScreen = LiveActivityDisplay(s)
        let phase: WatchPhase = switch s.phase {
        case .working: .working
        case .lunch: .lunch
        case .onBreak: .onBreak
        }
        isOnBreak = lockScreen.isOnBreak
        glyph = WatchDisplay.phaseGlyph(phase)
        let short = isOnBreak ? WatchDisplay.phaseTitle(phase) : (s.nextRows.first?.blockName ?? WatchDisplay.phaseTitle(phase))
        let title = WatchDisplay.smallTitle(s)
        titles = title == short ? [title] : [title, short]
        headerAccessibilityLabel = title
        detail = isStale ? Self.staleLine : WatchDisplay.smallDetail(s, calendar: calendar)
        detailGlyph = isStale ? Self.staleGlyph : nil
        detailAccessibilityLabel = isStale ? Self.staleAccessibilityLabel : nil
        timerStart = lockScreen.timerStart
        timerCharacters = lockScreen.timerCharacters

        let primary: WatchDisplay.Primary
        if isOnBreak {
            control = .backToWork
            primary = .backToWork
        } else if let chip = s.nextRows.first {
            control = .markRow(chip)
            primary = .markRow(chip)
        } else {
            control = .none
            primary = .none
        }
        controlLabels = WatchDisplay.primaryLabelSteps(primary)
        controlGlyph = WatchDisplay.primaryGlyph(primary)
        controlAccessibilityLabel = WatchDisplay.primaryAccessibilityLabel(primary)
        message = control == .none ? lockScreen.fieldMessage : nil
    }

    /// The lock screen's row intent, for the row the card shows.
    var markRowIntent: MarkRowIntent? {
        guard case .markRow(let chip) = control else { return nil }
        return MarkRowIntent(blockId: chip.blockId, row: chip.row)
    }
}

/// The Smart Stack card: the phase and its timer, what's next, and one big button.
///
/// ```
/// ┌───────────────────────────────────┐
/// │ 🍃 Working · Block 2     3:41:07  │
/// │ Next Row 14 · 38 trees            │
/// │ ╭───────────────────────────────╮ │
/// │ │       ✓  Row 14 done          │ │
/// │ ╰───────────────────────────────╯ │
/// └───────────────────────────────────┘
/// ```
struct LiveActivitySmallView: View {
    var state: LiveSnapshot
    /// iOS is about to end the activity: line 2 asks to open the app, as the lock screen does.
    var isStale = false
    @Environment(\.colorScheme) private var scheme

    /// The button: a glove-sized target, full width, taking whatever height the card spares.
    nonisolated static let buttonHeight: CGFloat = 36
    /// Text follows the watch's text size up to here; past it line 2 would push the button off.
    nonisolated static let largestText = DynamicTypeSize.xLarge

    /// A system font by text style: the only kind this card uses.
    struct SystemFont: Equatable, Sendable {
        var style: Font.TextStyle
        var design: Font.Design
        var weight: Font.Weight
        var monospacedDigits: Bool

        init(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight = .semibold, monospacedDigits: Bool = false) {
            self.style = style
            self.design = design
            self.weight = weight
            self.monospacedDigits = monospacedDigits
        }

        var font: Font {
            let font = Font.system(style, design: design).weight(weight)
            return monospacedDigits ? font.monospacedDigit() : font
        }
    }

    struct Fonts: Sendable {
        var timer = SystemFont(.title3, design: .rounded, monospacedDigits: true)
        var title = SystemFont(.footnote)
        var detail = SystemFont(.caption, weight: .medium)
        var button = SystemFont(.headline)
        var message = SystemFont(.caption)

        var all: [SystemFont] { [timer, title, detail, button, message] }
    }

    nonisolated static let fonts = Fonts()

    var body: some View {
        let display = LiveActivitySmallDisplay(state, isStale: isStale)
        let colors = LiveColors.lockScreen(scheme, onBreak: display.isOnBreak)
        // A tall text size, or the smallest watch, gives up line 2 before the button.
        ViewThatFits(in: .vertical) {
            SmallCard(display: display, colors: colors, showsDetail: true)
            SmallCard(display: display, colors: colors, showsDetail: false)
        }
        .foregroundStyle(colors.ink)
    }
}

/// The card's three parts, top to bottom.
struct SmallCard: View {
    var display: LiveActivitySmallDisplay
    var colors: LiveColors
    var showsDetail: Bool

    /// The words stay clear of the card's rounded corners; the button runs edge to edge.
    static let inset: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            SmallHeader(display: display, colors: colors)
            if showsDetail {
                HStack(spacing: 4) {
                    if let glyph = display.detailGlyph {
                        Image(systemName: glyph)
                    }
                    Text(display.detail)
                }
                .font(LiveActivitySmallView.fonts.detail.font)
                .foregroundStyle(colors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, SmallCard.inset)
                .padding(.vertical, -1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(display.detailAccessibilityLabel ?? display.detail)
            }
            SmallControl(display: display, colors: colors)
        }
        .dynamicTypeSize(...LiveActivitySmallView.largestText)
    }
}

/// The phase glyph and words on the left, the running timer on the right. The words shorten,
/// then go, before the timer does; VoiceOver hears the whole title, then the timer.
struct SmallHeader: View {
    var display: LiveActivitySmallDisplay
    var colors: LiveColors

    var body: some View {
        HStack(spacing: 4) {
            // The glyph always shows, so it carries the title for VoiceOver.
            Image(systemName: display.glyph)
                .font(LiveActivitySmallView.fonts.title.font)
                .foregroundStyle(colors.timer)
                .accessibilityLabel(display.headerAccessibilityLabel)
            // Explicit children: ViewThatFits needs unique ones, and the titles may repeat.
            ViewThatFits(in: .horizontal) {
                title(0)
                if display.titles.count > 1 { title(1) }
                Color.clear.frame(width: 0, height: 0)
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            SmallTimer(start: display.timerStart, characters: display.timerCharacters, color: colors.timer)
        }
        .padding(.horizontal, SmallCard.inset)
        .accessibilityElement(children: .combine)
    }

    private func title(_ index: Int) -> some View {
        Text(display.titles[index])
            .font(LiveActivitySmallView.fonts.title.font)
            .lineLimit(1)
    }
}

/// Counts up on its own. A timer in a Live Activity sizes itself for counting forever, so it
/// takes the width of a placeholder with as many digits as it can reach ("0:00:00").
struct SmallTimer: View {
    var start: Date
    var characters: Int
    var color: Color

    var body: some View {
        let font = LiveActivitySmallView.fonts.timer.font
        // The placeholder never shrinks, so the words beside it give way first.
        Text(Self.placeholder(characters))
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .hidden()
            .overlay(alignment: .trailing) {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
            // Digits sit inside the line box; the header only needs the room they show.
            .padding(.vertical, -4)
    }

    /// "0:00:00" for 7 characters, "00:00:00" for 8, "000:00:00" for 9.
    static func placeholder(_ characters: Int) -> String {
        String(repeating: "0", count: max(1, characters - 6)) + ":00:00"
    }
}

/// The one control: the row button while working, Back to work on a break, or why there's
/// nothing to mark. Double Tap presses it.
struct SmallControl: View {
    var display: LiveActivitySmallDisplay
    var colors: LiveColors

    var body: some View {
        Group {
            switch display.control {
            case .markRow:
                if let intent = display.markRowIntent {
                    Button(intent: intent) { label }
                        .buttonStyle(.plain)
                        .handGestureShortcut(.primaryAction)
                        .accessibilityLabel(display.controlAccessibilityLabel)
                        .accessibilityInputLabels(Array(display.controlLabels.prefix(2)))
                }
            case .backToWork:
                Button(intent: BackToWorkButtonIntent()) { label }
                    .buttonStyle(.plain)
                    .handGestureShortcut(.primaryAction)
                    .accessibilityLabel(display.controlAccessibilityLabel)
                    .accessibilityInputLabels(display.controlLabels)
            case .none:
                Text(display.message ?? "")
                    .font(LiveActivitySmallView.fonts.message.font)
                    .foregroundStyle(colors.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: LiveActivitySmallView.buttonHeight, maxHeight: .infinity)
                    .background(colors.undoFill, in: shape)
            }
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private var label: some View {
        HStack(spacing: 6) {
            Image(systemName: display.controlGlyph)
                .font(LiveActivitySmallView.fonts.button.font)
            ViewThatFits(in: .horizontal) {
                // Explicit children: ViewThatFits needs unique ones.
                if let first = display.controlLabels.first { buttonText(first) }
                if display.controlLabels.count > 1 { buttonText(display.controlLabels[1]) }
                if display.controlLabels.count > 2 { buttonText(display.controlLabels[2]) }
            }
        }
        .foregroundStyle(colors.onPrimary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: LiveActivitySmallView.buttonHeight, maxHeight: .infinity)
        .background(colors.primary, in: shape)
        .contentShape(shape)
    }

    private func buttonText(_ text: String) -> some View {
        Text(text)
            .font(LiveActivitySmallView.fonts.button.font)
            .lineLimit(1)
    }
}
