import AppIntents
import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// The intents themselves (Siri's, the lock screen's and the multi-step flows), run through
/// `IntentRunner` against the demo farm. Serialized: they point the runner at their model,
/// and point it back at the running app after each test.
@MainActor
@Suite("Intents", .serialized, .restoresIntentRunner)
final class IntentShellTests {
    let model: AppModel
    var published: [LiveSnapshot?] = []

    init() async {
        model = await Demo.model()
        let model = model
        IntentRunner.makeVoice = { Demo.voice(model) }
        model.actions.onLiveSnapshot = { [weak self] in self?.published.append($0) }
    }

    // MARK: After a change

    /// A lock-screen press sends its change right away instead of waiting out the pause a
    /// tap in the app gets, so it reaches the server before iOS suspends the app.
    @Test func aChangeFromTheLockScreenSyncsAtOnce() async throws {
        #expect(model.actions.perform(.clockIn(fieldId: nil)).succeeded)
        #expect(try model.session.store.pendingCount() > 0)
        IntentRunner.afterChange(model)
        let deadline = Date().addingTimeInterval(1)
        while try model.session.store.pendingCount() > 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try model.session.store.pendingCount() == 0, "still waiting for the 1.5 s pause")
    }

    // MARK: Controls

    @Test func aRefusedControlPressSaysWhyWhenNothingElseCan() async throws {
        var posted: [String] = []
        IntentRunner.postQuietNotice = { posted.append($0) }
        defer { IntentRunner.postQuietNotice = { QuietNotice.post($0) } }
        let reply = await IntentRunner.controlPress(.markNextRow)
        #expect(!reply.succeeded)
        #expect(posted == [reply.speech])
        #expect(reply.speech == Speech.notClockedIn)

        let ok = await IntentRunner.controlPress(.clockIn(fieldId: nil))
        #expect(ok.succeeded)
        #expect(posted.count == 1)
    }

    // MARK: Lock-screen buttons

    @Test func theLockScreenButtonsRunTheFieldActions() async throws {
        _ = try await ClockInButtonIntent().perform()
        #expect(Demo.openShift(model) != nil)

        _ = try await NextRowButtonIntent().perform()
        #expect(Demo.marks(model, row: try Demo.row(model, 5)) == 12)

        let row7 = try Demo.row(model, 7)
        _ = try await MarkRowIntent(blockId: row7.blockId, row: row7.row).perform()
        #expect(Demo.marks(model, row: row7) == 12)

        _ = try await UndoButtonIntent().perform()
        #expect(Demo.marks(model, row: row7) == 0)

        _ = try await StartBreakButtonIntent().perform()
        #expect(Demo.openShift(model)?.openBreak?.kind == .break)
        #expect(published.last??.phase == .onBreak)

        _ = try await BackToWorkButtonIntent().perform()
        #expect(Demo.openShift(model)?.openBreak == nil)
        #expect(published.last??.phase == .working)
    }

    @Test func aRefusedPressSaysWhyOnTheLockScreen() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let row1 = try Demo.row(model, 1)
        published.removeAll()
        _ = try await MarkRowIntent(blockId: row1.blockId, row: row1.row).perform()
        let snapshot = try #require(published.last ?? nil)
        #expect(snapshot.lastAction?.hasPrefix("Row 1 was shaped by Sam Ortiz on ") == true)
        #expect(snapshot.lastAction?.hasSuffix(".") == true)
        #expect(snapshot.lastAction?.contains("Next open row") == false, "only the first sentence fits")
        #expect(snapshot.nextRows.first?.title == "Row 5")
    }

    /// Undo beside a refusal would take back the action before it, not the refused one.
    @Test func aRefusalOffersNoUndo() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        _ = await IntentRunner.press(.markNextRow)
        #expect((published.last ?? nil)?.canUndo == true)
        let row1 = try Demo.row(model, 1)
        _ = try await MarkRowIntent(blockId: row1.blockId, row: row1.row).perform()
        let snapshot = try #require(published.last ?? nil)
        #expect(snapshot.lastAction?.hasPrefix("Row 1 was shaped by") == true)
        #expect(snapshot.canUndo == false)
    }

    /// Clocked out on another phone, synced, and the lock screen still shows a running card:
    /// a press takes it down rather than doing nothing while the timer runs on.
    @Test func aPressAfterClockingOutElsewhereEndsTheCard() async throws {
        #expect(Demo.openShift(model) == nil)
        published.removeAll()
        let reply = await IntentRunner.press(.markNextRow)
        #expect(reply.speech == Speech.notClockedIn)
        #expect(published.count == 1)
        #expect(published.last == .some(nil), "nil ends the activity")
    }

    @Test func aButtonForABlockThatIsGoneChangesNothing() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        published.removeAll()
        _ = try await MarkRowIntent(blockId: UUID(), row: 3).perform()
        #expect(model.snapshot.marks.count == 48, "only Sam's four rows")
        #expect((published.last ?? nil)?.lastAction == Speech.blockGone)
    }

    @Test func lockScreenNotesAreOneSentence() {
        #expect(IntentRunner.lockScreenNote("Row 14 was shaped by Sam on Oct 16. Next open row is 15.") == "Row 14 was shaped by Sam on Oct 16.")
        #expect(IntentRunner.lockScreenNote(Speech.notClockedIn) == "You’re not clocked in.")
        #expect(IntentRunner.lockScreenNote("You’re already on lunch since 12:01. Say \"back to work.\" when done.") == "You’re already on lunch since 12:01.")
        #expect(IntentRunner.lockScreenNote("Block 1 has rows 1 to 20.") == "Block 1 has rows 1 to 20.")
        #expect(IntentRunner.lockScreenNote("No period") == "No period")
    }

    // MARK: Siri intents

    /// iOS lets a background app start a Live Activity only inside a LiveActivityIntent, and
    /// Siri runs these in the background: "Clock in with Time Card" must put the timer up.
    @Test func everyCommandThatChangesTheDayCanStartTheLockScreenTimer() {
        let changing: [any AppIntent] = [
            ClockInIntent(), ClockOutIntent(), TakeBreakIntent(), BackToWorkIntent(), NextRowIntent(), MarkRowByNumberIntent(),
            MarkTreesIntent(), MoveToBlockIntent(), UndoIntent(), AddShiftNoteIntent(), NoteTreeIntent(), FixStartTimeIntent(),
            FieldTaskIntent(),
        ]
        for intent in changing {
            #expect((intent as Any) is any LiveActivityIntent, "\(type(of: intent))")
        }
        let buttons: [any AppIntent] = [MarkRowIntent(), StartBreakButtonIntent(), BackToWorkButtonIntent(), UndoButtonIntent(),
                                        NextRowButtonIntent(), ClockInButtonIntent()]
        for intent in buttons {
            #expect((intent as Any) is any LiveActivityIntent, "\(type(of: intent))")
        }
        // Asking a question changes nothing on the lock screen.
        #expect(!((AskTimeCardIntent() as Any) is any LiveActivityIntent))
    }

    @Test func siriIntentsRunAgainstTheSameModel() async throws {
        _ = try await ClockInIntent().perform()
        let open = try #require(Demo.openShift(model))
        _ = try await NextRowIntent().perform()
        #expect(Demo.marks(model, row: try Demo.row(model, 5)) == 12)
        _ = try await TakeBreakIntent(kind: .lunch).perform()
        #expect(Demo.openShift(model)?.openBreak?.kind == .lunch)
        _ = try await BackToWorkIntent().perform()
        #expect(Demo.openShift(model)?.openBreak == nil)
        _ = try await UndoIntent().perform()
        #expect(Demo.openShift(model)?.breaks.last?.end == nil, "undo reopens lunch")
        _ = try await BackToWorkIntent().perform()

        let block3 = try #require(VoiceCatalog.blocks(try Demo.state(model)).first { $0.title == "Block 3" })
        _ = try await MoveToBlockIntent(block: block3).perform()
        let here = try #require(VoiceCatalog.suggestedRows(try Demo.state(model)).first)
        #expect(here.blockName == "Block 3" && here.title == "Row 1")
        _ = try await MarkRowByNumberIntent(row: here).perform()
        #expect(Demo.marks(model, row: here.rowRef) == 12)

        let reply = await IntentRunner.voice { await $0.status(.trees) }
        #expect(reply.speech.hasPrefix("24 trees today"))
        _ = try await AskTimeCardIntent(topic: .whereAmI).perform()
        #expect(Demo.openShift(model)?.id == open.id)
    }

    @Test func entityQueriesReadTheFarm() async throws {
        let rows = try await RowQuery().suggestedEntities()
        #expect(rows.count == 10)
        #expect(try await RowQuery().entities(matching: "row twelve").first?.title == "Row 12")
        #expect(try await RowQuery().entities(for: [rows[3].id]) == [rows[3]])
        #expect(try await BlockQuery().entities(matching: "block four").first?.title == "Block 4")
        #expect(try await FieldQuery().suggestedEntities().map(\.title) == ["North Field", "Creek Field"])
        #expect(try await FieldQuery().entities(matching: "creek").first?.title == "Creek Field")
    }

    // MARK: Multi-step flows

    @Test func flowsCheckBeforeAskingAnything() async throws {
        let asked = Asked()
        let markRow = try await SiriFlows.markRow(nil, askRow: asked.row("row"), confirm: { _ in true })
        let markTrees = try await SiriFlows.markTrees(row: nil, first: nil, last: nil,
                                                      askRow: asked.row("row"), askFirst: asked.int("first", 1), askLast: asked.int("last", 2),
                                                      confirm: asked.yes("confirm"))
        let note = try await SiriFlows.addNote(nil, askText: asked.text("note", "Fuel"))
        let start = try await SiriFlows.fixStart(nil, askTime: asked.time("time"))
        for reply in [markRow, markTrees, note, start] {
            #expect(reply.speech == Speech.notClockedIn)
        }
        #expect(asked.questions.isEmpty, "nothing is asked when the answer would be “not clocked in”")
    }

    @Test func markingTreesAsksRowThenFirstThenLast() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let asked = Asked(row: try #require(VoiceCatalog.suggestedRows(try Demo.state(model)).first))
        let reply = try await SiriFlows.markTrees(row: nil, first: nil, last: nil,
                                                  askRow: asked.row("row"), askFirst: asked.int("first", 1), askLast: asked.int("last", 6),
                                                  confirm: asked.yes("confirm"))
        #expect(asked.questions == ["row", "first", "last"], "row 5 is where you are: nothing to check")
        #expect(reply.speech == "Marked trees 1 to 6 in row 5.")
    }

    @Test func aFarRowForTreesIsCheckedRightAfterTheRow() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let state = try Demo.state(model)
        let far = try #require(VoiceCatalog.rows(matching: "row 18", state: state).first)
        let asked = Asked(row: far, confirms: false)
        let reply = try await SiriFlows.markTrees(row: nil, first: nil, last: nil,
                                                  askRow: asked.row("row"), askFirst: asked.int("first", 1), askLast: asked.int("last", 6),
                                                  confirm: asked.yes("confirm"))
        #expect(asked.questions == ["row", "confirm: Row 18 in block 1? That’s 13 rows ahead."])
        #expect(reply.speech == "Okay, nothing marked.")
    }

    @Test func aRowOutsideTheBlockForTreesIsSaidBeforeTheTrees() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let state = try Demo.state(model)
        let outside = try #require(VoiceCatalog.rows(matching: "row 40", state: state).first)
        let asked = Asked(row: outside, confirms: true)
        let reply = try await SiriFlows.markTrees(row: nil, first: nil, last: nil,
                                                  askRow: asked.row("row"), askFirst: asked.int("first", 1), askLast: asked.int("last", 6),
                                                  confirm: asked.yes("confirm"))
        #expect(asked.questions == ["row"])
        #expect(reply.speech == "Block 1 has rows 1 to 20.")
    }

    @Test func aTreePastTheEndIsSaidBeforeTheNote() async throws {
        let asked = Asked()
        let reply = try await SiriFlows.noteTree(row: nil, tree: nil, note: nil, flag: nil,
                                                 askRow: asked.row("row"), askTree: asked.int("tree", 13),
                                                 askNote: asked.text("note", "Leader broken"), askFlag: asked.flag("flag", .replant),
                                                 confirm: asked.yes("confirm"))
        #expect(asked.questions == ["tree"], "the note isn't dictated for nothing")
        #expect(reply.speech == "Block 1 has 12 trees in each row.")
        #expect(model.snapshot.notes.isEmpty)
    }

    @Test func aFirstTreePastTheEndIsSaidBeforeTheLast() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let asked = Asked()
        let row = try #require(VoiceCatalog.rows(matching: "row 5", state: try Demo.state(model)).first)
        let reply = try await SiriFlows.markTrees(row: row, first: nil, last: nil,
                                                  askRow: asked.row("row"), askFirst: asked.int("first", 30), askLast: asked.int("last", 31),
                                                  confirm: asked.yes("confirm"))
        #expect(asked.questions == ["first"])
        #expect(reply.speech == "Block 1 has 12 trees in each row.")
    }

    @Test func aTreeNoteNeedsOnlyTheTreeNumberTheNoteAndAFlag() async throws {
        let asked = Asked()
        let reply = try await SiriFlows.noteTree(row: nil, tree: nil, note: nil, flag: nil,
                                                 askRow: asked.row("row"), askTree: asked.int("tree", 6),
                                                 askNote: asked.text("note", "Leader broken"), askFlag: asked.flag("flag", .replant),
                                                 confirm: asked.yes("confirm"))
        #expect(asked.questions == ["tree", "note", "flag"], "the row is the one you're on")
        #expect(reply.speech == "Noted on block 1, row 5, tree 6.")
        #expect(model.snapshot.notes.values.first?.flag == .replant)
    }

    @Test func aTreeNoteInARowFarAwayIsChecked() async throws {
        let state = try Demo.state(model)
        let far = try #require(VoiceCatalog.rows(matching: "row 3 in block 2", state: state).first)
        let asked = Asked(confirms: true)
        let reply = try await SiriFlows.noteTree(row: far, tree: 2, note: "Dead", flag: .dead,
                                                 askRow: asked.row("row"), askTree: asked.int("tree", 6),
                                                 askNote: asked.text("note", "x"), askFlag: asked.flag("flag", .noFlag),
                                                 confirm: asked.yes("confirm"))
        #expect(asked.questions == ["confirm: Row 3 in block 2? You’re in block 1."])
        #expect(reply.speech == "Noted on block 2, row 3, tree 2.")
    }

    @Test func whatWasAlreadySaidIsNotAskedAgain() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let asked = Asked()
        let note = try await SiriFlows.addNote("Fuel low", askText: asked.text("note", "x"))
        #expect(note.speech == "Added to today’s notes.")
        let blank = try await SiriFlows.addNote("  ", askText: asked.text("note", "Chain oiled"))
        #expect(blank.speech == "Added to today’s notes.")
        #expect(asked.questions == ["note"])
        #expect(Demo.openShift(model)?.notes == "Fuel low\nChain oiled")
    }

    @Test func movingWithoutABlockAsksWhichBlock() async throws {
        let block2 = try #require(VoiceCatalog.blocks(try Demo.state(model)).first { $0.title == "Block 2" })
        let asked = Asked(block: block2)
        let reply = try await SiriFlows.moveTo(nil, row: 4, askBlock: asked.block("block"))
        #expect(asked.questions == ["block"])
        #expect(reply.speech == "Okay, block 2, row 4 is next.")
    }

    @Test func fixingTheStartAsksTheTime() async throws {
        _ = await IntentRunner.perform(.clockIn(fieldId: nil))
        let asked = Asked(time: Date().addingTimeInterval(-45 * 60))
        let reply = try await SiriFlows.fixStart(nil, askTime: asked.time("time"))
        #expect(asked.questions == ["time"])
        #expect(reply.succeeded)
        #expect(reply.speech.hasPrefix("Start time changed to "))
    }

    @Test func signedOutAsksNothing() async throws {
        let signedOut = await Demo.model(signedIn: false)
        IntentRunner.makeVoice = { Demo.voice(signedOut) }
        let asked = Asked()
        let note = try await SiriFlows.noteTree(row: nil, tree: nil, note: nil, flag: nil,
                                                askRow: asked.row("row"), askTree: asked.int("tree", 1),
                                                askNote: asked.text("note", "x"), askFlag: asked.flag("flag", .noFlag),
                                                confirm: asked.yes("confirm"))
        let move = try await SiriFlows.moveTo(nil, row: nil, askBlock: asked.block("block"))
        #expect(note.speech == "Open Time Card to sign in.")
        #expect(move.speech == "Open Time Card to sign in.")
        #expect(asked.questions.isEmpty)
        #expect(try await RowQuery().suggestedEntities().isEmpty)
    }

    // MARK: Donations

    @Test func theAppsOwnButtonsTeachSiri() async throws {
        let state = try Demo.state(model)
        let north = try Demo.field(model, "North Field")
        #expect((IntentDonations.intent(for: .clockIn(fieldId: nil), state: state) as? ClockInIntent)?.field == nil)
        #expect((IntentDonations.intent(for: .clockIn(fieldId: north.id), state: state) as? ClockInIntent)?.field?.title == "North Field")
        #expect(IntentDonations.intent(for: .clockOut, state: state) is ClockOutIntent)
        #expect((IntentDonations.intent(for: .startBreak(.lunch, reason: ""), state: state) as? TakeBreakIntent)?.kind == .lunch)
        #expect(IntentDonations.intent(for: .endBreak, state: state) is BackToWorkIntent)
        #expect(IntentDonations.intent(for: .markNextRow, state: state) is NextRowIntent)
        #expect(IntentDonations.intent(for: .markRow(try Demo.row(model, 9)), state: state) is NextRowIntent)
        let block2 = try Demo.block(model, "2")
        #expect((IntentDonations.intent(for: .moveTo(blockId: block2.id, row: nil), state: state) as? MoveToBlockIntent)?.block?.title == "Block 2")
        #expect(IntentDonations.intent(for: .undo, state: state) == nil)
        #expect(IntentDonations.intent(for: .addShiftNote("x"), state: state) == nil)
    }

    @Test func aButtonInTheAppDonatesWhatItDid() async throws {
        let sent = Tally()
        IntentDonations.donor = { sent.intents.append($0) }
        defer { IntentDonations.donor = { IntentDonationManager.shared.donate(intent: $0) } }

        let reply = model.performInApp(.clockIn(fieldId: nil))
        #expect(reply.succeeded)
        #expect(Demo.openShift(model) != nil)
        #expect(sent.intents.count == 1)
        #expect(sent.intents.first is ClockInIntent)

        // Undo and notes aren't worth suggesting; a refused tap did nothing to suggest.
        model.performInApp(.addShiftNote("Fuel low"))
        model.performInApp(.undo)
        model.performInApp(.clockIn(fieldId: nil))
        #expect(sent.intents.count == 1)

        model.performInApp(.markNextRow)
        #expect(sent.intents.count == 2)
        #expect(sent.intents.last is NextRowIntent)
    }

    /// iOS logs Siri's own runs; donating them too would count them twice.
    @Test func siriAndTheLockScreenDonateNothing() async throws {
        let sent = Tally()
        IntentDonations.donor = { sent.intents.append($0) }
        defer { IntentDonations.donor = { IntentDonationManager.shared.donate(intent: $0) } }
        _ = try await ClockInIntent().perform()
        _ = try await NextRowButtonIntent().perform()
        await IntentRunner.voice { _ in
            IntentDonations.performed(.markNextRow, reply: FieldReply(speech: "", succeeded: true), state: nil)
        }
        #expect(Demo.marks(model, row: try Demo.row(model, 5)) == 12)
        #expect(sent.intents.isEmpty)
    }
}

/// Answers a flow's questions with set values, and remembers which were asked, in order.
final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var _questions: [String] = []
    let rowAnswer: RowEntity?
    let blockAnswer: BlockEntity?
    let timeAnswer: Date
    let confirms: Bool

    init(row: RowEntity? = nil, block: BlockEntity? = nil, time: Date = Date(), confirms: Bool = true) {
        rowAnswer = row
        blockAnswer = block
        timeAnswer = time
        self.confirms = confirms
    }

    var questions: [String] { lock.withLock { _questions } }

    private func note(_ q: String) { lock.withLock { _questions.append(q) } }

    struct NoAnswer: Error {}

    func row(_ q: String) -> SiriFlows.Asker<RowEntity> {
        { self.note(q); guard let r = self.rowAnswer else { throw NoAnswer() }; return r }
    }

    func block(_ q: String) -> SiriFlows.Asker<BlockEntity> {
        { self.note(q); guard let b = self.blockAnswer else { throw NoAnswer() }; return b }
    }

    func int(_ q: String, _ value: Int) -> SiriFlows.Asker<Int> {
        { self.note(q); return value }
    }

    func text(_ q: String, _ value: String) -> SiriFlows.Asker<String> {
        { self.note(q); return value }
    }

    func flag(_ q: String, _ value: FlagOption) -> SiriFlows.Asker<FlagOption> {
        { self.note(q); return value }
    }

    func time(_ q: String) -> SiriFlows.Asker<Date> {
        { self.note(q); return self.timeAnswer }
    }

    /// A yes-or-no question, noted with what was asked: "confirm: Row 18 in block 1? …"
    func yes(_ q: String) -> VoiceCommands.Confirm {
        { question in self.note("\(q): \(question)"); return self.confirms }
    }
}
