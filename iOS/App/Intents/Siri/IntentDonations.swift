import AppIntents
import Foundation
import TimeCardCore

/// Tells Siri when someone does in the app what they could have said, so iOS can suggest
/// it at the right moment ("Clock In" around the time you usually start, "Next Row" while
/// you're working). Only routine, repeatable actions are donated; one-off fixes aren't.
///
/// Siri and Shortcuts runs are logged by iOS itself, so only actions from the app's own
/// buttons donate: `performed(_:reply:state:)` does nothing inside an intent.
enum IntentDonations {
    /// Hands an intent to iOS. Tests collect them instead.
    @MainActor static var donor: @MainActor (any AppIntent) -> Void = { intent in
        IntentDonationManager.shared.donate(intent: intent)
    }

    /// The intent that does what this command did, or nil when it isn't worth suggesting.
    static func intent(for command: FieldCommand, state: FieldState?) -> (any AppIntent)? {
        switch command {
        case .clockIn(let fieldId):
            let field = fieldId.flatMap { id in state?.liveFields.first { $0.id == id } }
            return ClockInIntent(field: field.map(VoiceCatalog.field(for:)))
        case .clockOut:
            return ClockOutIntent()
        case .startBreak(let kind, _):
            return TakeBreakIntent(kind: BreakOption(kind))
        case .endBreak:
            return BackToWorkIntent()
        case .markNextRow, .markRow:
            // A row number is never the same twice; "next row" is what to suggest.
            return NextRowIntent()
        case .moveTo(let blockId, _):
            guard let state, let block = state.block(blockId), let field = state.field(block.fieldId) else { return nil }
            return MoveToBlockIntent(block: VoiceCatalog.block(for: block, field: field))
        case .markTrees, .addShiftNote, .addTreeNote, .changeStart, .undo, .cancelShift:
            return nil
        }
    }

    /// After a field action: donates it when it worked, came from the app's own buttons (not
    /// an intent) and is worth suggesting.
    @MainActor
    static func performed(_ command: FieldCommand, reply: FieldReply, state: FieldState?) {
        guard reply.succeeded, !IntentContext.isRunning, let intent = intent(for: command, state: state) else { return }
        donor(intent)
    }
}

extension AppModel {
    /// For the app's own buttons: runs a field action exactly as Siri and the lock screen
    /// do, then lets Siri learn from it and refreshes the rows Siri knows by name.
    @discardableResult
    func performInApp(_ command: FieldCommand) -> FieldReply {
        let reply = actions.perform(command)
        IntentDonations.performed(command, reply: reply, state: actions.state())
        if reply.succeeded { SiriSuggestions.shared.changed() }
        return reply
    }
}
