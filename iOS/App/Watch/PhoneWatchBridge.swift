import Foundation
import Observation
import TimeCardCore

// STUB: slice d replaces
//
// The iPhone's side of the watch link (docs/watch.md 1.3): reads the transport's events in one
// main-actor loop, answers each request through `WatchDesk` (exactly one reply, holding a
// background task until it's sent), publishes the state (coalesced over 250 ms, only when the
// watch is paired with the app installed), pushes complication updates on phase changes, and
// starts the watch workout after a phone clock-in. Slice 0 fixed the signatures and the
// `AppModel` hooks that call `publish(reason:)`; slice d writes the rest, test-first.

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
}

@MainActor
@Observable
final class PhoneWatchBridge {
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let transport: any WatchTransport
    @ObservationIgnored private let launcher: any WatchWorkoutLauncher
    @ObservationIgnored let desk: WatchDesk
    private(set) var status: WatchLinkStatus = .noWatch

    init(model: AppModel, transport: any WatchTransport, launcher: any WatchWorkoutLauncher, desk: WatchDesk) {
        self.model = model
        self.transport = transport
        self.launcher = launcher
        self.desk = desk
    }

    /// Called once from `AppModel.init`.
    func activate() {
        transport.activate()
    }

    /// Coalesced over 250 ms; every state comes from `desk.makeState()`.
    func publish(reason: PublishReason) {}
}
