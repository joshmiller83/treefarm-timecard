import SwiftUI
import TreeFarmKit

/// The shift summary after a clock-out (docs/watch.md 2.6, 3.9): worked time and trees from the
/// phone (or the watch's own count while the clock-out waits), and heart rate, calories and
/// active time from the workout when it recorded one. Never pay. Done is the primary action.
/// While the clock-out still waits for the phone, a banner says so in place of the title.
struct ShiftDoneScreen: View {
    let closed: ClosedShift
    let waiting: Bool
    let workout: WorkoutSummary?
    let done: () -> Void

    private let metrics = ButtonMetrics.current
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.isSmall ? 2 : 4) {
            if waiting {
                Banner(text: WatchDisplay.clockOutWaiting)
                    .accessibilityIdentifier("clockOutWaiting")
            } else {
                Label(WatchDisplay.shiftDone, systemImage: WatchDisplay.Glyph.shiftDone)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(WatchPalette.firBright)
            }

            Text(Fmt.hm(closed.worked))
                .font(.system(size: (metrics.timer + 6) * scale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityLabel(WatchDisplay.timerAccessibility(closed.worked))

            Text(waiting ? WatchDisplay.summaryWaitingLine(trees: closed.trees) : WatchDisplay.summaryWorkedLine(trees: closed.trees))
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(waiting ? WatchPalette.sap : .secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            if let workout {
                if let heart = WatchDisplay.summaryHeartLine(avg: workout.avgHeartRate, max: workout.maxHeartRate) {
                    Label(heart, systemImage: WatchDisplay.Glyph.heart)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WatchPalette.rustBright)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Label(WatchDisplay.summaryEnergyLine(kcal: workout.activeKcal, active: workout.activeDuration),
                      systemImage: WatchDisplay.Glyph.energy)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(WatchPalette.sap)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

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
}
