import ActivityKit
import SwiftUI
import TimeCardCore
import WidgetKit

/// The lock-screen Live Activity, the Dynamic Island, and the small card Apple Watch shows in
/// its Smart Stack (and CarPlay). The views live in Shared/LiveActivity and
/// LiveActivitySmall.swift so the app's tests can render them; this only places them.
struct TimeCardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimeCardActivityAttributes.self) { context in
            LiveActivityFamilyCard(state: context.state, isStale: context.isStale)
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
        // Without it the watch squeezes the lock-screen card until it's cut off.
        .supplementalActivityFamilies([.small])
    }
}

/// The lock screen (`.medium`) or the watch's Smart Stack card (`.small`).
private struct LiveActivityFamilyCard: View {
    var state: LiveSnapshot
    var isStale: Bool
    @Environment(\.activityFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch family {
        case .small:
            LiveActivitySmallView(state: state)
                .activityBackgroundTint(LiveColors.lockScreen(scheme, onBreak: state.phase != .working).background)
                .activitySystemActionForegroundColor(LiveColors.lockScreen(scheme, onBreak: state.phase != .working).ink)
        default:
            LockScreenCard(display: LiveActivityDisplay(state), isStale: isStale)
        }
    }
}

/// The lock-screen card with its background in the same light or dark look as its words. The
/// lock screen can hand the card's content one look while a dynamic color for the background
/// resolves to the other (a pale card with pale words on a light phone's first draw), so both
/// come from the content's own `colorScheme`.
private struct LockScreenCard: View {
    var display: LiveActivityDisplay
    var isStale: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors = LiveColors.lockScreen(scheme, onBreak: display.isOnBreak)
        LiveLockScreenView(display: display, isStale: isStale)
            .activityBackgroundTint(colors.background)
            .activitySystemActionForegroundColor(colors.ink)
    }
}
