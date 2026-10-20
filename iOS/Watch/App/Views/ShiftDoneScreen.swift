import SwiftUI
import TreeFarmKit

/// The shift summary after a clock-out (docs/watch.md 2.6, 3.9): worked time and trees from the
/// phone (or the watch's own count while the clock-out waits), and heart rate, calories and
/// active time from the workout when it recorded one. Never pay. Done is the primary action.
/// While the clock-out still waits for the phone, a banner says so in place of the title.
/// `WorkoutSummaryContent` supplies the words and what VoiceOver says for the numbers.
struct ShiftDoneScreen: View {
    let closed: ClosedShift
    let waiting: Bool
    let workout: WorkoutSummary?
    var metrics = ButtonMetrics.current
    let done: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    /// The words, and what VoiceOver says for the heart and flame lines.
    private var content: WorkoutSummaryContent {
        WorkoutSummaryContent(closed: closed, summary: workout, waitingForPhone: waiting)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.isSmall ? 2 : 4) {
            // It never scrolls (Double Tap is Done): on a small watch or at large text the
            // energy line goes first, then the heart line.
            ViewThatFits(in: .vertical) {
                facts(heart: true, energy: true)
                facts(heart: true, energy: false)
                facts(heart: false, energy: false)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Button(action: done) {
                GloveLabel(steps: [WatchDisplay.done], glyph: "")
            }
            .buttonStyle(GloveButtonStyle(tone: .fir, height: metrics.primary))
            .handGestureShortcut(.primaryAction)
            .accessibilityIdentifier("summaryDone")
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PhaseGlow(phase: .offClock))
    }

    private func facts(heart: Bool, energy: Bool) -> some View {
        VStack(alignment: .leading, spacing: metrics.isSmall ? 2 : 4) {
            if waiting {
                Banner(text: WatchDisplay.clockOutWaiting)
                    .accessibilityIdentifier("clockOutWaiting")
            } else {
                Label(WatchDisplay.shiftDone, systemImage: WatchDisplay.Glyph.shiftDone)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(WatchPalette.firBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(Fmt.hm(closed.worked))
                .font(.system(size: metrics.timer * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(WatchDisplay.timerAccessibility(closed.worked))

            if let detail = content.detail {
                Text(detail)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(waiting ? WatchPalette.sap : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            if heart, let line = content.heart {
                Label(line, systemImage: WatchDisplay.Glyph.heart)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WatchPalette.rustBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(content.heartAccessibility ?? line)
            }
            if energy, let line = content.energy {
                Label(line, systemImage: WatchDisplay.Glyph.energy)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WatchPalette.sap)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(content.energyAccessibility ?? line)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
