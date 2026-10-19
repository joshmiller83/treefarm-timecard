import ActivityKit
import SwiftUI
import TimeCardCore
import WidgetKit

/// The lock-screen Live Activity and the Dynamic Island. The views live in
/// Shared/LiveActivity so the app's tests can render them; this only places them.
struct TimeCardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimeCardActivityAttributes.self) { context in
            LiveLockScreenView(display: LiveActivityDisplay(context.state), isStale: context.isStale)
                .activityBackgroundTint(LiveColors.dynamicBackground)
                .activitySystemActionForegroundColor(LiveColors.dynamicInk)
        } dynamicIsland: { context in
            let display = LiveActivityDisplay(context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveIslandLeading(display: display)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveIslandTrailing(display: display)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveIslandBottom(display: display)
                }
            } compactLeading: {
                LiveIslandCompactLeading(display: display)
            } compactTrailing: {
                LiveIslandCompactTrailing(display: display)
            } minimal: {
                LiveIslandMinimal(display: display)
            }
            .keylineTint(LiveColors.island(onBreak: display.isOnBreak).timer)
        }
    }
}
