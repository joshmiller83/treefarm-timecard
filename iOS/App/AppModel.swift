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
    /// The Apple Watch link. Made and activated here, not in a view: a watch message can launch
    /// the app in the background with no scene, and the window's `.task` would never run.
    @ObservationIgnored private(set) var watch: PhoneWatchBridge!

    @ObservationIgnored private var started = false
    /// The one start every caller awaits (the window, Siri, the watch bridge), so a second
    /// caller never runs on a session that is still loading.
    @ObservationIgnored private var startTask: Task<Void, Never>?
    /// The person the watch last heard about, to tell a sign-in or sign-out from a sync.
    @ObservationIgnored private var watchFollowedUser: UUID??
    @ObservationIgnored private var lastForegroundRefresh: Date?
    @ObservationIgnored private var networkWatcher: Task<Void, Never>?

    nonisolated static let backgroundRefreshID = (Bundle.main.bundleIdentifier ?? "com.joshmiller83.timecard") + ".sync"

    /// `watchTransport` and `watchLauncher` default to the real WatchConnectivity and HealthKit
    /// ones for a live launch, and to ones with no watch behind them for UI tests and test hosts.
    init(session: TimeCardSession, mode: LaunchMode, storageError: String? = nil,
         watchTransport: (any WatchTransport)? = nil, watchLauncher: (any WatchWorkoutLauncher)? = nil) {
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
        let realWatch = mode == .live && !LaunchMode.isTestHost
        let desk = WatchDesk(actions: actions, store: session.store, settings: { [session] in
            WatchSettings.load(from: session.store, userId: session.me?.user.id)
        })
        watch = PhoneWatchBridge(model: self,
                                 transport: watchTransport ?? (realWatch ? WCSessionTransport() : DisconnectedWatchTransport()),
                                 launcher: watchLauncher ?? (realWatch ? HealthKitWatchLauncher() : UnavailableWatchLauncher()),
                                 desk: desk)
        watch.activate()
        followSessionForWatch()
    }

    /// The lock screen's Live Activity and the watch follow every change.
    func liveSnapshotChanged(_ snapshot: LiveSnapshot?) {
        // Once the session has opened, no snapshot really means off the clock.
        liveActivity.update(snapshot, attributes: activityAttributes, sessionLoaded: session.hasOpened)
        watch.publish(reason: .fieldAction)
    }

    /// Syncs, sign-ins and sign-outs reach the watch: reads the session's records and who is
    /// signed in, and hears about the next change to either.
    private func followSessionForWatch() {
        let user = withObservationTracking {
            _ = session.snapshot
            return session.auth.me?.user.id
        } onChange: { [weak self] in
            Task { @MainActor in self?.sessionChangedForWatch() }
        }
        watchFollowedUser = .some(user)
    }

    private func sessionChangedForWatch() {
        let before = watchFollowedUser ?? nil
        followSessionForWatch()
        let after = watchFollowedUser ?? nil
        watch.publish(reason: before == after ? .sync : (after == nil ? .signOut : .signIn))
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
        if let startTask {
            await startTask.value
            return
        }
        started = true
        lastForegroundRefresh = Date()
        let task = Task { @MainActor in
            await self.session.start()
            if self.mode == .live { self.watchNetwork() }
            self.watch.publish(reason: .started)
        }
        startTask = task
        await task.value
    }

    func sceneBecameActive() async {
        guard started else { return }
        actions.publishLiveSnapshot()
        watch.publish(reason: .sceneActive)
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

    func scheduleBackgroundRefresh() {
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
