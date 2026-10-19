import Foundation
import TimeCardCore

/// The one door from Siri, Shortcuts, Live Activity buttons and controls into the app.
/// Intents can wake the app in the background with no window, so this makes sure the
/// shared model has started (store open, session restored) before running anything.
@MainActor
enum IntentRunner {
    static func perform(_ command: FieldCommand) async -> FieldReply {
        let model = AppModel.shared
        if let problem = model.storageError { return FieldReply(speech: problem, succeeded: false) }
        await model.start()
        return model.actions.perform(command)
    }

    static func answer(_ question: FieldQuestion) async -> String {
        let model = AppModel.shared
        if let problem = model.storageError { return problem }
        await model.start()
        return model.actions.answer(question)
    }
}
