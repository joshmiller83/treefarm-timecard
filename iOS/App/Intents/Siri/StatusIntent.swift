import AppIntents
import Foundation
import SwiftUI
import TimeCardCore

/// "How many trees in Time Card?", "What row am I on?", "How much have I made?": Siri
/// answers out loud with TreeFarmKit's words and shows a small card with the same numbers.
/// Pay is said on a locked phone only when "Say pay out loud when locked" is on.
struct AskTimeCardIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Time Card"
    static var description: IntentDescription? { IntentDescription("Hours, trees, where you are, your pace or your pay, said out loud with a small card.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Question", default: .summary)
    var topic: StatusTopic

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Time Card \(\.$topic)")
    }

    init() {}

    init(topic: StatusTopic) {
        self.topic = topic
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let topic = topic
        let reply = await IntentRunner.voice { await $0.status(topic) }
        return .result(dialog: reply.dialog, view: DaySnippetView(card: reply.card))
    }
}
