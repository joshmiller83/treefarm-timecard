import AppIntents
import Foundation
import TimeCardCore

// Siri and Shortcuts commands for work in the field. Each is a thin shell: it runs the
// command's logic in `VoiceCommands` (or a multi-step `SiriFlows` flow) and speaks what
// that says, which is TreeFarmKit's wording. None opens the app, and all of them run with
// the phone locked in a pocket: the database stays readable after the first unlock.

// MARK: Clock

struct ClockInIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock In"
    static var description: IntentDescription? { IntentDescription("Starts a shift and the lock-screen timer, and says which row is next.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Field", description: "Leave empty to keep working the field you were in.")
    var field: FieldEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Clock in at \(\.$field)")
    }

    init() {}

    init(field: FieldEntity?) {
        self.field = field
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let fieldId = field?.fieldId
        let reply = await IntentRunner.voice { await $0.clockIn(field: fieldId) }
        return .result(dialog: reply.dialog)
    }
}

struct ClockOutIntent: AppIntent {
    static let title: LocalizedStringResource = "Clock Out"
    static var description: IntentDescription? { IntentDescription("Ends the shift after asking first, then says the hours and trees.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await IntentRunner.voice { voice in
            await voice.clockOut { question in await self.askYesNo(question, yes: "Clock out") }
        }
        return .result(dialog: reply.dialog)
    }
}

// MARK: Breaks

struct TakeBreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Take a Break"
    static var description: IntentDescription? { IntentDescription("Starts lunch or a break. Turn on “Ask for a break reason” in Settings to be asked what a break is for.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Break", default: .rest)
    var kind: BreakOption

    @Parameter(title: "Reason", requestValueDialog: "What’s the break for?")
    var reason: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Take \(\.$kind)") {
            \.$reason
        }
    }

    init() {}

    init(kind: BreakOption) {
        self.kind = kind
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kind = kind.kind, given = reason
        let reply = await IntentRunner.voice { voice in
            await voice.takeBreak(kind, reason: given) { question in
                try? await self.$reason.requestValue(.say(question))
            }
        }
        return .result(dialog: reply.dialog)
    }
}

struct BackToWorkIntent: AppIntent {
    static let title: LocalizedStringResource = "Back to Work"
    static var description: IntentDescription? { IntentDescription("Ends lunch or a break and says how long it was.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await IntentRunner.voice { await $0.backToWork() }
        return .result(dialog: reply.dialog)
    }
}

// MARK: Rows

struct NextRowIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Row"
    static var description: IntentDescription? { IntentDescription("Marks the row you're on shaped, like the lock-screen button, and says which row is next.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await IntentRunner.voice { await $0.nextRow() }
        return .result(dialog: reply.dialog)
    }
}

struct MarkRowByNumberIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a Row"
    static var description: IntentDescription? { IntentDescription("Marks a whole row shaped. A row far from where you are is checked first, in case Siri misheard.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Row", requestValueDialog: "Which row?")
    var row: RowEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark \(\.$row) shaped")
    }

    init() {}

    init(row: RowEntity) {
        self.row = row
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await SiriFlows.markRow(
            row,
            askRow: { try await self.$row.requestValue(.say(VoiceText.whichRow)) },
            confirm: { question in await self.askYesNo(question, yes: "Mark it") })
        return .result(dialog: reply.dialog)
    }
}

struct MarkTreesIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Trees"
    static var description: IntentDescription? { IntentDescription("Marks some trees in one row: from the first tree to the last.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Row", requestValueDialog: "Which row?")
    var row: RowEntity?

    @Parameter(title: "First tree", inclusiveRange: (1, 300), requestValueDialog: "First tree?")
    var firstTree: Int?

    @Parameter(title: "Last tree", inclusiveRange: (1, 300), requestValueDialog: "Last tree?")
    var lastTree: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Mark trees \(\.$firstTree) to \(\.$lastTree) in \(\.$row)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await SiriFlows.markTrees(
            row: row, first: firstTree, last: lastTree,
            askRow: { try await self.$row.requestValue(.say(VoiceText.whichRow)) },
            askFirst: { try await self.$firstTree.requestValue(.say(VoiceText.firstTree)) },
            askLast: { try await self.$lastTree.requestValue(.say(VoiceText.lastTree)) })
        return .result(dialog: reply.dialog)
    }
}

struct MoveToBlockIntent: AppIntent {
    static let title: LocalizedStringResource = "Move to a Block"
    static var description: IntentDescription? { IntentDescription("Sets where you're working, so “next row” starts there.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Block", requestValueDialog: "Which block?")
    var block: BlockEntity?

    @Parameter(title: "Row", description: "Leave empty for the block's first open row.", inclusiveRange: (1, 300))
    var row: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Move to \(\.$block)") {
            \.$row
        }
    }

    init() {}

    init(block: BlockEntity) {
        self.block = block
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await SiriFlows.moveTo(block, row: row, askBlock: { try await self.$block.requestValue(.say(VoiceText.whichBlock)) })
        return .result(dialog: reply.dialog)
    }
}

struct UndoIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo"
    static var description: IntentDescription? { IntentDescription("Takes back the last row, break, note or move.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await IntentRunner.voice { await $0.undo() }
        return .result(dialog: reply.dialog)
    }
}

// MARK: Notes and times

struct AddShiftNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a Note"
    static var description: IntentDescription? { IntentDescription("Adds a dictated note to today's shift.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Note", requestValueDialog: "What’s the note?")
    var note: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$note) to today's notes")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await SiriFlows.addNote(note, askText: { try await self.$note.requestValue(.say(VoiceText.whatsTheNote)) })
        return .result(dialog: reply.dialog)
    }
}

struct NoteTreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Note a Tree"
    static var description: IntentDescription? { IntentDescription("Leaves a note on one tree, with a flag if it needs attention, is dead or needs replanting. The row is the one you're on unless you pick one.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Row", description: "Leave empty for the row you're on.", requestValueDialog: "Which row?")
    var row: RowEntity?

    @Parameter(title: "Tree", inclusiveRange: (1, 300), requestValueDialog: "Which tree?")
    var tree: Int?

    @Parameter(title: "Note", requestValueDialog: "What’s the note?")
    var note: String?

    @Parameter(title: "Flag", requestValueDialog: "Any flag? Needs attention, dead, replant, or none.")
    var flag: FlagOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Note tree \(\.$tree) in \(\.$row): \(\.$note)") {
            \.$flag
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await SiriFlows.noteTree(
            row: row, tree: tree, note: note, flag: flag,
            askRow: { try await self.$row.requestValue(.say(VoiceText.whichRow)) },
            askTree: { try await self.$tree.requestValue(.say(VoiceText.whichTree)) },
            askNote: { try await self.$note.requestValue(.say(VoiceText.whatsTheNote)) },
            askFlag: { try await self.$flag.requestValue(.say(VoiceText.anyFlag)) })
        return .result(dialog: reply.dialog)
    }
}

struct FixStartTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Fix My Start Time"
    static var description: IntentDescription? { IntentDescription("Changes when the open shift started, checked by the same rules as the app.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Start time", kind: .time, requestValueDialog: "What time did you start?")
    var time: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("I started at \(\.$time)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = try await SiriFlows.fixStart(time, askTime: { try await self.$time.requestValue(.say(VoiceText.whatTime)) })
        return .result(dialog: reply.dialog)
    }
}

/// One App Shortcut for the less frequent commands (an app gets ten App Shortcuts):
/// "Add a note", "Note a tree", "Mark trees", "Fix my start time" in Time Card.
struct FieldTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Notes and Fixes"
    static var description: IntentDescription? { IntentDescription("Add a note, note a tree, mark some trees, or fix your start time.") }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Task", requestValueDialog: "Add a note, note a tree, mark trees, or fix your start time?")
    var task: FieldTask

    @Parameter(title: "Note", requestValueDialog: "What’s the note?")
    var note: String?

    @Parameter(title: "Row", requestValueDialog: "Which row?")
    var row: RowEntity?

    @Parameter(title: "Tree", inclusiveRange: (1, 300), requestValueDialog: "Which tree?")
    var tree: Int?

    @Parameter(title: "Last tree", inclusiveRange: (1, 300), requestValueDialog: "Last tree?")
    var lastTree: Int?

    @Parameter(title: "Flag", requestValueDialog: "Any flag? Needs attention, dead, replant, or none.")
    var flag: FlagOption?

    @Parameter(title: "Start time", kind: .time, requestValueDialog: "What time did you start?")
    var time: Date?

    static var parameterSummary: some ParameterSummary {
        Switch(\.$task) {
            Case(.addNote) { Summary("\(\.$task): \(\.$note)") }
            Case(.noteTree) {
                Summary("\(\.$task): tree \(\.$tree) in \(\.$row), \(\.$note)") {
                    \.$flag
                }
            }
            Case(.markTrees) { Summary("\(\.$task) \(\.$tree) to \(\.$lastTree) in \(\.$row)") }
            Case(.fixStart) { Summary("\(\.$task): \(\.$time)") }
            DefaultCase { Summary("\(\.$task)") }
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let askRow: SiriFlows.Asker<RowEntity> = { try await self.$row.requestValue(.say(VoiceText.whichRow)) }
        let reply: VoiceReply
        switch task {
        case .addNote:
            reply = try await SiriFlows.addNote(note, askText: { try await self.$note.requestValue(.say(VoiceText.whatsTheNote)) })
        case .noteTree:
            reply = try await SiriFlows.noteTree(
                row: row, tree: tree, note: note, flag: flag, askRow: askRow,
                askTree: { try await self.$tree.requestValue(.say(VoiceText.whichTree)) },
                askNote: { try await self.$note.requestValue(.say(VoiceText.whatsTheNote)) },
                askFlag: { try await self.$flag.requestValue(.say(VoiceText.anyFlag)) })
        case .markTrees:
            reply = try await SiriFlows.markTrees(
                row: row, first: tree, last: lastTree, askRow: askRow,
                askFirst: { try await self.$tree.requestValue(.say(VoiceText.firstTree)) },
                askLast: { try await self.$lastTree.requestValue(.say(VoiceText.lastTree)) })
        case .fixStart:
            reply = try await SiriFlows.fixStart(time, askTime: { try await self.$time.requestValue(.say(VoiceText.whatTime)) })
        }
        return .result(dialog: reply.dialog)
    }
}
