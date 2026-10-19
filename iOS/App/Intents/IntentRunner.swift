import Foundation
import TimeCardCore

/// The one door from Siri, Shortcuts, Live Activity buttons and controls into the app.
/// Intents can wake the app in the background with no window, so this makes sure the
/// shared model has started (store open, session restored) before running anything, and
/// says the right thing when it can't: "Unlock your phone once, then try again." before the
/// first unlock after a restart, "Open Time Card to sign in." when signed out.
@MainActor
enum IntentRunner {
    /// Builds Siri's view of the running app. Tests point it at the demo farm.
    static var makeVoice: @MainActor () -> VoiceCommands = { VoiceCommands.live() }

    /// Runs a voice command's logic (see `VoiceCommands`).
    static func voice<Result: Sendable>(_ body: @MainActor @Sendable (VoiceCommands) async -> Result) async -> Result {
        await body(makeVoice())
    }

    /// The farm as the field actions see it, or nil when the app can't open it (locked
    /// since a restart, or signed out). Entity queries read rows, blocks and fields here.
    static func fieldState() async -> FieldState? {
        let voice = makeVoice()
        guard await voice.blocker() == nil else { return nil }
        return voice.actions.state()
    }

    /// Runs a field command for a Live Activity button or a control.
    static func perform(_ command: FieldCommand) async -> FieldReply {
        let voice = makeVoice()
        if let blocked = await voice.blocker() { return FieldReply(speech: blocked, succeeded: false) }
        let reply = voice.actions.perform(command)
        if reply.succeeded { voice.onChange() }
        return reply
    }

    static func answer(_ question: FieldQuestion) async -> String {
        let voice = makeVoice()
        if let blocked = await voice.blocker() { return blocked }
        return voice.actions.answer(question)
    }

    /// A lock-screen button press. Buttons can't speak, so when the action is refused (the row
    /// was shaped by someone else between the screen drawing and the tap, say) the reason's
    /// first sentence shows on the Live Activity in place of the last action, next to the
    /// refreshed row buttons.
    @discardableResult
    static func press(_ command: FieldCommand) async -> FieldReply {
        let reply = await perform(command)
        if !reply.succeeded {
            let actions = makeVoice().actions
            if var snapshot = actions.liveSnapshot() {
                snapshot.lastAction = lockScreenNote(reply.speech)
                actions.onLiveSnapshot?(snapshot)
            }
        }
        return reply
    }

    /// The first sentence, which is all the lock screen has room for:
    /// "Row 14 was shaped by Sam on Oct 16. Next open row is 15." → "Row 14 was shaped by Sam on Oct 16."
    nonisolated static func lockScreenNote(_ speech: String) -> String {
        var quoted = false
        var index = speech.startIndex
        while index < speech.endIndex {
            let ch = speech[index]
            if ch == "\"" { quoted.toggle() }
            let next = speech.index(after: index)
            if !quoted, ".?!".contains(ch), next == speech.endIndex || speech[next] == " " {
                return String(speech[...index])
            }
            index = next
        }
        return speech
    }
}
