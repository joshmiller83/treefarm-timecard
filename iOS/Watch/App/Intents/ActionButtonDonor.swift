import AppIntents
import Foundation
import TreeFarmKit

/// What a later Action button press does while the shift's workout runs.
enum ActionButtonNext: Equatable, Sendable {
    /// Working: mark the row the watch shows.
    case markNextRow
    /// On lunch or a break: back to work.
    case resumeWork
}

/// The seam over `donate(result:)`, so the donor is tested without the system.
@MainActor
protocol ActionButtonDonating: AnyObject {
    func donate(_ next: ActionButtonNext)
}

/// Donates the next action as the result of the Action button's workout intent. Only the
/// latest donation counts.
@MainActor
final class IntentActionButtonDonations: ActionButtonDonating {
    func donate(_ next: ActionButtonNext) {
        Task {
            let start = StartShiftWorkoutIntent(style: .treeShift)
            switch next {
            case .markNextRow:
                _ = try? await start.donate(result: .result(actionButtonIntent: MarkNextRowIntent()))
            case .resumeWork:
                _ = try? await start.donate(result: .result(actionButtonIntent: ResumeWorkIntent()))
            }
        }
    }
}

/// Donates the Ultra Action button's next action again on every phase change
/// (docs/watch.md 4.2): `MarkNextRowIntent` while working, `ResumeWorkIntent` on lunch or a
/// break. With no session to give the button a next action (recording off, or Health denied),
/// it donates nothing, and later presses only open the app.
@MainActor
final class ActionButtonDonor {
    static let shared = ActionButtonDonor()

    private let donating: any ActionButtonDonating
    /// False when the watch can't record a workout at all (Health denied or never allowed).
    private let sessionPossible: @MainActor () -> Bool
    /// What was last decided: the phase and the next action, so a row never donates again.
    private var last: (phase: WatchPhase, next: ActionButtonNext?)?

    init(donating: any ActionButtonDonating = IntentActionButtonDonations(),
         sessionPossible: @escaping @MainActor () -> Bool = ActionButtonDonor.workoutsPossible) {
        self.donating = donating
        self.sessionPossible = sessionPossible
    }

    /// Called with every displayed state.
    func update(_ displayed: WatchState?) {
        let phase = WatchDisplay.phase(displayed)
        let next = Self.next(for: displayed, sessionPossible: sessionPossible())
        if let last, last.phase == phase, last.next == next { return }
        last = (phase, next)
        if let next { donating.donate(next) }
    }

    /// The next action for a state, or nil when there's nothing to donate.
    static func next(for state: WatchState?, sessionPossible: Bool) -> ActionButtonNext? {
        guard let state, state.recordWorkouts, sessionPossible else { return nil }
        switch WatchDisplay.phase(state) {
        case .working: return .markNextRow
        case .lunch, .onBreak: return .resumeWork
        case .offClock, .signedOut, .noData: return nil
        }
    }

    /// Whether this watch can run the shift's workout session.
    static func workoutsPossible() -> Bool {
        switch ShiftWorkout.shared.live.recording {
        case .off, .notAuthorized: false
        default: true
        }
    }
}
