import BackgroundTasks
import Foundation
import Observation
import TimeCardCore

/// The app-wide model. `TimeCardSession` (in TimeCardCore) holds the tested logic:
/// sign-in, the open farm, its records and sync. This adds what only the app can do:
/// scene changes, the network monitor and background refresh.
///
/// Field actions (Siri, Live Activity buttons, controls and the app's own buttons) go
/// through `actions`, which writes through the session, so every change lands in the
/// store and syncs the same way, and the lock screen hears about it.
@MainActor
@Observable
final class AppModel {
    /// The one model per process. Siri and lock-screen buttons can wake the app in the
    /// background with no window, and must find the same store and session as the UI.
    /// Replaced only by `reopenIfSealed()`.
    private(set) static var shared = AppEnvironment.makeModel()

    /// A process woken before the first unlock after a restart (by Siri, a lock-screen button or
    /// a control) finds the database sealed, and its model keeps that error for good. Once the
    /// phone has been unlocked, this opens the database again; a model that opens becomes the
    /// shared one, for the window, Siri and the lock screen alike. Returns the new model (with
    /// its own `storageError` if it still can't open), or the shared one when it was fine.
    @discardableResult
    static func reopenIfSealed(make: () -> AppModel = { AppEnvironment.makeModel() }) -> AppModel {
        guard let fresh = reopening(shared, make: make) else { return shared }
        if fresh.storageError == nil { shared = fresh }
        return fresh
    }

    /// A freshly made model when `current` couldn't open its database, else nil.
    static func reopening(_ current: AppModel, make: () -> AppModel) -> AppModel? {
        current.storageError == nil ? nil : make()
    }

    let session: TimeCardSession
    let mode: LaunchMode
    /// Set when the database couldn't open; the app shows this instead of working.
    let storageError: String?
    @ObservationIgnored let actions: FieldActions
    @ObservationIgnored let liveActivity = LiveActivityController()

    @ObservationIgnored private var started = false
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored private var lastForegroundRefresh: Date?
    @ObservationIgnored private var networkWatcher: Task<Void, Never>?

    nonisolated static let backgroundRefreshID = (Bundle.main.bundleIdentifier ?? "com.joshmiller83.timecard") + ".sync"

    init(session: TimeCardSession, mode: LaunchMode, storageError: String? = nil) {
        self.session = session
        self.mode = mode
        self.storageError = storageError
        self.actions = FieldActions(session: session)
        actions.onLiveSnapshot = { [weak self] snapshot in
            self?.liveSnapshotChanged(snapshot)
        }
        // Trees someone else shaped first (and other refusals) reach the lock screen too, and
        // take the Undo that would have pointed at them.
        session.onNotice = { [weak self] notice in
            self?.actions.noteRefusal(notice)
        }
    }

    /// The lock screen's Live Activity follows every change.
    func liveSnapshotChanged(_ snapshot: LiveSnapshot?) {
        liveActivity.update(snapshot, attributes: activityAttributes)
    }

    var activityAttributes: TimeCardActivityAttributes? {
        guard let farm = session.farm, let me = session.me else { return nil }
        return TimeCardActivityAttributes(farmName: farm.name, userName: me.user.displayName)
    }

    // MARK: Seams for the next slices

    var snapshot: FarmSnapshot { session.snapshot }

    func save(_ records: [SyncRecord]) throws {
        try session.save(records)
    }

    // MARK: Lifecycle

    /// Opens the session once. Later callers (an intent that woke the app while the window
    /// was still opening it) wait for that same start instead of running on a store that
    /// isn't loaded yet.
    func start() async {
        guard storageError == nil else { return }
        if let starting {
            await starting.value
            return
        }
        started = true
        lastForegroundRefresh = Date()
        let task = Task { @MainActor in
            await self.session.start()
            if self.mode == .live { self.watchNetwork() }
        }
        starting = task
        await task.value
    }

    func sceneBecameActive() async {
        guard started else { return }
        actions.publishLiveSnapshot()
        await session.requestSync(.foreground)
        // Refresh farms and roles now and then, not on every glance at the phone.
        if let last = lastForegroundRefresh, Date().timeIntervalSince(last) < 5 * 60 { return }
        lastForegroundRefresh = Date()
        if case .signedIn = session.auth { try? await session.refreshMe() }
    }

    func sceneEnteredBackground() {
        scheduleBackgroundRefresh()
    }

    /// Runs when iOS wakes the app for `backgroundRefreshID`.
    func backgroundRefresh() async {
        scheduleBackgroundRefresh()
        if !started { await start() }
        _ = await session.syncNow()
    }

    private func scheduleBackgroundRefresh() {
        guard mode == .live, case .signedIn = session.auth else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundRefreshID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func watchNetwork() {
        networkWatcher = Task { [weak self] in
            var tracker = ReachabilityTracker()
            for await reachable in NetworkMonitor.updates() {
                guard let self else { return }
                if tracker.update(isReachable: reachable) {
                    await self.session.requestSync(.networkReturn)
                }
            }
        }
    }
}
