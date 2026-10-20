import AppIntents
import Foundation
import TreeFarmKit

// Siri on the watch: the ten commands in docs/watch.md 4.1. iPhone App Shortcuts don't run on
// the watch, so the watch app has its own. Each intent is a thin shell over `WatchVoice` and
// says what that returns; `speak(model:…)` is the part tests run against a scripted model.
//
// Only Clock In opens the app: the shift's workout starts in the foreground, where
// WatchConnectivity is reachable. The others run in place, and with the phone away they wait
// on the watch like any tap.

// MARK: 1 · Clock in

struct ClockInIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock In"
    static var description: IntentDescription? { IntentDescription("Starts a shift and its workout, and says which row is next.") }
    /// The workout starts in the foreground, where WatchConnectivity is reachable.
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.clockIn(model, source: .siri)
    }
}

// MARK: 2 · Clock out

struct ClockOutIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock Out"
    static var description: IntentDescription? { IntentDescription("Ends the shift after asking first.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await speak(model: WatchIntentRunner.model) { question in
            await self.askYesNo(question, yes: "Clock out")
        }
        return .result(dialog: .say(said))
    }

    @MainActor
    func speak(model: any WatchIntentModel, confirm: (String) async -> Bool) async -> String {
        await WatchVoice.clockOut(model, confirm: confirm)
    }
}

// MARK: 3, 4, 5 · Breaks

struct TakeLunchIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Lunch"
    static var description: IntentDescription? { IntentDescription("Starts lunch. The shift's workout pauses.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.run(.startBreak(.lunch, reason: ""), model, source: .siri)
    }
}

struct TakeBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Take a Break"
    static var description: IntentDescription? { IntentDescription("Starts a break. The shift's workout pauses.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.run(.startBreak(.break, reason: ""), model, source: .siri)
    }
}

struct BackToWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Back to Work"
    static var description: IntentDescription? { IntentDescription("Ends lunch or a break and says how long it was.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.run(.endBreak, model, source: .siri)
    }
}

// MARK: 6, 7 · Rows

struct NextRowIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Row"
    static var description: IntentDescription? { IntentDescription("Marks the row the watch shows and says which is next.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.nextRow(model, source: .siri)
    }
}

struct MarkRowIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a Row"
    static var description: IntentDescription? { IntentDescription("Marks a row shaped. A row far from where you are is checked first, in case Siri misheard.") }
    static let openAppWhenRun = false

    @Parameter(title: "Row", requestValueDialog: "Which row?")
    var row: WatchRowEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$row) shaped")
    }

    init() {}

    init(row: WatchRowEntity) {
        self.row = row
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await speak(model: WatchIntentRunner.model, askRow: {
            try await self.$row.requestValue(.say("Which row?"))
        }, confirm: { question in
            await self.askYesNo(question, yes: "Mark it")
        })
        return .result(dialog: .say(said))
    }

    @MainActor
    func speak(model: any WatchIntentModel, askRow: () async throws -> WatchRowEntity,
               confirm: (String) async -> Bool) async -> String {
        await WatchVoice.markRow(row?.rowRef, model, askRow: { try await askRow().rowRef }, confirm: confirm)
    }
}

// MARK: 8 · Undo

struct UndoIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo"
    static var description: IntentDescription? { IntentDescription("Takes back the last thing you did. A tap still waiting for your phone is taken back on the watch.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model)))
    }

    @MainActor
    func speak(model: any WatchIntentModel) async -> String {
        await WatchVoice.undo(model)
    }
}

// MARK: 9 · Status

struct StatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How’s My Day"
    static var description: IntentDescription? { IntentDescription("Hours, trees, pace and the next row in one answer.") }
    static let openAppWhenRun = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: .say(await speak(model: WatchIntentRunner.model, now: Date())))
    }

    @MainActor
    func speak(model: any WatchIntentModel, now: Date) async -> String {
        await WatchVoice.status(model, now: now)
    }
}

// MARK: 10 · A note

struct AddNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Note"
    static var description: IntentDescription? { IntentDescription("Adds a dictated note to today's shift.") }
    static let openAppWhenRun = false

    @Parameter(title: "Note", requestValueDialog: "What’s the note?")
    var text: String?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let said = await speak(model: WatchIntentRunner.model) {
            try await self.$text.requestValue(.say("What’s the note?"))
        }
        return .result(dialog: .say(said))
    }

    @MainActor
    func speak(model: any WatchIntentModel, askText: () async throws -> String) async -> String {
        await WatchVoice.addNote(text, model, askText: askText)
    }
}
