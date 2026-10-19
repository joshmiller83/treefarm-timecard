import Foundation
import Observation
import TimeCardCore

// The iPhone's side of the watch link (docs/watch.md 1.3). `AppModel` makes and activates it
// in `init`, not in a view: a watch message can launch the app in the background with no
// scene, where the window's `.task` never runs.
//
// - One main-actor loop reads the transport's events in WatchConnectivity's order (no
//   callback gets its own `Task`), so nothing here is ever assumed to run on the main actor
//   from WatchConnectivity's queue.
// - Each request is answered exactly once, through `WatchDesk`, after the app's one start has
//   finished (never a false "sign in"), holding a background task until the reply is sent.
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

@MainActor
@Observable
final class PhoneWatchBridge {
    /// How long publishes gather before one state goes out.
    @ObservationIgnored var coalesce: Duration = .milliseconds(250)
    /// How long `startWatchApp` may take: its completion can hang when the watch is off.
    static let launchTimeout: Duration = .seconds(10)
    @ObservationIgnored var now: () -> Date = Date.init

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
                desk.receive(data)
                return
            }
            await answer(data, through: reply)
        case .contextReceived(_, let done), .userInfoReceived(_, let done):
            // The watch never sends these; mark them handled all the same.
            done()
        }
    }

    /// Exactly one reply per request, after the app has started.
    private func answer(_ data: Data, through reply: WatchReplySink) async {
        let receivedAt = now()
        let hold = BackgroundTask(name: "Time Card watch reply")
        hold.begin()
        defer { hold.end() }
        if let model {
            await model.start()
            // Locked since a restart: the data can't be read, so the tap waits on the watch.
            if model.storageError != nil {
                reply.send(WatchDesk.unavailable(data, speech: Speech.unlockOnce))
                return
            }
        }
        reply.send(desk.handle(data, receivedAt: receivedAt))
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
