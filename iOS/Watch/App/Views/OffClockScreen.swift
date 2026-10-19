import SwiftUI
import TreeFarmKit
import WatchKit

/// Off the clock (docs/watch.md 3.4): one page, no scrolling. Clock in is the primary action,
/// so Double Tap fires it; a pinch by accident is undone with Undo clock-in on Now.
struct OffClockScreen: View {
    let model: WatchShiftModel
    let state: WatchState
    let primaryEnabled: Bool
    let act: (FieldCommand, WatchSource) -> Void
    let showQueue: () -> Void

    private let metrics = ButtonMetrics.current

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.isSmall ? 4 : 6) {
            HStack {
                Text(WatchDisplay.farmLine(state))
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if model.waitingCount > 0 {
                    QueueBadge(count: model.waitingCount, action: showQueue)
                }
            }

            Spacer(minLength: 0)

            if model.clockOutWaiting {
                Banner(text: WatchDisplay.clockOutWaiting)
                    .accessibilityIdentifier("clockOutWaiting")
            }

            Button {
                act(.clockIn(fieldId: nil), .button)
            } label: {
                GloveLabel(steps: [WatchDisplay.clockIn], glyph: WatchDisplay.Glyph.clockIn,
                           font: .system(.title2, design: .rounded).weight(.bold))
            }
            .buttonStyle(GloveButtonStyle(tone: .fir, height: metrics.primary + (metrics.isSmall ? 0 : 4), cornerRadius: 26))
            .handGestureShortcut(.primaryAction, isEnabled: primaryEnabled)
            .accessibilityLabel(WatchDisplay.clockIn)
            .accessibilityIdentifier("primaryAction")

            VStack(alignment: .leading, spacing: 1) {
                if let starts = WatchDisplay.placeLine(state) {
                    Text(starts)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                if let last = lastLine {
                    ViewThatFits(in: .horizontal) {
                        ForEach(last, id: \.self) { step in
                            Text(step).lineLimit(1).fixedSize()
                        }
                        Text(last.last ?? "").lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

        }
        .padding(.horizontal, 2)
        .background(PhaseGlow(phase: .offClock))
        .watchToast(model.toast, alignment: .top)
        .navigationTitle(WatchDisplay.appName)
    }

    /// "Last shift 8:12 · 412 trees" (shorter as text grows), or "6.5 h today" after a split shift.
    private var lastLine: [String]? {
        if let closed = state.lastClosedShift, state.calendar.isSameDay(closed.end, Date()),
           state.todayWorked > closed.worked + 60 {
            return [WatchDisplay.hoursTodayLine(state.todayWorked)]
        }
        return state.lastClosedShift.map(WatchDisplay.lastShiftSteps)
    }
}
