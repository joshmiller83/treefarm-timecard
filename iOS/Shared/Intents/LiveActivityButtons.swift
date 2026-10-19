import AppIntents
import Foundation
import TimeCardCore

// Intents behind the Live Activity's buttons and the Control Center controls.
//
// They're compiled into the widget extension (which draws the buttons) and the app.
// As LiveActivityIntents they always run in the app's process, where the store and the
// activity live, so in the extension their `perform` is never called and compiles empty.
//
// In the app each one goes through `IntentRunner.press`: the same field action Siri and the
// app's buttons use, which saves, queues a sync and redraws the activity. Buttons can't
// speak, so when an action is refused (the row was shaped by someone else since the screen
// was drawn, say) the first sentence of the reason shows on the activity instead. They run
// with the phone locked: the database stays readable after the first unlock.

struct MarkRowIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark a Row Shaped"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Block") var blockId: String
    @Parameter(title: "Row") var row: Int

    init() {}

    init(blockId: UUID, row: Int) {
        self.blockId = blockId.uuidString
        self.row = row
    }

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        if let id = UUID(uuidString: blockId) {
            await IntentRunner.press(.markRow(RowRef(blockId: id, row: row)))
        }
#endif
        return .result()
    }
}

struct StartBreakButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start a Break"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        await IntentRunner.press(.startBreak(.break, reason: ""))
#endif
        return .result()
    }
}

struct BackToWorkButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back to Work"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        await IntentRunner.press(.endBreak)
#endif
        return .result()
    }
}

struct UndoButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Undo"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        await IntentRunner.press(.undo)
#endif
        return .result()
    }
}

struct NextRowButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark the Next Row"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        await IntentRunner.press(.markNextRow)
#endif
        return .result()
    }
}

struct ClockInButtonIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clock In"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult {
#if !WIDGET_EXTENSION
        await IntentRunner.press(.clockIn(fieldId: nil))
#endif
        return .result()
    }
}
