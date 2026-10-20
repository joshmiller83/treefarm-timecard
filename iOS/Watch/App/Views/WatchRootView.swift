import SwiftUI
import TreeFarmKit

/// What the watch shows (docs/watch.md 3.1):
///
/// - first launch with recording on and Health never asked → the Health card (2.4), first of all,
///   because the Action button only launches the app until Health was asked once
/// - signed out or never connected → `SetupScreen`
/// - off the clock → `OffClockScreen` (one page), or the shift summary right after a clock-out
/// - on the clock → horizontal pages, opening on Now: Controls ← Now → Today
///
/// It also owns the confirmation (Double Tap is off while it shows, so a pinch can never
/// confirm a clock-out), the Queue sheet behind the badge, and the wrist-raise rule.
struct WatchRootView: View {
    @State private var model = WatchShiftModel.shared
    @State private var workout = ShiftWorkout.shared
    @State private var pending: PendingConfirmation?
    @State private var showQueue = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let state = model.displayed
        let phase = WatchDisplay.phase(state)
        NavigationStack {
            Group {
                if workout.needsHealthOnboarding {
                    HealthOnboardingView(workout: workout)
                } else {
                    screen(state, phase)
                }
            }
        }
        .sheet(isPresented: $showQueue) {
            QueueSheet(model: model)
        }
        .confirmationDialog(pending?.question ?? "", isPresented: dialogBinding, titleVisibility: .visible, presenting: pending) { confirm in
            Button(confirm.confirmLabel, role: confirm.isClockOut ? .destructive : nil) {
                run(confirm.command, confirm.source)
            }
            Button(WatchDisplay.keepWorking) {}
        }
        .onChange(of: phase) { old, new in
            // A shift that starts always opens on Now.
            if old == .offClock, Self.onTheClock(new) { model.pages.selection = .now }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            switch newPhase {
            case .active: model.sceneBecameActive()
            default: model.sceneWentAway()
            }
        }
    }

    @ViewBuilder
    private func screen(_ state: WatchState?, _ phase: WatchPhase) -> some View {
        switch phase {
        case .noData, .signedOut:
            SetupScreen(model: model, phase: phase)
        case .offClock:
            if let summary = model.summary {
                ShiftDoneScreen(closed: summary, waiting: model.clockOutWaiting,
                                workout: workoutSummary(for: summary), done: dismissSummary)
            } else if let state {
                OffClockScreen(model: model, state: state, primaryEnabled: !dialogShown, act: act) { showQueue = true }
            }
        case .working, .lunch, .onBreak:
            if let state { shiftPages(state) }
        }
    }

    // MARK: Pages

    private func shiftPages(_ state: WatchState) -> some View {
        TabView(selection: $model.pages.selection) {
            ControlsScreen(model: model, state: state, act: act)
                .tag(ShiftPage.controls)
            NowScreen(model: model, state: state,
                      primaryEnabled: model.pages.primaryActionEnabled(dialogShown: dialogShown), act: act) { showQueue = true }
                .tag(ShiftPage.now)
            TodayScreen(model: model, state: state) { showQueue = true }
                .tag(ShiftPage.today)
        }
        .tabViewStyle(.page)
    }

    private static func onTheClock(_ phase: WatchPhase) -> Bool {
        phase == .working || phase == .lunch || phase == .onBreak
    }

    private var dialogShown: Bool { pending != nil || showQueue }

    private var dialogBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    // MARK: Acting

    /// Asks first when the engine would (clock-out, a far row), then runs the command.
    private func act(_ command: FieldCommand, _ source: WatchSource) {
        if let question = model.confirmation(for: command) {
            pending = PendingConfirmation(question: question, command: command, source: source)
            return
        }
        run(command, source)
    }

    /// The battery warning at clock-in comes from the workout as it starts (docs/watch.md 2.8).
    private func run(_ command: FieldCommand, _ source: WatchSource) {
        Task {
            _ = await model.perform(command, source: source)
            switch command {
            case .startBreak, .endBreak:
                // From Controls, the result shows where it matters: on Now.
                model.pages.selection = .now
            default:
                break
            }
        }
    }

    private func workoutSummary(for closed: ClosedShift) -> WorkoutSummary? {
        guard let summary = workout.live.lastSummary, summary.shiftId == closed.shiftId else { return nil }
        return summary
    }

    /// Done: the summary goes, on the model and in the workout's slot alike.
    private func dismissSummary() {
        model.dismissSummary()
        workout.dismissSummary()
    }
}

/// A question asked before a command runs.
struct PendingConfirmation: Identifiable {
    let id = UUID()
    let question: String
    let command: FieldCommand
    let source: WatchSource

    var isClockOut: Bool {
        if case .clockOut = command { return true }
        return false
    }

    /// "Yes, clock out", or the row itself ("Row 40 done").
    var confirmLabel: String {
        isClockOut ? WatchDisplay.yesClockOut : WatchDisplay.label(for: command)
    }
}
