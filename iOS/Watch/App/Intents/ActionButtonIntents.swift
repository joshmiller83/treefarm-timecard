import AppIntents
import Foundation
import TreeFarmKit

// The Ultra's Action button (docs/watch.md 4.2). Set it up once in Settings › Action Button ›
// Workout › Time Card. These live in the watch app target (not an extension) and keep the
// default `openAppWhenRun`: they run in the app that owns the shift's workout session.
//
// - First press: `StartShiftWorkoutIntent` clocks in and records (or, with a shift already on
//   the clock, only starts its workout).
// - Later presses: the donated next action, `MarkNextRowIntent` while working or
//   `ResumeWorkIntent` on lunch or a break (`ActionButtonDonor`).
// - Action + side button: `PauseShiftIntent` (lunch, then breaks), `ResumeShiftIntent`.
// - The button never clocks out: a cuff can press it by accident.

/// The one kind of workout Time Card records.
enum ShiftWorkoutStyle: String, AppEnum, CaseIterable {
    case treeShift

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Shift" }
    static var caseDisplayRepresentations: [ShiftWorkoutStyle: DisplayRepresentation] {
        [.treeShift: DisplayRepresentation(title: "Tree shift", subtitle: "Clock in and record", image: .init(systemName: "leaf.fill"))]
    }
}

struct StartShiftWorkoutIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start Shift"
    static var description: IntentDescription? { IntentDescription("Clocks in and records the shift as a workout.") }

    @Parameter(title: "Shift")
    var workoutStyle: ShiftWorkoutStyle

    static var suggestedWorkouts: [StartShiftWorkoutIntent] {
        [StartShiftWorkoutIntent(style: .treeShift)]
    }

    var displayRepresentation: DisplayRepresentation {
        ShiftWorkoutStyle.caseDisplayRepresentations[workoutStyle] ?? DisplayRepresentation(title: "Tree shift")
    }

    init() {
        workoutStyle = .treeShift
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await speak(model: WatchIntentRunner.model) { WatchIntentRunner.attachWorkout() }
        return .result(dialog: .say(said))
    }

    @MainActor
    func speak(model: any WatchIntentModel, attachWorkout: () -> Void) async -> String {
        await WatchVoice.startShift(model, attachWorkout: attachWorkout)
    }
}

/// The next press while working: marks the row the watch shows.
struct MarkNextRowIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Next Row"
    static var description: IntentDescription? { IntentDescription("Marks the row the watch shows.") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.nextRow(model, source: .actionButton)
    }
}

/// The next press on lunch or a break: back to work.
struct ResumeWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Work"
    static var description: IntentDescription? { IntentDescription("Ends lunch or the break.") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.run(.endBreak, model, source: .actionButton)
    }
}

/// Action + side button: lunch if there's been none today, otherwise a break.
struct PauseShiftIntent: PauseWorkoutIntent {
    static let title: LocalizedStringResource = "Pause Shift"
    static var description: IntentDescription? { IntentDescription("Starts lunch, or a break once you've had lunch.") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.pause(model, source: .actionButton)
    }
}

/// Action + side button while paused: back to work.
struct ResumeShiftIntent: ResumeWorkoutIntent {
    static let title: LocalizedStringResource = "Resume Shift"
    static var description: IntentDescription? { IntentDescription("Ends lunch or the break.") }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.run(.endBreak, model, source: .actionButton)
    }
}
