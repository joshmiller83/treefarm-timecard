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

    /// The model this command works on. A reference, so `blocker()` can swap in a freshly
    /// opened one when the database was still sealed when the app woke.
    private let current: Current
    var device: DeviceConditions
    var now: () -> Date = Date.init
    /// Siri resolves spoken times on the phone's own calendar.
    var phoneCalendar: Calendar = .current
    /// Runs after every change: Siri's row and block suggestions follow the work (once things
    /// settle), and the change goes to the server and the lock screen before iOS suspends the app.
    var onChange: @MainActor () -> Void
    /// Opens the database again for a model that couldn't open it, and returns the new model
    /// (which carries its own `storageError` if it still can't). Nil: nothing to retry with.
    var reopen: (@MainActor () -> AppModel)?

    init(model: AppModel, device: DeviceConditions, reopen: (@MainActor () -> AppModel)? = nil) {
        let current = Current(model)
        self.current = current
        self.device = device
        self.reopen = reopen
        self.onChange = {
            SiriSuggestions.shared.changed()
            IntentRunner.afterChange(current.model)
        }
    }

    /// The running app's model, on this phone as it is right now.
    static func live() -> VoiceCommands {
        let model = IntentRunner.model
        SiriSuggestions.shared.follow(model)
        return VoiceCommands(model: model, device: .current(), reopen: IntentRunner.reopenStorage)
    }

    var model: AppModel { current.model }
    var actions: FieldActions { model.actions }

    @MainActor
    private final class Current {
        var model: AppModel

        init(_ model: AppModel) {
            self.model = model
        }
    }

    // MARK: Ready?

    /// Nil when field actions can run; otherwise what to say instead. Opens the store and
    /// session first, since Siri may have just woken the app with no window.
    ///
    /// Before the first unlock after a restart the database file is sealed, so a process
    /// woken then (by Siri, or a Control Center button) has no data. Once the phone has been
    /// unlocked it opens the database again, so "Unlock your phone once, then try again" is
    /// true. Only when that fails on an unlocked phone is the real problem said.
    func blocker() async -> String? {
        if model.storageError != nil {
            guard device.protectedDataAvailable else { return VoiceText.unlockOnce }
            guard let reopen else { return model.storageError }
            let fresh = reopen()
            if let problem = fresh.storageError { return problem }
            current.model = fresh
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

    /// Nil when `row` is in its block; otherwise what Siri says ("Block 1 has rows 1 to 20."),
    /// as soon as the row is known, before asking anything else.
    func problem(row: RowRef) -> String? {
        guard let state = actions.state() else { return FieldActions.signedOut }
        guard let block = state.block(row.blockId) else { return Speech.blockGone }
        return block.contains(row) ? nil : Speech.rowsRange(block)
    }

    /// Nil when tree number `tree` (counting from 1) is in the row's block; otherwise
    /// "Block 1 has 12 trees in each row.", before the note or the next number is asked.
    func problem(tree: Int, in row: RowRef) -> String? {
        guard let state = actions.state() else { return FieldActions.signedOut }
        guard let block = state.block(row.blockId) else { return Speech.blockGone }
        return (1...max(1, block.treesPerRow)).contains(tree) ? nil : Speech.treesRange(block)
    }

    /// Asks before working on a row far from where you are, or in another block, in case Siri
    /// misheard ("forty" for "fourteen"). True: go ahead. Flows ask right after the row is said.
    func checked(_ row: RowRef, confirm: Confirm) async -> Bool {
        guard let question = actions.confirmation(for: .markRow(row)) else { return true }
        return await confirm(question)
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

    /// Trees `first` through `last` (counting from 1, either order) in one row. The row was
    /// said out loud, so one outside its block is refused and one far away or in another block
    /// is checked first, as for a row; then each tree number. `confirm` nil: already asked.
    func markTrees(row: RowRef, first: Int, last: Int?, confirm: Confirm?) async -> VoiceReply {
        if let stop = await problem(before: .marking) { return .failed(stop) }
        if let out = problem(row: row) { return .failed(out) }
        if let confirm, !(await checked(row, confirm: confirm)) { return .failed(VoiceText.nothingMarked) }
        for tree in [first, last ?? first] {
            if let out = problem(tree: tree, in: row) { return .failed(out) }
        }
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

    /// A note on tree `tree` (counting from 1) of a row. A row that was said out loud (rather
    /// than the one you're on) is checked first when it's far away or in another block.
    func noteTree(row: RowRef, tree: Int, body: String, flag: NoteFlag, confirm: Confirm? = nil) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        if let out = problem(row: row) { return .failed(out) }
        if let confirm, !(await checked(row, confirm: confirm)) { return .failed(VoiceText.nothingNoted) }
        if let out = problem(tree: tree, in: row) { return .failed(out) }
        return await run(.addTreeNote(TreeRef(blockId: row.blockId, row: row.row, position: tree - 1), body: body, flag: flag))
    }

    /// "I started at 7:30": the 7:30 nearest the shift's current start, on the farm's clock.
    func changeStart(to spoken: Date) async -> VoiceReply {
        if let blocked = await blocker() { return .failed(blocked) }
        guard let state = actions.state() else { return .failed(FieldActions.signedOut) }
        let start = StartTime.resolve(spoken, now: now(), near: state.openShift?.start, phoneCalendar: phoneCalendar, farm: state.calendar)
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
