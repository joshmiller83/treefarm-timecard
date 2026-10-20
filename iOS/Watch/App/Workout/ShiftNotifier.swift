import Foundation
import TreeFarmKit
import UserNotifications

/// The one local notification the watch posts: a clock-out that waited an hour for the phone
/// (docs/watch.md 2.2 and 2.4). It is scheduled with the system at the stop, so it comes even
/// when the session ends from outside or the app is gone, and taken back once the phone answers.
@MainActor
protocol ShiftNotifier: AnyObject {
    /// Asked on the first-launch card, worded "Remind me if a clock-out gets stuck."
    func requestAuthorization() async -> Bool
    /// "Open Time Card near your iPhone to finish clocking out."
    func notifyStuckClockOut() async
    /// The same reminder, left with the system at the stop for `date`.
    func scheduleStuckClockOut(at date: Date) async
    /// No clock-out waits any more: takes the reminder back, scheduled or shown.
    func cancelStuckClockOut()
}

@MainActor
final class UserNotificationShiftNotifier: ShiftNotifier {
    static let stuckClockOutId = "timecard.stuck-clock-out"

    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// The in-app path (rule 2 at 60 minutes). The reminder scheduled at the stop has usually
    /// been shown by then, so it isn't said twice; otherwise this one replaces it (same id).
    func notifyStuckClockOut() async {
        let shown = await center.deliveredNotifications().contains { $0.request.identifier == Self.stuckClockOutId }
        guard !shown else { return }
        try? await center.add(Self.request(trigger: nil))
    }

    func scheduleStuckClockOut(at date: Date) async {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try? await center.add(Self.request(trigger: trigger))
    }

    func cancelStuckClockOut() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.stuckClockOutId])
        center.removeDeliveredNotifications(withIdentifiers: [Self.stuckClockOutId])
    }

    /// "Open Time Card near your iPhone to finish clocking out." One id, so a newer one
    /// replaces an older one instead of stacking.
    private static func request(trigger: UNNotificationTrigger?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = WatchDisplay.appName
        content.body = WatchDisplay.stuckClockOut
        content.sound = .default
        return UNNotificationRequest(identifier: stuckClockOutId, content: content, trigger: trigger)
    }
}
