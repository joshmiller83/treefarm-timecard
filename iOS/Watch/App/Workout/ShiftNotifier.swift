import Foundation
import TreeFarmKit
import UserNotifications

/// The one local notification the watch posts: a clock-out that waited an hour for the phone
/// (docs/watch.md 2.2 and 2.4).
@MainActor
protocol ShiftNotifier: AnyObject {
    /// Asked on the first-launch card, worded "Remind me if a clock-out gets stuck."
    func requestAuthorization() async -> Bool
    /// "Open Time Card near your iPhone to finish clocking out."
    func notifyStuckClockOut() async
}

@MainActor
final class UserNotificationShiftNotifier: ShiftNotifier {
    static let stuckClockOutId = "timecard.stuck-clock-out"

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notifyStuckClockOut() async {
        let content = UNMutableNotificationContent()
        content.title = WatchDisplay.appName
        content.body = WatchDisplay.stuckClockOut
        content.sound = .default
        // The same id replaces an earlier one instead of stacking.
        let request = UNNotificationRequest(identifier: Self.stuckClockOutId, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
