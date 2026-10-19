import SwiftUI
import TreeFarmKit

/// What the shift summary says (docs/watch.md 2.6 and 3.9): worked time and trees from the
/// phone's closed shift (or the watch's own count while the clock-out waits), heart rate and
/// energy from the workout. Never pay.
struct WorkoutSummaryContent: Equatable {
    var title = WatchDisplay.shiftDone
    /// The big "8:12".
    var worked: String?
    var workedAccessibility: String?
    /// "worked · 412 trees", or "412 trees · waiting for iPhone".
    var detail: String?
    /// "avg 104 · max 151", beside a heart.
    var heart: String?
    /// "Average heart rate 104, maximum 151": the heart is hidden from VoiceOver.
    var heartAccessibility: String?
    /// "1,120 kcal · 7:41 act.", beside a flame.
    var energy: String?
    /// "1,120 calories, 7 hours 41 minutes active".
    var energyAccessibility: String?

    init(closed: ClosedShift?, summary: WorkoutSummary?, waitingForPhone: Bool) {
        if let closed {
            worked = Fmt.hm(closed.worked)
            workedAccessibility = WatchDisplay.timerAccessibility(closed.worked)
            detail = waitingForPhone ? WatchDisplay.summaryWaitingLine(trees: closed.trees)
                                     : WatchDisplay.summaryWorkedLine(trees: closed.trees)
        }
        if let summary {
            heart = WatchDisplay.summaryHeartLine(avg: summary.avgHeartRate, max: summary.maxHeartRate)
            heartAccessibility = WorkoutWords.summaryHeartAccessibility(avg: summary.avgHeartRate, max: summary.maxHeartRate)
            energy = WatchDisplay.summaryEnergyLine(kcal: summary.activeKcal, active: summary.activeDuration)
            energyAccessibility = WorkoutWords.summaryEnergyAccessibility(kcal: summary.activeKcal, active: summary.activeDuration)
        }
    }
}

/// The screen after a shift ends. It never scrolls (Double Tap is Done), so on a small watch or
/// at large text it drops the energy line, then the heart line, rather than scroll.
struct WorkoutSummaryView: View {
    let content: WorkoutSummaryContent
    let onDone: () -> Void

    @Environment(\.workoutSizeOverride) private var sizeOverride
    @Environment(\.isLuminanceReduced) private var dimmed

    private var size: WorkoutSize { sizeOverride ?? .current }

    init(closed: ClosedShift?, summary: WorkoutSummary?, waitingForPhone: Bool, onDone: @escaping () -> Void) {
        self.content = WorkoutSummaryContent(closed: closed, summary: summary, waitingForPhone: waitingForPhone)
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .vertical) {
                facts(heart: true, energy: true)
                facts(heart: true, energy: false)
                facts(heart: false, energy: false)
            }
            .frame(maxHeight: .infinity)

            Button(action: onDone) {
                Text(WatchDisplay.done)
            }
            .buttonStyle(GloveButtonStyle(fill: WorkoutPalette.fir, height: size.primaryHeight))
            .handGestureShortcut(.primaryAction)
            .accessibilityIdentifier("summary.done")
        }
    }

    private func facts(heart: Bool, energy: Bool) -> some View {
        VStack(spacing: 2) {
            Label(content.title, systemImage: WatchDisplay.Glyph.shiftDone)
                .font(.headline)
                .foregroundStyle(WorkoutPalette.firText)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let worked = content.worked {
                Text(worked)
                    .font(.system(size: size.bigNumber, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityLabel(content.workedAccessibility ?? worked)
            }
            if let detail = content.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            if heart, let line = content.heart {
                metric(line, spoken: content.heartAccessibility, glyph: WatchDisplay.Glyph.heart, tint: WorkoutPalette.heart)
            }
            if energy, let line = content.energy {
                metric(line, spoken: content.energyAccessibility, glyph: WatchDisplay.Glyph.energy, tint: WorkoutPalette.energy)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ line: String, spoken: String?, glyph: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .foregroundStyle(dimmed ? tint.opacity(0.6) : tint)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(line)
                .foregroundStyle(.white.opacity(dimmed ? 0.6 : 0.9))
                .monospacedDigit()
                .accessibilityLabel(spoken ?? line)
        }
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
