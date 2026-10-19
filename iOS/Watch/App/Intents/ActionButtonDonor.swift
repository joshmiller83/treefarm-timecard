import AppIntents
import Foundation
import Observation
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
///
/// The displayed state can say working before the shift's workout session is running, and a
/// donation made then may not count, so it donates again once the session runs: it follows
/// the workout's recording status (`ShiftWorkout.shared.live.recording`) as well as the state.
@MainActor
final class ActionButtonDonor {
    static let shared = ActionButtonDonor()

    private struct Decision: Equatable {
        var phase: WatchPhase
        var next: ActionButtonNext?
        var sessionRunning: Bool
    }

    private let donating: any ActionButtonDonating
    /// The workout's recording status, read under observation so a change is heard.
    private let recording: @MainActor () -> WorkoutLive.Recording
    private var displayed: WatchState?
    /// What was last decided, so a row (same phase, same session) never donates again.
    private var last: Decision?

    init(donating: any ActionButtonDonating = IntentActionButtonDonations(),
         recording: @escaping @MainActor () -> WorkoutLive.Recording = { ShiftWorkout.shared.live.recording }) {
        self.donating = donating
        self.recording = recording
        followRecording()
    }

    /// Called with every displayed state.
    func update(_ displayed: WatchState?) {
        self.displayed = displayed
        decide()
    }

    private func decide() {
        let status = recording()
        let decision = Decision(phase: WatchDisplay.phase(displayed),
                                next: Self.next(for: displayed, sessionPossible: Self.workoutsPossible(status)),
                                sessionRunning: status == .recording || status == .paused)
        guard decision != last else { return }
        last = decision
        if let next = decision.next { donating.donate(next) }
    }

    private func followRecording() {
        _ = withObservationTracking {
            recording()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.followRecording()
                self?.decide()
            }
        }
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
        workoutsPossible(ShiftWorkout.shared.live.recording)
    }

    static func workoutsPossible(_ status: WorkoutLive.Recording) -> Bool {
        switch status {
        case .off, .notAuthorized: false
        default: true
        }
    }
}
