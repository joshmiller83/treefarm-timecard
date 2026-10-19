import ActivityKit
import Foundation
import TimeCardCore
import UIKit
import UserNotifications

/// The few ActivityKit calls the controller needs, so its rules are tested without ActivityKit.
@MainActor
protocol LiveActivityHosting: AnyObject {
    /// False when Live Activities are turned off for Time Card in Settings.
    var areActivitiesEnabled: Bool { get }
    /// True with the app on screen. Only then is an old activity swapped for a fresh one,
    /// and only then may the notification permission prompt appear.
    var isAppActive: Bool { get }
    func activities() -> [LiveActivityRecord]
    /// Requests a new activity and returns its id.
    func start(_ attributes: TimeCardActivityAttributes, _ state: LiveSnapshot, staleDate: Date?) throws -> String
    func update(id: String, _ state: LiveSnapshot, staleDate: Date?) async
    /// Ends the activity and takes it off the lock screen right away.
    func end(id: String, _ state: LiveSnapshot?) async
    /// Keeps the app running (a background task) until the returned function is called, so
    /// iOS doesn't suspend it between a lock-screen tap's intent returning and the update.
    func holdAwake() -> @MainActor () -> Void
}

/// The "your lock-screen timer is about to end" notification.
@MainActor
protocol LiveActivityReminding: AnyObject {
    /// Replaces any earlier reminder. `askPermission` is true when the app is on screen,
    /// the only time a permission prompt makes sense.
    func schedule(at date: Date, askPermission: Bool) async
    func cancel() async
}

/// When each activity started, kept across launches: iOS doesn't say, and the eight-hour
/// limit counts from the start.
protocol LiveActivityLedger {
    var starts: [String: Date] { get set }
}

// MARK: - The real ones

@MainActor
final class ActivityKitHost: LiveActivityHosting {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isAppActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    func activities() -> [LiveActivityRecord] {
        Activity<TimeCardActivityAttributes>.activities.map { activity in
            let state: LiveActivityRecord.State = switch activity.activityState {
            case .active: .active
            case .stale: .stale
            case .ended: .ended
            case .dismissed: .dismissed
            // Pending (iOS 26: scheduled for later) and anything newer: not a card on screen.
            default: .dismissed
            }
            return LiveActivityRecord(id: activity.id, attributes: activity.attributes, state: state)
        }
    }

    func holdAwake() -> @MainActor () -> Void {
        let task = BackgroundTask()
        task.begin()
        return { task.end() }
    }

    func start(_ attributes: TimeCardActivityAttributes, _ state: LiveSnapshot, staleDate: Date?) throws -> String {
        let activity = try Activity.request(attributes: attributes,
                                            content: ActivityContent(state: state, staleDate: staleDate),
                                            pushType: nil)
        return activity.id
    }

    func update(id: String, _ state: LiveSnapshot, staleDate: Date?) async {
        await Self.update(id: id, ActivityContent(state: state, staleDate: staleDate))
    }

    func end(id: String, _ state: LiveSnapshot?) async {
        await Self.end(id: id, state.map { ActivityContent(state: $0, staleDate: nil) })
    }

    // Activities aren't Sendable, so they're looked up and used off the main actor.
    private nonisolated static func update(id: String, _ content: ActivityContent<LiveSnapshot>) async {
        guard let activity = Activity<TimeCardActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }

    private nonisolated static func end(id: String, _ content: ActivityContent<LiveSnapshot>?) async {
        guard let activity = Activity<TimeCardActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(content, dismissalPolicy: .immediate)
    }
}

/// One `beginBackgroundTask`, ended once, by the caller or when iOS runs out of patience.
/// A UIKit background task: keeps the app running for a little while after iOS would
/// suspend it (an intent returned, the app left the screen). `onExpire` runs if iOS ends it first.
@MainActor
final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid
    private let name: String
    private let onExpire: @MainActor () -> Void

    init(name: String = "Live Activity update", onExpire: @escaping @MainActor () -> Void = {}) {
        self.name = name
        self.onExpire = onExpire
    }

    func begin() {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated {
                self?.onExpire()
                // iOS is about to suspend the app: let go of the shared database first.
                AppDatabase.suspend()
                self?.end()
            }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

@MainActor
final class NotificationReminders: LiveActivityReminding {
    static let identifier = "timecard.live-activity.ending"
    static let message = "Open Time Card to keep your lock-screen timer"

    /// False in UI-test launches, so no permission alert lands on top of the app.
    let asksPermission: Bool

    init(asksPermission: Bool) {
        self.asksPermission = asksPermission
    }

    func schedule(at date: Date, askPermission: Bool) async {
        let center = UNUserNotificationCenter.current()
        // Asked the first time a shift starts from the app: the moment the lock-screen timer
        // appears is when a note about keeping it makes sense.
        if asksPermission, askPermission, await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.body = Self.message
        content.sound = .default
        content.threadIdentifier = "live-activity"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    func cancel() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [Self.identifier])
    }
}

struct DefaultsLedger: LiveActivityLedger {
    static let key = "timecard.liveActivity.startedAt"
    var defaults: UserDefaults = .standard

    var starts: [String: Date] {
        get { (defaults.dictionary(forKey: Self.key) as? [String: Date]) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
