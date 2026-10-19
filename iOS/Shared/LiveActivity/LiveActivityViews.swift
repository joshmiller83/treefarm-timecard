import AppIntents
import SwiftUI
import TimeCardCore

// The Live Activity's views: the lock screen and the Dynamic Island. Compiled into the
// widget extension, which draws them, and the app, whose tests render them.
//
// Built for gloves and a quick glance: the row, break, back-to-work and Undo buttons are
// 54 pt tall (on the lock screen Undo is a fifth tile beside the rows, under the header's
// "Row 14 marked"), the timer is the biggest thing on screen, and there's no clock-out button, so a pocket tap
// can't end a shift. Everything fits Apple's 160 pt lock-screen height, with text up to
// `LiveLockScreenView.largestText`.

/// The lock screen.
struct LiveLockScreenView: View {
    var display: LiveActivityDisplay
    var isStale = false
    @Environment(\.colorScheme) private var scheme

    static let buttonHeight: CGFloat = 54
    /// Text follows the person's text size up to here. Past it the card would pass 160 pt.
    static let largestText = DynamicTypeSize.xxLarge

    var body: some View {
        let colors = LiveColors.lockScreen(scheme, onBreak: display.isOnBreak)
        VStack(alignment: .leading, spacing: 0) {
            // Undo is a glove-sized tile in the button row, not a small capsule in the header
            // right above the row buttons; the header keeps the "Row 14 marked" confirmation.
            LiveHeader(display: display, isStale: isStale, colors: colors, undoInRow: true)
            LiveTimerRow(display: display, colors: colors, timerSize: 40)
                .padding(.top, 3)
            if !display.isOnBreak {
                LiveProgressBar(progress: display.progress, label: display.progressLabel, colors: colors)
                    .padding(.top, 6)
            }
            LiveButtonRow(display: display, colors: colors, undoInRow: true)
                .padding(.top, display.isOnBreak ? 10 : 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .foregroundStyle(colors.ink)
        .dynamicTypeSize(...Self.largestText)
    }
}

// MARK: - Parts

/// Status pill and where you are (or the break's reason); the last action on the right, which
/// is also the Undo button. When it's tight the trailing part shortens first, so the block
/// stays in view.
struct LiveHeader: View {
    var display: LiveActivityDisplay
    var isStale: Bool
    var colors: LiveColors
    /// Undo is in the button row, so the confirmation here is text only.
    var undoInRow = false

    /// Tall enough for a gloved tap on Undo across the whole confirmation.
    static let height: CGFloat = 30

    var body: some View {
        HStack(spacing: 8) {
            LiveStatusPill(title: display.statusTitle, colors: colors)
                .fixedSize()
            if let notice = display.lastAction.flatMap({ $0.kind == .notice ? $0.text : nil }), !isStale {
                // A refused tap says why, ahead of where you are.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        line(.short, .short)
                        LiveNotice(text: notice, colors: colors).fixedSize()
                    }
                    LiveNotice(text: notice, colors: colors)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    line(.full, .full)
                    line(.short, .full)
                    line(.short, .short)
                    line(.truncated, .minimal)
                }
            }
        }
        .frame(height: Self.height)
    }

    private func line(_ place: LiveHeaderLine.Place, _ trailing: LiveHeaderLine.Trailing) -> LiveHeaderLine {
        LiveHeaderLine(display: display, isStale: isStale, colors: colors, place: place, trailing: trailing, offersUndo: !undoInRow)
    }
}

/// One way to fill the header beside the pill: where you are, then the last action.
struct LiveHeaderLine: View {
    enum Place { case full, short, truncated }
    /// "✓ Row 14 marked [Undo]", "✓ [Undo]", "[Undo]"
    enum Trailing { case full, short, minimal }

    var display: LiveActivityDisplay
    var isStale: Bool
    var colors: LiveColors
    var place: Place
    var trailing: Trailing
    var offersUndo = true

    var body: some View {
        HStack(spacing: 8) {
            placeText
            Spacer(minLength: 0)
            trailingView.fixedSize()
        }
    }

    @ViewBuilder
    private var placeText: some View {
        let text = Group {
            if display.isOnBreak {
                if let reason = display.breakDetail {
                    Text(reason)
                } else if let start = display.breakStart {
                    Text(place == .full ? "since \(start, style: .time)" : "\(start, style: .time)")
                }
            } else {
                Text(place == .full ? display.place : (display.blockTitle ?? display.place))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(display.isOnBreak ? colors.muted : colors.ink)
        .lineLimit(1)
        if place == .truncated {
            text.minimumScaleFactor(0.8)
        } else {
            text.fixedSize()
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        if isStale {
            Label("Open Time Card", systemImage: "arrow.clockwise")
                .labelStyle(LiveIconLabelStyle(showsTitle: trailing == .full))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.muted)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Open Time Card to keep this timer")
        } else if let last = display.lastAction, last.kind != .notice, !display.isOnBreak {
            // On a break the pill already says "On lunch", and Undo sits by Back to work.
            LiveLastAction(last: last, colors: colors, showsText: trailing == .full,
                           showsIcon: trailing != .minimal || !last.canUndo || !offersUndo, offersUndo: offersUndo)
        }
    }
}

/// An icon, with its title when there's room.
struct LiveIconLabelStyle: LabelStyle {
    var showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            if showsTitle { configuration.title }
        }
    }
}

struct LiveStatusPill: View {
    var title: String
    var colors: LiveColors

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(colors.dot).frame(width: 7, height: 7)
            Text(title).font(.footnote.weight(.bold))
        }
        .foregroundStyle(colors.pillInk)
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .frame(minHeight: 24)
        .background(colors.pillFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// "✓ Row 14 marked  [Undo]". With Undo on offer the whole thing is one Undo button, so a
/// gloved tap anywhere on it takes the mark back. "Undid row 14" has no Undo, so a second tap
/// can't look like a redo.
struct LiveLastAction: View {
    var last: LiveActivityDisplay.LastAction
    var colors: LiveColors
    /// False shows only the icon (and Undo), when the header is tight.
    var showsText = true
    /// False leaves only Undo, when it's tighter still.
    var showsIcon = true
    /// False when Undo is a button elsewhere (the lock screen's button row).
    var offersUndo = true

    var body: some View {
        if last.canUndo && offersUndo {
            Button(intent: UndoButtonIntent()) {
                HStack(spacing: 6) {
                    confirmation
                    Text("Undo")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(colors.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 26)
                        .background(colors.undoFill, in: Capsule())
                }
                .frame(minHeight: LiveHeader.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Undo: \(last.text)")
            .accessibilityAddTraits(.isButton)
        } else {
            confirmation
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(last.text)
        }
    }

    private var confirmation: some View {
        HStack(spacing: 5) {
            if showsIcon {
                Image(systemName: last.kind == .undone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(colors.check)
            }
            if showsText {
                Text(last.text)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(colors.ink)
                    .lineLimit(1)
            }
        }
        .font(.footnote)
    }
}

/// Why a lock-screen tap didn't go through: "Row 14 was shaped by Sam on Oct 16."
struct LiveNotice: View {
    var text: String
    var colors: LiveColors
    /// Two short lines fit the lock screen's header; the island has room for one.
    var lines = 2

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(colors.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors.ink)
                .lineLimit(lines)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The big timer, with trees this shift (or, on a break, the frozen worked time) on the right.
struct LiveTimerRow: View {
    var display: LiveActivityDisplay
    var colors: LiveColors
    var timerSize: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 5) {
            LiveTimer(start: display.timerStart, size: timerSize, color: colors.timer, characters: display.timerCharacters)
            // When the timer needs room for ten hours on a small phone, or the text is large,
            // the caption goes; the number stays.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    if display.timerCaption != nil { caption }
                    Spacer(minLength: 4)
                    rightStat
                }
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    Spacer(minLength: 4)
                    rightStat
                }
            }
        }
    }

    @ViewBuilder
    private var rightStat: some View {
        if let worked = display.frozenWorked {
            stat(worked, display.frozenWorkedCaption ?? "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(display.frozenWorkedAccessibilityLabel ?? worked)
        } else {
            stat(display.trees, display.treesCaption)
                .accessibilityElement(children: .combine)
        }
    }

    /// "worked / today", stacked small beside the timer.
    private var caption: some View {
        let words = (display.timerCaption ?? "").split(separator: " ", maxSplits: 1).map(String.init)
        return VStack(alignment: .leading, spacing: -1) {
            ForEach(words, id: \.self) { Text($0) }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(colors.muted)
        .lineLimit(1)
        .fixedSize()
        .padding(.bottom, 1)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value)
                .font(LiveFonts.number(21))
                .monospacedDigit()
                .foregroundStyle(colors.ink)
                .trimmedLineBox(21)
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(colors.muted)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Counts up from `start` on its own: no updates needed while the phone sleeps.
///
/// Never `fixedSize()` a timer: in a Live Activity it sizes itself for counting up forever
/// and pushes everything else off the card. It gets the width of its digits instead.
struct LiveTimer: View {
    var start: Date
    var size: CGFloat
    var color: Color
    var characters = 7
    var alignment: Alignment = .leading

    /// Plex Mono's digits and colons are 0.6 em wide.
    static func width(characters: Int, size: CGFloat) -> CGFloat {
        (CGFloat(characters) * 0.6 * size + 2).rounded(.up)
    }

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(LiveFonts.number(size))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .multilineTextAlignment(alignment == .trailing ? .trailing : .leading)
            .frame(width: Self.width(characters: characters, size: size), alignment: alignment)
            .trimmedLineBox(size)
    }
}

extension View {
    /// Digits sit well inside a font's line box; trim the empty top and bottom so a big
    /// number takes only the room it shows. Baselines still line up.
    func trimmedLineBox(_ size: CGFloat) -> some View {
        padding(.top, -0.24 * size).padding(.bottom, -0.2 * size)
    }
}

/// The field's progress: a thin bar. (No GeometryReader: the widget host measures with
/// open-ended sizes, and a GeometryReader there brings the extension down.)
struct LiveProgressBar: View {
    var progress: Double
    /// "3,240 of 8,540 trees shaped in North Field"
    var label: String
    var colors: LiveColors

    var body: some View {
        FractionWidth(fraction: progress) {
            Capsule().fill(colors.track)
            Capsule().fill(colors.progress)
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }
}

/// Lays out its first child at full width and the second at `fraction` of it, from the left.
struct FractionWidth: Layout {
    var fraction: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: Self.finite(proposal.width, or: 100), height: Self.finite(proposal.height, or: 4))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // The widget host lays out with open-ended sizes while it measures; anything
        // non-finite placed here stops the extension, so it's clamped.
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        let full = Self.finite(bounds.width, or: 0)
        let height = Self.finite(bounds.height, or: 4)
        let origin = CGPoint(x: bounds.minX.isFinite ? bounds.minX : 0, y: bounds.minY.isFinite ? bounds.minY : 0)
        for (i, subview) in subviews.enumerated() {
            var width = i == 0 ? full : full * f
            if i > 0, f > 0 { width = max(width, height) }
            subview.place(at: origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: height))
        }
    }

    private static func finite(_ value: CGFloat?, or fallback: CGFloat) -> CGFloat {
        guard let value, value.isFinite else { return fallback }
        return max(0, value)
    }
}

/// [Row 13] [Row 14] [Row 15] [Break], or [Back to work] [Undo] on a break. In the island,
/// where there's no header for it, Undo joins the working row too.
struct LiveButtonRow: View {
    var display: LiveActivityDisplay
    var colors: LiveColors
    var undoInRow = false
    /// The small words on the buttons grow with the text size; the numbers are big already.
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 10
    @ScaledMetric(relativeTo: .footnote) private var labelSize: CGFloat = 13

    var body: some View {
        HStack(spacing: 6) {
            if display.isOnBreak {
                Button(intent: BackToWorkButtonIntent()) {
                    Label("Back to work", systemImage: "play.fill")
                        .accessibilityInputLabels(["Back to work"])
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(colors.onPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colors.primary, in: shape)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                if let last = display.lastAction, last.canUndo {
                    // Room for a real button here, so a mistaken Break is one gloved tap from gone.
                    Button(intent: UndoButtonIntent()) {
                        iconButton("Undo", systemImage: "arrow.uturn.backward", ink: colors.ink, fill: colors.undoFill)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo: \(last.text)")
                    .accessibilityInputLabels(["Undo"])
                }
            } else {
                if let message = display.fieldMessage {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(colors.muted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(display.rows) { row in
                    Button(intent: MarkRowIntent(blockId: row.chip.blockId, row: row.chip.row)) {
                        rowLabel(row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(row.accessibilityLabel)
                    .accessibilityInputLabels(row.inputLabels)
                }
                Button(intent: StartBreakButtonIntent()) {
                    iconButton("Break", systemImage: "cup.and.saucer.fill", ink: colors.onSecondary, fill: colors.secondary,
                               width: display.fieldMessage == nil ? nil : 84)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start a break")
                .accessibilityInputLabels(["Break", "Start a break", "Take a break"])
                if undoInRow, let last = display.lastAction, last.canUndo {
                    Button(intent: UndoButtonIntent()) {
                        iconButton("Undo", systemImage: "arrow.uturn.backward", ink: colors.ink, fill: colors.undoFill,
                                   width: display.fieldMessage == nil ? nil : 84)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo: \(last.text)")
                    .accessibilityInputLabels(["Undo"])
                }
            }
        }
        .frame(height: LiveLockScreenView.buttonHeight)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    /// A cup over "Break", an arrow over "Undo".
    private func iconButton(_ title: String, systemImage: String, ink: Color, fill: Color, width: CGFloat? = 84) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: labelSize + 4, weight: .semibold))
            Text(title)
                .font(.system(size: labelSize, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 4)
        .frame(maxWidth: width ?? .infinity, maxHeight: .infinity)
        .frame(width: width)
        .background(fill, in: shape)
        .contentShape(shape)
    }

    private func rowLabel(_ row: LiveActivityDisplay.RowButton) -> some View {
        VStack(spacing: 0) {
            Text(row.caption.uppercased())
                .font(.system(size: captionSize, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(colors.onPrimaryCaption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(row.number)
                .font(LiveFonts.number(24))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(colors.onPrimary)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.primary, in: shape)
        .contentShape(shape)
    }
}

// MARK: - Dynamic Island

/// Expanded, leading: the status, and the last action ("✓ Row 6 marked") or the block.
struct LiveIslandLeading: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        VStack(alignment: .leading, spacing: 4) {
            LiveStatusPill(title: display.statusTitle, colors: colors)
            Group {
                if let last = display.lastAction, last.kind != .notice, !display.isOnBreak {
                    Label {
                        Text(last.text).foregroundStyle(colors.ink)
                    } icon: {
                        Image(systemName: last.kind == .undone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(colors.check)
                    }
                    .labelStyle(LiveIconLabelStyle(showsTitle: true))
                } else if display.isOnBreak, display.breakDetail == nil, let start = display.breakStart {
                    Text("since \(start, style: .time)")
                } else {
                    Text(display.isOnBreak ? (display.breakDetail ?? "") : (display.blockTitle ?? display.place))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(colors.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.leading, 4)
        .frame(maxHeight: .infinity, alignment: .center)
        .dynamicTypeSize(...LiveIslandLeading.largestText)
    }

    /// The island has a fixed size, so text stops growing at the standard size.
    static let largestText = DynamicTypeSize.large
}

/// Expanded, trailing: the timer.
struct LiveIslandTrailing: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        VStack(alignment: .trailing, spacing: 0) {
            LiveTimer(start: display.timerStart, size: Self.timerSize(characters: display.timerCharacters), color: colors.timer,
                      characters: display.timerCharacters, alignment: .trailing)
            Text(display.isOnBreak ? (display.frozenWorked.map { "\($0) worked" } ?? "") : "\(display.trees) \(display.treesCaption)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(colors.muted)
                .lineLimit(1)
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity, alignment: .center)
        .dynamicTypeSize(...LiveIslandLeading.largestText)
    }

    /// Beside the camera there's room for about 112 pt of digits: smaller type for longer times.
    static func timerSize(characters: Int) -> CGFloat {
        min(26, (110 / (CGFloat(characters) * 0.6)).rounded(.down))
    }
}

/// Expanded, bottom: the same buttons as the lock screen, with Undo among them, and why a tap
/// was refused when one was.
struct LiveIslandBottom: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        VStack(spacing: 4) {
            if let last = display.lastAction, last.kind == .notice {
                LiveNotice(text: last.text, colors: colors, lines: 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LiveButtonRow(display: display, colors: colors, undoInRow: true)
        }
        // Clear of the island's rounded bottom corners.
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .dynamicTypeSize(...LiveIslandLeading.largestText)
    }
}

/// Compact, leading: a leaf and the next row (a cup on a break).
struct LiveIslandCompactLeading: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        HStack(spacing: 4) {
            Image(systemName: display.isOnBreak ? "cup.and.saucer.fill" : "leaf.fill")
                .foregroundStyle(colors.timer)
            if !display.isOnBreak, let row = display.compactRow {
                Text("R\(row)")
                    .font(LiveFonts.number(14))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .dynamicTypeSize(...LiveIslandLeading.largestText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.isOnBreak ? display.statusTitle : display.compactRow.map { "Next, row \($0)" } ?? display.statusTitle)
    }
}

/// Compact, trailing: the timer.
struct LiveIslandCompactTrailing: View {
    var display: LiveActivityDisplay

    var body: some View {
        LiveTimer(start: display.timerStart, size: 14, color: LiveColors.island(onBreak: display.isOnBreak).timer,
                  characters: display.timerCharacters, alignment: .trailing)
    }
}

/// Minimal, when another app's activity shares the island. A working day's clock won't fit
/// the bubble in digits, so it's a ring that fills over an eight-hour day around a leaf, ticking
/// on its own. A break shows its own timer ("12:30"), which does fit.
struct LiveIslandMinimal: View {
    var display: LiveActivityDisplay
    /// Renders and previews: draw the ring as it stands at this moment. A ticking ring can't be
    /// drawn into an image.
    var still: Date?

    static let day: TimeInterval = 8 * 3600

    var body: some View {
        let color = LiveColors.island(onBreak: display.isOnBreak).timer
        if display.isOnBreak {
            Text(timerInterval: display.timerStart...Date.distantFuture, countsDown: false)
                .font(LiveFonts.number(10))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(width: 34)
        } else {
            ZStack {
                if let still {
                    LiveStillRing(fraction: still.timeIntervalSince(display.timerStart) / Self.day, color: color)
                } else {
                    ProgressView(timerInterval: display.timerStart...display.timerStart.addingTimeInterval(Self.day), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.circular)
                    .labelsHidden()
                    .tint(color)
                }
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Working")
        }
    }
}

/// The minimal island's ring, drawn still, about as the system draws a circular progress view.
struct LiveStillRing: View {
    var fraction: Double
    var color: Color

    var body: some View {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: 3)
            Circle().trim(from: 0, to: f)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(3)
    }
}
