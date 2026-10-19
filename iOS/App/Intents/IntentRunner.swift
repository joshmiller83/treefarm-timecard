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

    /// Runs a voice command's logic (see `VoiceCommands`). Everything it runs sees
    /// `IntentContext.isRunning`.
    static func voice<Result: Sendable>(_ body: @MainActor @Sendable (VoiceCommands) async -> Result) async -> Result {
        await IntentContext.$isRunning.withValue(true) {
            await body(makeVoice())
        }
    }

    /// The farm as the field actions see it, or nil when the app can't open it (locked
    /// since a restart, or signed out). Entity queries read rows, blocks and fields here.
    static func fieldState() async -> FieldState? {
        await voice { voice in
            guard await voice.blocker() == nil else { return nil }
            return voice.actions.state()
        }
    }

    /// Runs a field command for a Live Activity button or a control.
    static func perform(_ command: FieldCommand) async -> FieldReply {
        await voice { voice in
            if let blocked = await voice.blocker() { return FieldReply(speech: blocked, succeeded: false) }
            let reply = voice.actions.perform(command)
            if reply.succeeded { voice.onChange() }
            VoiceCommands.log.info("button \(VoiceCommands.name(of: command), privacy: .public): \(reply.succeeded ? "done" : "refused", privacy: .public)")
            return reply
        }
    }

    static func answer(_ question: FieldQuestion) async -> String {
        await voice { voice in
            if let blocked = await voice.blocker() { return blocked }
            return voice.actions.answer(question)
        }
    }

    /// A lock-screen button press. Buttons can't speak, so when the action is refused (the row
    /// was shaped by someone else between the screen drawing and the tap, say) the reason's
    /// first sentence shows on the Live Activity in place of the last action, next to the
    /// refreshed row buttons, with no Undo beside it: Undo would take back an earlier action.
    /// When there's no shift to show any more (clocked out on another phone and synced, or
    /// signed out), the press takes the leftover activity down instead of doing nothing.
    @discardableResult
    static func press(_ command: FieldCommand) async -> FieldReply {
        let reply = await perform(command)
        guard !reply.succeeded else { return reply }
        let model = makeVoice().model
        // Without its data (sealed since a restart) the app can't tell what the card should say.
        guard model.storageError == nil else { return reply }
        let actions = model.actions
        if var snapshot = actions.liveSnapshot() {
            snapshot.lastAction = lockScreenNote(reply.speech)
            snapshot.canUndo = false
            actions.onLiveSnapshot?(snapshot)
        } else {
            actions.onLiveSnapshot?(nil)
        }
        return reply
    }

    /// The first sentence, which is all the lock screen has room for:
    /// "Row 14 was shaped by Sam on Oct 16. Next open row is 15." → "Row 14 was shaped by Sam on Oct 16."
    nonisolated static func lockScreenNote(_ speech: String) -> String {
        Speech.firstSentence(speech)
    }

    // MARK: After a change

    /// The longest a change from Siri or the lock screen keeps the app awake to reach the server.
    static let syncCap: Duration = .seconds(8)

    /// After a change from Siri, a lock-screen button or a control. iOS may suspend the app as
    /// soon as the intent returns, so a background task keeps it running until the change is on
    /// its way to the server (a pass now, not after the usual pause, for up to `syncCap`), the
    /// lock screen shows it, and Siri's suggestions have caught up; then a background refresh
    /// is booked for anything still waiting. The intent itself doesn't wait for any of this.
    static func afterChange(_ model: AppModel) {
        let hold = BackgroundTask(name: "Time Card sync")
        hold.begin()
        Task { @MainActor in
            _ = await model.session.syncNow(within: syncCap)
            await model.liveActivity.waitUntilIdle()
            await SiriSuggestions.shared.settled()
            model.scheduleBackgroundRefresh()
            hold.end()
        }
    }

    // MARK: The model

    /// The model intents work on: the shared one, which `reopenStorage()` replaces when the app
    /// woke before the first unlock after a restart (database sealed) and the phone has been
    /// unlocked since.
    static var model: AppModel { AppModel.shared }

    /// Opens the database again for a model that couldn't open it. `VoiceCommands.blocker()`
    /// calls this only once the phone has been unlocked, when the file is readable again.
    /// Returns the new model, which carries its own `storageError` if it still can't open; one
    /// that opens becomes `AppModel.shared`, so the app's window uses it too.
    static func reopenStorage() -> AppModel {
        let fresh = AppModel.reopenIfSealed()
        if fresh.storageError == nil { SiriSuggestions.shared.follow(fresh) }
        return fresh
    }
}

/// Whether the code running now was started by an intent. The app's own buttons teach Siri
/// (`IntentDonations`); an intent's run doesn't, since iOS logs Siri's and Shortcuts' runs
/// itself. Task-local, so it holds for exactly the code an intent runs, however it's reached.
enum IntentContext {
    @TaskLocal static var isRunning = false
}
