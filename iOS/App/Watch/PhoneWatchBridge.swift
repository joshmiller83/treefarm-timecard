import Foundation
import Observation
import TimeCardCore
import UIKit

// The iPhone's side of the watch link (docs/watch.md 1.3). `AppModel` makes and activates it
// in `init`, not in a view: a watch message can launch the app in the background with no
// scene, where the window's `.task` never runs.
//
// - One main-actor loop reads the transport's events in WatchConnectivity's order (no
//   callback gets its own `Task`), so nothing here is ever assumed to run on the main actor
//   from WatchConnectivity's queue.
// - Each request is answered exactly once, through `WatchDesk`, after the app's one start has
//   finished (never a false "sign in"). A process woken before the first unlock after a restart
//   has its data sealed; once the phone has been unlocked, the request opens it again.
// - A watch message usually reaches the app in a pocket, where the window has let go of the
//   shared database (`AppDatabase.suspend()`) and GRDB refuses every write. So it resumes the
//   database and holds a background task until the reply and the state it changed have gone
//   out (and, in the background, the change is on its way to the server); then, still in the
//   background, it lets go of the database again (`WatchDatabaseKeeper`).
// - The state is published coalesced over 250 ms, only to a paired watch with the app
//   installed, and only once the session has loaded: as the application context, and as a
//   message too while the watch is reachable. Every state comes from `desk.makeState()`.
// - A phase change the watch can't hear about goes out as a complication push, and a phone
//   clock-in starts the watch's workout, after the context (`WatchComplicationPusher`).

/// Why the phone publishes its state.
enum PublishReason: Equatable, Sendable {
    /// A field action from any door (`AppModel.liveSnapshotChanged`).
    case fieldAction
    /// The session finished starting.
    case started
    /// A sync push or pull changed the records.
    case sync
    case sceneActive
    case signIn
    case signOut
    /// WatchConnectivity activated.
    case activation
    /// Paired, installed or complication state changed.
    case watchStateChanged
    /// The "Record shifts as workouts" toggle changed.
    case settingsChanged
}

/// The Settings status line.
enum WatchLinkStatus: Equatable, Sendable {
    case noWatch, appNotInstalled, inReach, outOfReach

    init(paired: Bool, installed: Bool, reachable: Bool) {
        if !paired {
            self = .noWatch
        } else if !installed {
            self = .appNotInstalled
        } else {
            self = reachable ? .inReach : .outOfReach
        }
    }
}

/// Background time and the shared database for the watch link (docs/watch.md 1.3 step 8).
///
/// iOS kills an app suspended while it holds a lock on a file in a shared container
/// (0xdead10cc), so the app suspends the database whenever it leaves the screen, and GRDB then
/// refuses every write until something resumes it. One keeper serves every bridge in the
/// process, because the suspension is process-wide.
@MainActor
final class WatchDatabaseKeeper {
    static let shared = WatchDatabaseKeeper()

    /// Begins a UIKit background task; the closure it returns ends it.
    var holdAwake: @MainActor (String) -> @MainActor () -> Void = { name in
        let task = BackgroundTask(name: name)
        task.begin()
        return { task.end() }
    }
    var resume: @MainActor () -> Void = { AppDatabase.resume() }
    var suspend: @MainActor () -> Void = { AppDatabase.suspend() }
    var isInBackground: @MainActor () -> Bool = { UIApplication.shared.applicationState == .background }

    /// Work a watch message woke the app for, still running.
    private(set) var working = 0

    /// For work a watch message woke the app for: resumes the database and keeps the app
    /// running until the returned closure is called. The last one out lets go of the database
    /// again if the app is in the background.
    func wake(_ name: String) -> @MainActor () -> Void {
        let release = holdAwake(name)
        resume()
        working += 1
        return { [self] in
            working -= 1
            if working == 0, isInBackground() { suspend() }
            release()
        }
    }

    /// For a publish: keeps the app running while the state goes out. It resumes the database
    /// only during watch work; a publish of another door's change (Siri, a background refresh)
    /// leaves the database as that door set it.
    func hold(_ name: String) -> @MainActor () -> Void {
        let release = holdAwake(name)
        if working > 0 { resume() }
        return release
    }
}

@MainActor
@Observable
final class PhoneWatchBridge {
    /// How long publishes gather before one state goes out.
    @ObservationIgnored var coalesce: Duration = .milliseconds(250)
    /// How long `startWatchApp` may take: its completion can hang when the watch is off.
    static let launchTimeout: Duration = .seconds(10)
    @ObservationIgnored var now: () -> Date = Date.init
    /// Background time and the shared database.
    @ObservationIgnored var keeper = WatchDatabaseKeeper.shared
    /// The phone has been unlocked since it restarted (the data a sealed model couldn't read
    /// can be opened now).
    @ObservationIgnored var protectedDataAvailable: @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable }
    /// Opens the data again for a model that couldn't (as Siri does); the new model, which
    /// carries its own `storageError` if it still can't, becomes the app's when it opens.
    @ObservationIgnored var reopen: @MainActor () -> AppModel = { IntentRunner.reopenStorage() }

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let transport: any WatchTransport
    @ObservationIgnored private let launcher: any WatchWorkoutLauncher
    @ObservationIgnored let desk: WatchDesk
    private(set) var status: WatchLinkStatus = .noWatch

    @ObservationIgnored private var paired = false
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var complicationEnabled = false
    @ObservationIgnored private var reachable = false
    @ObservationIgnored private var activatedOnce = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pendingPublish: Task<Void, Never>?
    @ObservationIgnored private var pendingReasons: [PublishReason] = []
    @ObservationIgnored private var launches: [Task<Void, Never>] = []
    /// What the last `startWatchApp` said (for tests and diagnostics).
    @ObservationIgnored private(set) var lastLaunch: WatchLaunchResult?

    init(model: AppModel, transport: any WatchTransport, launcher: any WatchWorkoutLauncher, desk: WatchDesk) {
        self.model = model
        self.transport = transport
        self.launcher = launcher
        self.desk = desk
    }

    /// Called once from `AppModel.init`: starts reading the transport, then activates it.
    func activate() {
        if loop == nil {
            let events = transport.events
            loop = Task { @MainActor [weak self] in
                for await event in events {
                    guard let self else { return }
                    await self.handle(event)
                }
            }
        }
        transport.activate()
    }

    // MARK: Events

    private func handle(_ event: WatchTransportEvent) async {
        switch event {
        case .activated(let paired, let installed, let complicationEnabled):
            self.paired = paired
            self.installed = installed
            self.complicationEnabled = complicationEnabled
            reachable = transport.isReachable
            updateStatus()
            publish(reason: activatedOnce ? .watchStateChanged : .activation)
            activatedOnce = true
        case .reachabilityChanged(let value):
            reachable = value
            updateStatus()
        case .needsUnlock:
            break
        case .received(let data, let reply):
            guard let reply else {
                await receive(data)
                return
            }
            await answer(data, through: reply)
        case .contextReceived(_, let done), .userInfoReceived(_, let done):
            // The watch never sends these; mark them handled all the same.
            done()
        }
    }

    /// Where a message is run, once the app has started: this model, or, when its data was
    /// sealed at launch (woken before the first unlock after a restart) and the phone has been
    /// unlocked since, a freshly opened one. Nil while the data stays sealed.
    private struct Target {
        let model: AppModel?
        let bridge: PhoneWatchBridge
        var desk: WatchDesk { bridge.desk }
    }

    private func target() async -> Target? {
        guard let model else { return Target(model: nil, bridge: self) }
        if model.storageError == nil {
            await model.start()
            return Target(model: model, bridge: self)
        }
        guard protectedDataAvailable() else { return nil }
        // The fresh model's own link takes over WatchConnectivity from here on.
        let fresh = reopen()
        guard fresh.storageError == nil, let bridge = fresh.watch else { return nil }
        await fresh.start()
        return Target(model: fresh, bridge: bridge)
    }

    /// Exactly one reply per request, after the app has started.
    private func answer(_ data: Data, through reply: WatchReplySink) async {
        let receivedAt = now()
        let done = keeper.wake("Time Card watch reply")
        guard let target = await target() else {
            // Locked since a restart: the data can't be read, so the tap waits on the watch.
            reply.send(WatchDesk.unavailable(data, speech: Speech.unlockOnce))
            done()
            return
        }
        let answered = target.desk.handle(data, receivedAt: receivedAt)
        reply.send(answered)
        // The rest doesn't hold up the next request.
        let bridges = target.bridge === self ? [self] : [self, target.bridge]
        let applied = Self.applied(answered)
        let keeper = self.keeper
        Task { @MainActor in
            // Until the state this tap changed has gone out too.
            for bridge in bridges { await bridge.settled() }
            if applied, keeper.isInBackground(), let model = target.model {
                // In a pocket, as for Siri: the change goes to the server now, while the app
                // still runs, and a background refresh is booked for anything left.
                _ = await model.session.syncNow(within: IntentRunner.syncCap)
                model.scheduleBackgroundRefresh()
                for bridge in bridges { await bridge.settled() }
            }
            done()
        }
    }

    /// A message that waits for no reply (a workout summary), kept on this phone.
    private func receive(_ data: Data) async {
        let done = keeper.wake("Time Card workout summary")
        defer { done() }
        await target()?.desk.receive(data)
    }

    /// True when the reply says a command was applied.
    private static func applied(_ answered: Data) -> Bool {
        guard case .reply(let reply)? = try? WatchEnvelope.decode(answered).message else { return false }
        return reply.appliedAt != nil
    }

    private func updateStatus() {
        let next = WatchLinkStatus(paired: paired, installed: installed, reachable: reachable)
        if next != status { status = next }
    }

    // MARK: Publishing

    /// Coalesced over `coalesce`; every state comes from `desk.makeState()`.
    func publish(reason: PublishReason) {
        pendingReasons.append(reason)
        guard pendingPublish == nil else { return }
        let delay = coalesce
        pendingPublish = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            await self?.flushPublish()
        }
    }

    /// Waits until the publishes asked for so far (and any workout launch they made) are done.
    func settled() async {
        while let pending = pendingPublish {
            await pending.value
            if pendingPublish == pending { break }
        }
        for launch in launches { await launch.value }
    }

    private func flushPublish() async {
        pendingPublish = nil
        pendingReasons = []
        guard paired, installed else { return }
        // Before the session has loaded (or while its data is sealed) there's nothing true to
        // say: a signed-out state would stop the watch's workout.
        guard let model, model.storageError == nil, model.session.hasOpened else { return }
        // Making the state saves the counter.
        let release = keeper.hold("Time Card watch state")
        defer { release() }

        let before = desk.lastPhase
        let state = desk.makeState()
        guard let data = try? WatchEnvelope(.state(state)).data() else { return }
        let after = WatchDisplay.phase(state)
        try? transport.publishContext(data)
        let reachableNow = transport.isReachable

        if WatchComplicationPusher.shouldPush(before: before, after: after, reachable: reachableNow,
                                              complicationEnabled: complicationEnabled) {
            _ = transport.transferComplicationState(data)
        }
        // The context first: `HKWorkoutConfiguration` carries no shift, so the watch reads it there.
        if WatchComplicationPusher.shouldLaunchWorkout(before: before, state: state,
                                                       openedByWatch: state.shiftId.map(desk.openedByWatch) ?? false,
                                                       watchAppInstalled: installed) {
            launchWorkout()
        }
        if reachableNow { try? await transport.post(data) }
    }

    private func launchWorkout() {
        let launcher = self.launcher
        launches.removeAll { $0.isCancelled }
        let task = Task { @MainActor [weak self] in
            let result = await launcher.startShiftWorkout(timeout: Self.launchTimeout)
            self?.lastLaunch = result
        }
        launches.append(task)
        if launches.count > 4 { launches.removeFirst(launches.count - 4) }
    }
}
