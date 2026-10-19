import AppIntents
import SwiftUI
import TimeCardCore

// The Live Activity's views: the lock screen and the Dynamic Island. Compiled into the
// widget extension, which draws them, and the app, whose tests render them.
//
// Built for gloves and a quick glance: every button is 54 pt tall, the timer is the
// biggest thing on screen, and there's no clock-out button, so a pocket tap can't end a
// shift. Everything fits Apple's 160 pt lock-screen height.

/// The lock screen.
struct LiveLockScreenView: View {
    var display: LiveActivityDisplay
    var isStale = false
    @Environment(\.colorScheme) private var scheme

    static let buttonHeight: CGFloat = 54

    var body: some View {
        let colors = LiveColors.lockScreen(scheme, onBreak: display.isOnBreak)
        VStack(alignment: .leading, spacing: 0) {
            LiveHeader(display: display, isStale: isStale, colors: colors)
            LiveTimerRow(display: display, colors: colors, timerSize: 40)
                .padding(.top, 4)
            if !display.isOnBreak {
                LiveProgressBar(progress: display.progress, colors: colors)
                    .accessibilityLabel(display.progressLabel)
                    .padding(.top, 6)
            }
            LiveButtonRow(display: display, colors: colors)
                .padding(.top, display.isOnBreak ? 12 : 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(colors.ink)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }
}

// MARK: - Parts

/// Status pill and where you are (or the break's reason); the last action and Undo on the right.
struct LiveHeader: View {
    var display: LiveActivityDisplay
    var isStale: Bool
    var colors: LiveColors

    static let height: CGFloat = 26

    var body: some View {
        HStack(spacing: 8) {
            LiveStatusPill(title: display.statusTitle, colors: colors)
                .fixedSize()
            ViewThatFits(in: .horizontal) {
                place(full: true)
                place(full: false)
                Color.clear.frame(width: 0, height: 0)
            }
            .foregroundStyle(display.isOnBreak ? colors.muted : colors.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .fixedSize()
        }
        .frame(height: Self.height)
    }

    @ViewBuilder
    private func place(full: Bool) -> some View {
        Group {
            if display.isOnBreak {
                if let reason = display.breakDetail {
                    Text(reason)
                } else if let start = display.breakStart {
                    Text(full ? "since \(start, style: .time)" : "\(start, style: .time)")
                }
            } else {
                Text(full ? display.place : (display.blockTitle ?? display.place))
            }
        }
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private var trailing: some View {
        if isStale {
            Label("Open Time Card", systemImage: "arrow.clockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(colors.muted)
                .accessibilityLabel("Open Time Card to keep this timer")
        } else if let last = display.lastAction {
            // On a break the pill already says "On lunch", so only Undo is shown.
            LiveLastAction(last: last, colors: colors, showsText: !display.isOnBreak)
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
        .frame(height: 24)
        .background(colors.pillFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// "✓ Row 14 marked  [Undo]"
struct LiveLastAction: View {
    var last: LiveActivityDisplay.LastAction
    var colors: LiveColors
    var showsText = true

    var body: some View {
        HStack(spacing: 6) {
            if showsText {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(colors.check)
                    .accessibilityHidden(true)
                Text(last.text)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            if last.canUndo {
                Button(intent: UndoButtonIntent()) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleOnly)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(colors.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 26)
                        .background(colors.undoFill, in: Capsule())
                        // A taller target than it looks, for gloves; it spills into the padding around it.
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -5)
                .accessibilityLabel("Undo: \(last.text)")
            }
        }
        .font(.footnote)
    }
}

/// The big timer, with trees this shift (or, on a break, the frozen worked time) on the right.
struct LiveTimerRow: View {
    var display: LiveActivityDisplay
    var colors: LiveColors
    var timerSize: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 7) {
            LiveTimer(start: display.timerStart, size: timerSize, color: colors.timer, characters: display.timerCharacters)
            // A ten-hour day on a small phone has no room for the caption; the number stays.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    if display.timerCaption != nil { caption }
                    Spacer(minLength: 6)
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
        VStack(alignment: .trailing, spacing: 1) {
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
    var colors: LiveColors

    var body: some View {
        FractionWidth(fraction: progress) {
            Capsule().fill(colors.track)
            Capsule().fill(colors.progress)
        }
        .frame(height: 4)
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

/// [Row 13] [Row 14] [Row 15] [Break], or one big [Back to work] on a break.
struct LiveButtonRow: View {
    var display: LiveActivityDisplay
    var colors: LiveColors

    var body: some View {
        Group {
            if display.isOnBreak {
                Button(intent: BackToWorkButtonIntent()) {
                    Label("Back to work", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(colors.onPrimary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(colors.primary, in: shape)
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 6) {
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
                    }
                    Button(intent: StartBreakButtonIntent()) {
                        VStack(spacing: 3) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Break")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(colors.onSecondary)
                        .frame(maxWidth: display.fieldMessage == nil ? .infinity : 84, maxHeight: .infinity)
                        .background(colors.secondary, in: shape)
                        .contentShape(shape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a break")
                }
            }
        }
        .frame(height: LiveLockScreenView.buttonHeight)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    private func rowLabel(_ row: LiveActivityDisplay.RowButton) -> some View {
        VStack(spacing: 0) {
            Text(row.caption.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .opacity(0.8)
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

/// Expanded, leading: the status and the block.
struct LiveIslandLeading: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        VStack(alignment: .leading, spacing: 4) {
            LiveStatusPill(title: display.statusTitle, colors: colors)
            Group {
                if display.isOnBreak, display.breakDetail == nil, let start = display.breakStart {
                    Text("since \(start, style: .time)")
                } else {
                    Text(display.isOnBreak ? (display.breakDetail ?? "") : (display.blockTitle ?? display.place))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(colors.muted)
            .lineLimit(1)
        }
        .padding(.leading, 4)
        .frame(maxHeight: .infinity, alignment: .center)
        .dynamicTypeSize(...LiveIslandLeading.largestText)
    }

    /// The island has a fixed size, so text stops growing here, as on the lock screen.
    static let largestText = DynamicTypeSize.large
}

/// Expanded, trailing: the timer.
struct LiveIslandTrailing: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        VStack(alignment: .trailing, spacing: 0) {
            LiveTimer(start: display.timerStart, size: 26, color: colors.timer, characters: display.timerCharacters, alignment: .trailing)
            Text(display.isOnBreak ? (display.frozenWorked.map { "\($0) worked" } ?? "") : "\(display.trees) \(display.treesCaption)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(colors.muted)
                .lineLimit(1)
        }
        .padding(.trailing, 4)
        .frame(maxHeight: .infinity, alignment: .center)
        .dynamicTypeSize(...LiveIslandLeading.largestText)
    }
}

/// Expanded, bottom: the same buttons as the lock screen, and the last action.
struct LiveIslandBottom: View {
    var display: LiveActivityDisplay

    var body: some View {
        let colors = LiveColors.island(onBreak: display.isOnBreak)
        VStack(spacing: 6) {
            if let last = display.lastAction {
                LiveLastAction(last: last, colors: colors)
                    .foregroundStyle(colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LiveButtonRow(display: display, colors: colors)
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
                ProgressView(timerInterval: display.timerStart...display.timerStart.addingTimeInterval(Self.day), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.circular)
                .labelsHidden()
                .tint(color)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Working")
        }
    }
}
