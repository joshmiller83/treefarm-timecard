import BackgroundTasks
import Foundation
import Observation
import TimeCardCore

/// The app-wide model. `TimeCardSession` (in TimeCardCore) holds the tested logic:
/// sign-in, the open farm, its records and sync. This adds what only the app can do:
/// scene changes, the network monitor and background refresh.
///
/// Later slices (field actions, Siri, the Live Activity) read `snapshot` and write
/// through `save(_:)`, so every change lands in the store and syncs the same way.
@MainActor
@Observable
final class AppModel {
    let session: TimeCardSession
    let mode: LaunchMode
    /// Set when the database couldn't open; the app shows this instead of working.
    let storageError: String?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastForegroundRefresh: Date?
    @ObservationIgnored private var networkWatcher: Task<Void, Never>?

    nonisolated static let backgroundRefreshID = (Bundle.main.bundleIdentifier ?? "com.joshmiller83.timecard") + ".sync"

    init(session: TimeCardSession, mode: LaunchMode, storageError: String? = nil) {
        self.session = session
        self.mode = mode
        self.storageError = storageError
    }

    // MARK: Seams for the next slices

    var snapshot: FarmSnapshot { session.snapshot }

    func save(_ records: [SyncRecord]) throws {
        try session.save(records)
    }

    // MARK: Lifecycle

    func start() async {
        guard !started, storageError == nil else { return }
        started = true
        lastForegroundRefresh = Date()
        await session.start()
        if mode == .live { watchNetwork() }
    }

    func sceneBecameActive() async {
        guard started else { return }
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
