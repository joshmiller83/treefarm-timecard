import Foundation
import Observation
import TreeFarmKit

// STUB: slice a replaces
//
// The only thing the views, intents and workout code talk to (docs/watch.md 1.4). It holds the
// confirmed state (the newest `WatchState` that `supersedes` the current one), the courier's
// outbox and in-flight requests, the displayed state (`WatchOptimism.displayed`), the reach,
// the waiting count and the toast. Slice 0 fixed the signatures below; slice a writes it,
// test-first, keeping them.
//
// At launch it registers these observers (8.3): `ShiftWorkout.shared.reconcile(change.workout)`,
// `ActionButtonDonor.shared.update(change.displayed)`, `WatchShortcuts.updateAppShortcutParameters()`
// when the first chip changes, and `WatchStateFile.write` followed by
// `WidgetCenter.shared.reloadTimelines(ofKind: "timecard.watch.shift")` when
// `ComplicationReload.needsReload` says so.

/// How the phone can be reached: `.reachable`, `.outOfReach`, `.needsUnlock`, `.neverConnected`.
typealias PhoneReach = WatchDisplay.Reach

/// Where a command came from.
enum WatchSource: Sendable {
    case button, doubleTap, crown, siri, actionButton
}

/// What became of a command.
enum WatchOutcome: Equatable, Sendable {
    /// The phone did it.
    case done(WatchReply)
    /// The phone refused it; `reply.speech` says why.
    case refused(WatchReply)
    /// Saved on the watch for later; the string is what to show or say.
    case queued(String)
    /// Not sent and not saved (live-only with the phone away, or refused by `WatchPrecheck`).
    case notSent(String)
}

/// The short message over the bottom of the timer (docs/watch.md 3.10).
struct WatchToast: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case success, refusal, saved, info }

    var text: String
    var kind: Kind

    /// 2.5 s for success and "Saved on watch", 4 s for a refusal.
    var duration: TimeInterval { kind == .refusal ? 4 : 2.5 }
}

/// What the model's observers hear after every state, outbox or in-flight change.
struct WatchModelChange {
    let displayed: WatchState?
    let waitingCount: Int
    let workout: WorkoutInputs
}

@MainActor
@Observable
final class WatchShiftModel {
    static let shared = WatchShiftModel()

    private(set) var confirmed: WatchState?
    private(set) var displayed: WatchState?
    private(set) var reach: PhoneReach = .neverConnected
    /// Outbox items not in flight.
    private(set) var waitingCount = 0
    var toast: WatchToast?

    @ObservationIgnored private var observers: [@MainActor (WatchModelChange) -> Void] = []

    /// Activates the transport (WatchAppDelegate calls it first thing at launch).
    func activate() {}

    func perform(_ command: FieldCommand, source: WatchSource) async -> WatchOutcome {
        .notSent(WatchPrecheck.refusal(for: command, state: displayed) ?? WatchDisplay.neverConnected)
    }

    func ask(_ question: FieldQuestion) async -> String {
        WatchDisplay.askNeedsPhone
    }

    func confirmation(for command: FieldCommand) -> String? {
        displayed.flatMap { WatchConfirm.question(for: command, state: $0, now: Date()) }
    }

    func undo() async -> WatchOutcome {
        .notSent(WatchDisplay.undoNeedsPhone)
    }

    /// `.cancelShift(displayed.shiftId)`, offered for 2 minutes after a watch clock-in.
    func undoClockIn() async -> WatchOutcome {
        guard let shiftId = displayed?.shiftId else { return .notSent(Speech.notClockedIn) }
        return await perform(.cancelShift(shiftId), source: .button)
    }

    func refresh() async {}

    func addObserver(_ observer: @escaping @MainActor (WatchModelChange) -> Void) {
        observers.append(observer)
    }
}
