import ActivityKit
import SwiftUI
import WidgetKit

/// Placeholder Live Activity: the status and a running timer. The real lock-screen
/// layout (row buttons, break, undo) comes with the Live Activity slice.
struct TimeCardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimeCardActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "leaf.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.phase.title)
                        .font(.headline)
                    Text(context.attributes.farmName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: context.state.timerStart...Date.distantFuture, countsDown: false)
                    .font(.title2.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
            .padding()
            .activityBackgroundTint(Color(red: 0x1D / 255, green: 0x5B / 255, blue: 0x3A / 255).opacity(0.9))
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.phase.title, systemImage: "leaf.fill")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.timerStart...Date.distantFuture, countsDown: false)
                        .monospacedDigit()
                        .frame(maxWidth: 80)
                }
            } compactLeading: {
                Image(systemName: "leaf.fill")
            } compactTrailing: {
                Text(timerInterval: context.state.timerStart...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "leaf.fill")
            }
        }
    }
}

extension TimeCardActivityAttributes.ContentState.Phase {
    var title: String {
        switch self {
        case .working: "Working"
        case .lunch: "Lunch"
        case .onBreak: "On break"
        }
    }
}

extension TimeCardActivityAttributes.ContentState {
    /// While working, the timer counts total worked time; on a break it counts the break.
    var timerStart: Date {
        phase == .working ? segmentStart.addingTimeInterval(-workedBefore) : segmentStart
    }
}
