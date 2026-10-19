import AppIntents
import Foundation
import TreeFarmKit

/// What the watch's intents need from `WatchShiftModel` (docs/watch.md 4.1): the displayed
/// state, whether the phone is in reach, and the model's own doors for commands, questions,
/// confirmations and undo. Intents never talk to WatchConnectivity or the outbox themselves,
/// so a Siri tap queues, waits and is undone exactly like a button tap.
@MainActor
protocol WatchIntentModel: AnyObject {
    var displayed: WatchState? { get }
    var reach: PhoneReach { get }
    func perform(_ command: FieldCommand, source: WatchSource) async -> WatchOutcome
    func ask(_ question: FieldQuestion) async -> String
    func confirmation(for command: FieldCommand) -> String?
    func undo() async -> WatchOutcome
}

extension WatchShiftModel: WatchIntentModel {}

/// The one model the intents run against, and the workout they can attach to.
@MainActor
enum WatchIntentRunner {
    static var model: any WatchIntentModel { WatchShiftModel.shared }

    /// Starts or attaches the shift's workout for a shift already on the clock (the Action
    /// button's first press after a phone clock-in): reconcile decides, as for a phone launch.
    static func attachWorkout() {
        ShiftWorkout.shared.handleLaunch()
    }
}

extension IntentDialog {
    /// A dialog that says exactly this text (never looked up as a localization key).
    static func say(_ text: String) -> IntentDialog {
        IntentDialog("\(text)")
    }
}

extension AppIntent {
    /// Asks a yes-or-no question out loud and waits. "No", or no answer, gives false and
    /// nothing changes. Yes and no take the everyday words people say with gloves on.
    func askYesNo(_ question: String, yes: LocalizedStringResource) async -> Bool {
        let action = ConfirmationActionName.custom(
            acceptLabel: yes, acceptAlternatives: ["Yes", "Yeah", "Yep", "Sure", "Do it", "Go ahead"],
            denyLabel: "No", denyAlternatives: ["Nope", "Not yet", "Cancel", "Never mind", "Wait"])
        do {
            try await requestConfirmation(actionName: action, dialog: .say(question))
            return true
        } catch {
            return false
        }
    }
}
