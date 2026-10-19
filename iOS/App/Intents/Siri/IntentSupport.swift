import AppIntents
import Foundation

extension IntentDialog {
    /// A dialog that says exactly this text (it's never looked up as a localization key).
    static func say(_ text: String) -> IntentDialog {
        IntentDialog("\(text)")
    }
}

extension VoiceReply {
    var dialog: IntentDialog { .say(speech) }
}

extension AppIntent {
    /// Asks a yes-or-no question out loud and waits. "No", or no answer, gives false, and
    /// nothing changes. Yes and no take the everyday words people say with gloves on.
    func askYesNo(_ question: String, yes: LocalizedStringResource) async -> Bool {
        let action = ConfirmationActionName.custom(
            acceptLabel: yes, acceptAlternatives: ["Yes", "Yeah", "Yep", "Sure", "Do it", "Go ahead"],
            denyLabel: "No", denyAlternatives: ["Nope", "Not yet", "Cancel", "Never mind", "Wait"])
        do {
            if #available(iOS 18.0, *) {
                try await requestConfirmation(actionName: action, dialog: .say(question))
            } else {
                try await legacyConfirmation(question, action: action)
            }
            return true
        } catch {
            return false
        }
    }

    /// iOS 17's form of the same question.
    @available(iOS, introduced: 17.0, deprecated: 18.0, message: "iOS 18 has requestConfirmation(actionName:dialog:)")
    private func legacyConfirmation(_ question: String, action: ConfirmationActionName) async throws {
        try await requestConfirmation(result: .result(dialog: .say(question)), confirmationActionName: action)
    }
}
