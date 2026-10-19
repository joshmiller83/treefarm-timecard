import Foundation
import os
import TimeCardCore

/// What Siri says back, and the card it shows for status questions.
struct VoiceReply: Equatable, Sendable {
    var speech: String
    /// Something changed (or, for questions, there was an answer).
    var succeeded: Bool
    var card: DayCard?

    init(speech: String, succeeded: Bool, card: DayCard? = nil) {
        self.speech = speech
        self.succeeded = succeeded
        self.card = card
    }

    init(_ reply: FieldReply) {
        self.init(speech: reply.speech, succeeded: reply.succeeded)
    }

    static func failed(_ speech: String) -> VoiceReply {
        VoiceReply(speech: speech, succeeded: false)
    }
}

/// Siri's side of the app: one method per voice command. The App Intents are thin shells
/// around these, so this is where the behavior lives and is tested, against the same
/// `FieldActions` the lock screen and the app's buttons use.
///
/// Each method makes sure the app is ready (database open, signed in) before doing or
/// asking anything, asks before clocking out or marking a row Siri may have misheard, and
/// otherwise says exactly what `FieldActions` (TreeFarmKit's `FieldEngine`) says.
@MainActor
struct VoiceCommands {
    /// Asks a yes-or-no question out loud; true means go ahead.
    typealias Confirm = @Sendable (String) async -> Bool
    /// Asks a question out loud; nil when there was no answer.
    typealias Ask = @Sendable (String) async -> String?

    /// What must be true before an intent asks its follow-up questions.
    enum Need {
        /// Signed in, with the database open.
        case signedIn
        /// On the clock, in a season: marking rows or trees.
        case marking
        /// A shift today to add a note to.
        case shiftNote
        /// An open shift whose start can change.
        case openShift
    }

    let model: AppModel
    var device: DeviceConditions
    var now: () -> Date = Date.init
    /// Siri resolves spoken times on the phone's own calendar.
    var phoneCalendar: Calendar = .current
    /// Runs after every change, so Siri's row and block suggestions follow the work.
    var onChange: @MainActor () -> Void = { TimeCardShortcuts.updateAppShortcutParameters() }

    init(model: AppModel, device: DeviceConditions) {
        self.model = model
        self.device = device
    }

    /// The running app's model, on this phone as it is right now.
    static func live() -> VoiceCommands {
        VoiceCommands(model: AppModel.shared, device: .current())
    }

    var actions: FieldActions { model.actions }

    // MARK: Ready?

    /// Nil when field actions can run; otherwise what to say instead. Opens the store and
    /// session first, since Siri may have just woken the app with no window.
    func blocker() async -> String? {
        if let problem = model.storageError {
            // Before the first unlock after a restart the database is sealed. Unlocked and
            // still failing is a real problem, so say what it is.
            return device.protectedDataAvailable ? problem : VoiceText.unlockOnce
        }
        await model.start()
        return actions.state() == nil ? FieldActions.signedOut : nil
    }

    /// What would stop a multi-step command, so Siri says it before asking any questions.
    func problem(before need: Need) async -> String? {
        if let blocked = await blocker() { return blocked }
        guard let state = actions.state() else { return FieldActions.signedOut }
        switch need {
        case .signedIn:
            return nil
        case .marking:
            // The same two things FieldEngine checks before any marking.
            if state.openShift == nil { return Speech.notClockedIn }
            if state.season == nil { return Speech.noSeason }
            return nil
        case .shiftNote:
            return dryRun(.addShiftNote("…"), state: state)
        case .openShift:
            return dryRun(.changeStart(state.openShift?.start ?? now()), state: state)
        }
    }

    /// The row you're on: the next open row from your work position.
    func currentRow() -> RowRef? {
        actions.state()?.nextRows(1).first
    }

    /// The farm's calendar, for times said out loud.
    var farmCalendar: FarmCalendar? {
        actions.state()?.calendar
    }

    // MARK: Clock

    func clockIn(field: UUID?) async -> VoiceReply {
        await run(.clockIn(fieldId: field))
    }

    /// Always asks first ("You’ve worked 7 hours 12 minutes today. Clock out?").
    func clockOut(confirm: Confirm) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        if let question = actions.confirmation(for: .clockOut) {
            guard await confirm(question) else { return .failed(VoiceText.stillClockedIn) }
        }
        return await run(.clockOut)
    }

    /// Lunch, or a break. With "Ask for a break reason" on, a break with no reason given asks
    /// what it's for, but only when the break can start.
    func takeBreak(_ kind: BreakKind, reason given: String?, askReason: Ask) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        var reason = given ?? ""
        if kind == .break, given == nil, VoicePreferences.load(from: model.session.store).askBreakReason,
           let state = actions.state(), dryRun(.startBreak(.break, reason: ""), state: state) == nil {
            reason = await askReason(VoiceText.whatsTheBreakFor) ?? ""
        }
        return await run(.startBreak(kind, reason: reason))
    }

    func backToWork() async -> VoiceReply {
        await run(.endBreak)
    }

    // MARK: Rows

    func nextRow() async -> VoiceReply {
        await run(.markNextRow)
    }

    /// Marks a whole row. A row far from where you are, or in another block, is checked
    /// first in case Siri misheard ("fourteen" and "forty").
    func markRow(_ row: RowRef, confirm: Confirm) async -> VoiceReply {
        if let stop = await problem(before: .marking) { return .failed(stop) }
        if let question = actions.confirmation(for: .markRow(row)) {
            guard await confirm(question) else { return .failed(VoiceText.nothingMarked) }
        }
        return await run(.markRow(row))
    }

    /// Trees `first` through `last` (counting from 1, either order) in one row.
    func markTrees(row: RowRef, first: Int, last: Int?) async -> VoiceReply {
        let a = first - 1, b = (last ?? first) - 1
        return await run(.markTrees(row, positions: min(a, b)...max(a, b)))
    }

    /// "I'm in block 3": `row` counts from 1; nil means the block's first open row.
    func moveTo(block: UUID, row: Int?) async -> VoiceReply {
        await run(.moveTo(blockId: block, row: row.map { $0 - 1 }))
    }

    func undo() async -> VoiceReply {
        await run(.undo)
    }

    // MARK: Notes and times

    func addNote(_ text: String) async -> VoiceReply {
        await run(.addShiftNote(text))
    }

    /// A note on tree `tree` (counting from 1) of a row.
    func noteTree(row: RowRef, tree: Int, body: String, flag: NoteFlag) async -> VoiceReply {
        await run(.addTreeNote(TreeRef(blockId: row.blockId, row: row.row, position: tree - 1), body: body, flag: flag))
    }

    /// "I started at 7:30": the latest 7:30 that has passed, on the farm's clock.
    func changeStart(to spoken: Date) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        guard let calendar = farmCalendar else { return .failed(FieldActions.signedOut) }
        let start = StartTime.resolve(spoken, now: now(), phoneCalendar: phoneCalendar, farm: calendar)
        return await run(.changeStart(start.roundedToMillisecond))
    }

    // MARK: Questions

    func status(_ topic: StatusTopic) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        let prefs = VoicePreferences.load(from: model.session.store)
        let at = now()
        let speech: String = switch topic {
        case .summary: actions.answer(.hours) + " " + actions.answer(.trees)
        case .hours: actions.answer(.hours)
        case .trees: actions.answer(.trees)
        case .whereAmI: actions.answer(.whereAmI)
        case .pace: actions.answer(.pace)
        case .pay: actions.answer(.pay(locked: device.isLocked, sayWhenLocked: prefs.sayPayWhenLocked))
        }
        let payAllowed = topic == .pay && (!device.isLocked || prefs.sayPayWhenLocked)
        let card = actions.state().map {
            DayCard.build(state: $0, now: at, topic: topic, showPay: payAllowed, payHidden: topic == .pay && !payAllowed)
        }
        return VoiceReply(speech: speech, succeeded: true, card: card)
    }

    // MARK: Plumbing

    private func run(_ command: FieldCommand) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        let reply = actions.perform(command)
        if reply.succeeded { onChange() }
        Self.log.info("\(Self.name(of: command), privacy: .public): \(reply.succeeded ? "done" : "refused", privacy: .public)")
        return VoiceReply(reply)
    }

    nonisolated static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "timecard", category: "voice")

    /// The command's name for the log, without what was said ("addShiftNote", "markRow").
    nonisolated static func name(of command: FieldCommand) -> String {
        Mirror(reflecting: command).children.first?.label ?? String(describing: command)
    }

    /// What the command would fail with right now, by TreeFarmKit's rules, saving nothing.
    private func dryRun(_ command: FieldCommand, state: FieldState) -> String? {
        var scratch = UndoStack<UndoEntry>()
        if case .failure(let failure) = FieldEngine.perform(command, state: state, undo: &scratch, now: now()) {
            return failure.speech
        }
        return nil
    }
}
