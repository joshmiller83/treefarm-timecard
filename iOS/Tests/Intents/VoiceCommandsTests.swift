import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// Every Siri command's logic, run against the demo farm the way an intent runs it:
/// what changed, what Siri says, and each way it can fail.
@MainActor
@Suite("Voice commands")
struct VoiceCommandsTests {
    // MARK: Getting ready

    @Test func signedOutAsksToOpenTheApp() async throws {
        let model = await Demo.model(signedIn: false)
        let voice = Demo.voice(model)
        let asked = Answerer(true)
        #expect(await voice.clockIn(field: nil).speech == "Open Time Card to sign in.")
        #expect(await voice.status(.hours).speech == "Open Time Card to sign in.")
        let reply = await voice.markRow(RowRef(blockId: UUID(), row: 3), confirm: asked.confirm)
        #expect(reply.speech == "Open Time Card to sign in.")
        #expect(!reply.succeeded)
        #expect(asked.questions.isEmpty)
        #expect(await voice.problem(before: .shiftNote) == "Open Time Card to sign in.")
    }

    @Test func beforeTheFirstUnlockSiriAsksForOne() async {
        let session = TimeCardSession(store: try! LocalStore.inMemory(), api: StubAPIClient(), tokens: InMemoryTokenStore(), deviceName: "t")
        let model = AppModel(session: session, mode: .live, storageError: "Time Card couldn’t open its data.")
        // Locked since the restart: the database file is still sealed.
        let locked = Demo.voice(model, locked: true)
        #expect(await locked.clockIn(field: nil).speech == "Unlock your phone once, then try again.")
        #expect(await locked.status(.trees).speech == "Unlock your phone once, then try again.")
        // Unlocked and still broken: say what really went wrong.
        let unlocked = Demo.voice(model, locked: false)
        #expect(await unlocked.nextRow().speech == "Time Card couldn’t open its data.")
    }

    // MARK: Clock in and out

    @Test func clockingInSaysTheTimeAndWhereToStart() async throws {
        let model = await Demo.model()
        var changes = 0
        var voice = Demo.voice(model)
        voice.onChange = { changes += 1 }
        let reply = await voice.clockIn(field: nil)
        let open = try #require(Demo.openShift(model))
        #expect(reply.succeeded)
        #expect(reply.speech == "Clocked in at \(Demo.spoken(open.start, model)). You’re on block 1, row 5.")
        #expect(try model.session.store.pendingCount() >= 1)
        #expect(changes == 1, "row suggestions for Siri refresh after a change")

        let again = await voice.clockIn(field: nil)
        #expect(!again.succeeded)
        #expect(again.speech == "You’re already clocked in since \(Demo.spoken(open.start, model)).")
        #expect(changes == 1)
    }

    @Test func clockingInAtAnotherField() async throws {
        let model = await Demo.model()
        let creek = try Demo.field(model, "Creek Field")
        let reply = await Demo.voice(model).clockIn(field: creek.id)
        #expect(reply.speech.hasSuffix(" You’re on block 1, row 1."))
        #expect(try Demo.state(model).currentField?.id == creek.id)
    }

    @Test func clockingOutAsksFirst() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        _ = await voice.nextRow()

        let no = Answerer(false)
        let kept = await voice.clockOut(confirm: no.confirm)
        #expect(no.questions == ["You’ve worked less than a minute today. Clock out?"])
        #expect(kept.speech == "Okay, you’re still clocked in.")
        #expect(!kept.succeeded)
        let open = try #require(Demo.openShift(model))

        let yes = Answerer(true)
        let out = await voice.clockOut(confirm: yes.confirm)
        #expect(yes.questions.count == 1)
        #expect(out.succeeded)
        let closed = try #require(model.snapshot.shifts[open.id])
        #expect(out.speech == "Clocked out at \(Demo.spoken(closed.end, model)). less than a minute, 12 trees.")
        #expect(Demo.openShift(model) == nil)
    }

    @Test func clockingOutWhenNotClockedInDoesNotAsk() async throws {
        let model = await Demo.model()
        let asked = Answerer(true)
        let reply = await Demo.voice(model).clockOut(confirm: asked.confirm)
        #expect(asked.questions.isEmpty)
        #expect(reply.speech == Speech.notClockedIn)
    }

    // MARK: Breaks

    @Test func lunchAndBackToWork() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        #expect(await voice.takeBreak(.lunch, reason: nil, askReason: Speaker("x").ask).speech == Speech.notClockedIn)
        _ = await voice.clockIn(field: nil)

        let lunch = await voice.takeBreak(.lunch, reason: nil, askReason: Speaker("x").ask)
        let started = try #require(Demo.openShift(model)?.openBreak)
        #expect(lunch.speech == "Lunch started at \(Demo.spoken(started.start, model)).")
        #expect(started.kind == .lunch)

        let twice = await voice.takeBreak(.lunch, reason: nil, askReason: Speaker("x").ask)
        #expect(twice.speech == "You’re already on lunch since \(Demo.spoken(started.start, model)). Say \"back to work\" when you’re done.")

        let back = await voice.backToWork()
        let ended = try #require(Demo.openShift(model)?.breaks.last?.end)
        #expect(back.speech == "Back at \(Demo.spoken(ended, model)). Lunch was less than a minute.")
        #expect(await voice.backToWork().speech == "You’re not on a break.")
    }

    @Test func theBreakReasonIsAskedOnlyWhenTurnedOn() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)

        let quiet = Speaker("water")
        let first = await voice.takeBreak(.break, reason: nil, askReason: quiet.ask)
        #expect(quiet.questions.isEmpty)
        #expect(first.speech.hasPrefix("Break started at "))
        _ = await voice.backToWork()

        try VoicePreferences(askBreakReason: true).save(to: model.session.store)
        let asks = Speaker("water")
        let second = await voice.takeBreak(.break, reason: nil, askReason: asks.ask)
        #expect(asks.questions == ["What’s the break for?"])
        #expect(second.speech.hasPrefix("Break for water started at "))
        #expect(Demo.openShift(model)?.openBreak?.reason == "water")
        _ = await voice.backToWork()

        // Lunch never needs a reason, and a reason already given isn't asked again.
        let lunch = Speaker("x")
        _ = await voice.takeBreak(.lunch, reason: nil, askReason: lunch.ask)
        #expect(lunch.questions.isEmpty)
        _ = await voice.backToWork()
        let given = Speaker("x")
        #expect(await voice.takeBreak(.break, reason: "fuel", askReason: given.ask).speech.hasPrefix("Break for fuel started at "))
        #expect(given.questions.isEmpty)
    }

    @Test func noReasonIsAskedWhenTheBreakCanNotStart() async throws {
        let model = await Demo.model()
        try VoicePreferences(askBreakReason: true).save(to: model.session.store)
        let asks = Speaker("water")
        let reply = await Demo.voice(model).takeBreak(.break, reason: nil, askReason: asks.ask)
        #expect(asks.questions.isEmpty)
        #expect(reply.speech == Speech.notClockedIn)
    }

    // MARK: Rows

    @Test func nextRowMarksTheRowAndMovesOn() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        #expect(await voice.nextRow().speech == Speech.notClockedIn)
        _ = await voice.clockIn(field: nil)
        let reply = await voice.nextRow()
        #expect(reply.speech == "Row 5 marked, 12 trees. Next is row 6.")
        #expect(Demo.marks(model, row: try Demo.row(model, 5)) == 12)
        #expect(await voice.nextRow().speech == "Row 6 marked, 12 trees. Next is row 7.")
    }

    @Test func aNearRowIsMarkedRightAway() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        let asked = Answerer(false)
        let reply = await voice.markRow(try Demo.row(model, 7), confirm: asked.confirm)
        #expect(asked.questions.isEmpty)
        #expect(reply.speech == "Row 7 marked, 12 trees. Next is row 8.")
    }

    @Test func aFarRowIsCheckedInCaseSiriMisheard() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        let row20 = try Demo.row(model, 20)

        let no = Answerer(false)
        let declined = await voice.markRow(row20, confirm: no.confirm)
        #expect(no.questions == ["Row 20 in block 1? That’s 15 rows ahead."])
        #expect(declined.speech == "Okay, nothing marked.")
        #expect(Demo.marks(model, row: row20) == 0)

        let otherBlock = Answerer(false)
        _ = await voice.markRow(try Demo.row(model, 1, block: "2"), confirm: otherBlock.confirm)
        #expect(otherBlock.questions == ["Row 1 in block 2? You’re in block 1."])

        let yes = Answerer(true)
        let marked = await voice.markRow(row20, confirm: yes.confirm)
        #expect(marked.speech == "Row 20 marked, 12 trees. Next is block 2, row 1.")
        #expect(Demo.marks(model, row: row20) == 12)
    }

    @Test func aRowSomeoneElseShapedSaysWho() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        let row1 = try Demo.row(model, 1)
        let samsMark = try #require(model.snapshot.marks.values.first { $0.blockId == row1.blockId && $0.row == 0 })
        let day = Fmt.monthDay(samsMark.markedAt, FarmCalendar(farm: try #require(model.session.farm)))
        let reply = await voice.markRow(row1, confirm: Answerer(true).confirm)
        #expect(!reply.succeeded)
        #expect(reply.speech == "Row 1 was shaped by Sam Ortiz on \(day). Next open row is 5.")
    }

    @Test func aRowPastTheEndOfTheBlockSaysTheRange() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        let asked = Answerer(true)
        let reply = await voice.markRow(try Demo.row(model, 40), confirm: asked.confirm)
        #expect(asked.questions.isEmpty)
        #expect(reply.speech == "Block 1 has rows 1 to 20.")
    }

    @Test func markingARowWhenNotClockedInAsksNothing() async throws {
        let model = await Demo.model()
        let asked = Answerer(true)
        let reply = await Demo.voice(model).markRow(try Demo.row(model, 20), confirm: asked.confirm)
        #expect(asked.questions.isEmpty)
        #expect(reply.speech == Speech.notClockedIn)
        #expect(await Demo.voice(model).problem(before: .marking) == Speech.notClockedIn)
    }

    @Test func markingSomeTreesInARow() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        let row5 = try Demo.row(model, 5)
        #expect(await voice.markTrees(row: row5, first: 1, last: 6).speech == Speech.notClockedIn)
        _ = await voice.clockIn(field: nil)
        #expect(await voice.problem(before: .marking) == nil)
        #expect(await voice.markTrees(row: row5, first: 6, last: 1).speech == "Marked trees 1 to 6 in row 5.")
        #expect(Demo.marks(model, row: row5) == 6)
        #expect(await voice.markTrees(row: row5, first: 8, last: nil).speech == "Marked tree 8 in row 5.")
        #expect(await voice.markTrees(row: row5, first: 3, last: 4).speech == "Those trees were already shaped.")
        #expect(await voice.markTrees(row: row5, first: 13, last: nil).speech == "Block 1 has 12 trees in each row.")
    }

    // MARK: Moving, undoing

    @Test func movingToABlock() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        let block2 = try Demo.block(model, "2")
        #expect(await voice.moveTo(block: block2.id, row: nil).speech == "Okay, block 2, row 1 is next.")
        #expect(try Demo.state(model).nextRows(1).first == RowRef(blockId: block2.id, row: 0))
        #expect(await voice.moveTo(block: block2.id, row: 3).speech == "Okay, block 2, row 3 is next.")
        #expect(await voice.moveTo(block: block2.id, row: 30).speech == "Block 2 has rows 1 to 20.")
        #expect(await voice.moveTo(block: UUID(), row: nil).speech == Speech.blockGone)
        #expect(await voice.undo().speech == "Undid the move.")
    }

    @Test func undoTakesBackTheLastThing() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        #expect(await voice.undo().speech == Speech.nothingToUndo)
        _ = await voice.clockIn(field: nil)
        _ = await voice.nextRow()
        let reply = await voice.undo()
        #expect(reply.succeeded)
        #expect(reply.speech == "Undid row 5.")
        #expect(Demo.marks(model, row: try Demo.row(model, 5)) == 0)
    }

    // MARK: Notes

    @Test func aNoteForToday() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        #expect(await voice.problem(before: .shiftNote) == Speech.notClockedIn)
        #expect(await voice.addNote("Fuel low on the shears").speech == Speech.notClockedIn)
        _ = await voice.clockIn(field: nil)
        #expect(await voice.problem(before: .shiftNote) == nil)
        #expect(await voice.addNote("Fuel low on the shears").speech == "Added to today’s notes.")
        #expect(Demo.openShift(model)?.notes == "Fuel low on the shears")
        #expect(await voice.addNote("   ").speech == Speech.emptyNote)
    }

    @Test func aNoteOnATreeInTheCurrentRow() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        let here = try #require(voice.currentRow())
        #expect(here == (try Demo.row(model, 5)))
        let reply = await voice.noteTree(row: here, tree: 6, body: "Leader broken", flag: .attention)
        #expect(reply.speech == "Noted on block 1, row 5, tree 6.")
        let note = try #require(model.snapshot.notes.values.first)
        #expect(note.body == "Leader broken")
        #expect(note.flag == .attention)
        #expect(note.tree == TreeRef(blockId: here.blockId, row: 4, position: 5))
        #expect(await voice.noteTree(row: here, tree: 20, body: "x", flag: .none).speech == "Block 1 has 12 trees in each row.")
    }

    // MARK: Start time

    @Test func fixingTheStartTime() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        #expect(await voice.problem(before: .openShift) == Speech.notClockedIn)
        #expect(await voice.changeStart(to: Date().addingTimeInterval(-3600)).speech == Speech.notClockedIn)
        _ = await voice.clockIn(field: nil)
        #expect(await voice.problem(before: .openShift) == nil)

        let reply = await voice.changeStart(to: Date().addingTimeInterval(-3600))
        let open = try #require(Demo.openShift(model))
        #expect(reply.succeeded)
        #expect(reply.speech == "Start time changed to \(Demo.spoken(open.start, model)).")
        #expect(abs(open.start.timeIntervalSinceNow + 3600) < 120)
    }

    // MARK: Status

    @Test func statusAnswersComeFromTheFieldAnswers() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        // An hour on the clock, so the pace doesn't change between two answers.
        _ = await voice.changeStart(to: Date().addingTimeInterval(-60 * 60))
        _ = await voice.nextRow()
        for (topic, question) in [(StatusTopic.hours, FieldQuestion.hours), (.trees, .trees), (.whereAmI, .whereAmI), (.pace, .pace)] {
            let reply = await voice.status(topic)
            #expect(reply.speech == model.actions.answer(question), "\(topic)")
            #expect(reply.card?.topic == topic)
        }
        let summary = await voice.status(.summary)
        #expect(summary.speech == model.actions.answer(.hours) + " " + model.actions.answer(.trees))
        #expect(await voice.status(.whereAmI).speech == "You’re on block 1, row 6. Next are rows 7 and 8.")
    }

    @Test func payIsQuietOnALockedPhoneUnlessAllowed() async throws {
        let model = await Demo.model()
        let voice = Demo.voice(model)
        _ = await voice.clockIn(field: nil)
        _ = await voice.changeStart(to: Date().addingTimeInterval(-90 * 60))

        let unlocked = await voice.status(.pay)
        #expect(unlocked.speech.hasPrefix("$"))
        let pay = try #require(unlocked.card?.pay)
        #expect(pay.todayCents > 2900, "about an hour and a half at $20")
        // The card's numbers and what Siri said are the same.
        #expect(unlocked.speech == "\(Fmt.usd(cents: pay.todayCents)) today, \(Fmt.usd(cents: pay.weekCents)) this week.")

        let locked = await Demo.voice(model, locked: true).status(.pay)
        #expect(locked.speech == "Unlock your phone to hear your pay.")
        #expect(locked.card?.pay == nil)
        #expect(locked.card?.payHidden == true)

        try VoicePreferences(sayPayWhenLocked: true).save(to: model.session.store)
        let allowed = await Demo.voice(model, locked: true).status(.pay)
        #expect(allowed.speech == unlocked.speech)
        #expect(allowed.card?.pay != nil)

        // Pay never shows on a card nobody asked about pay for.
        let hours = await Demo.voice(model).status(.hours).card
        #expect(hours?.pay == nil)
        #expect(hours?.payHidden == false)
    }
}
