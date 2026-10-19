import AppIntents
import Foundation
import TimeCardCore

/// Tells Siri when someone does in the app what they could have said, so iOS can suggest
/// it at the right moment ("Clock In" around the time you usually start, "Next Row" while
/// you're working). Only routine, repeatable actions are donated; one-off fixes aren't.
///
/// Siri and Shortcuts runs are logged by iOS itself, so only the app's own buttons donate,
/// through `AppModel.performInApp(_:)`.
enum IntentDonations {
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
        case .markTrees, .addShiftNote, .addTreeNote, .changeStart, .undo:
            return nil
        }
    }

    static func donate(_ command: FieldCommand, state: FieldState?) {
        guard let intent = intent(for: command, state: state) else { return }
        donate(intent)
    }

    private static func donate(_ intent: some AppIntent) {
        IntentDonationManager.shared.donate(intent: intent)
    }
}

extension AppModel {
    /// For the app's own buttons: runs a field action exactly as Siri and the lock screen
    /// do, then lets Siri learn from it and refreshes the rows Siri knows by name.
    @discardableResult
    func performInApp(_ command: FieldCommand) -> FieldReply {
        let reply = actions.perform(command)
        if reply.succeeded {
            IntentDonations.donate(command, state: actions.state())
            TimeCardShortcuts.updateAppShortcutParameters()
        }
        return reply
    }
}
