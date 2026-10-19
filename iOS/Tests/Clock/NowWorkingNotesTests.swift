import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Now working card")
struct NowWorkingTests {
    let f = ClockFixture()

    func live(_ state: FieldState, now: Date, lastAction: String? = nil, canUndo: Bool = false) -> LiveSnapshot? {
        LiveSnapshot.build(state: state, now: now, lastAction: lastAction, canUndo: canUndo)
    }

    @Test func offTheClockThereIsNoCard() {
        let state = f.state()
        #expect(NowWorking(state: state, live: live(state, now: f.today(7, 0))) == nil)
    }

    @Test func showsWhereYouAreAndTheSameRowsAsTheLockScreen() throws {
        let open = f.shift(f.today(7, 0))
        let state = f.state(shifts: [open], marks: f.marks(rows: 0...1, on: open))
        let snap = try #require(live(state, now: f.today(8, 0), lastAction: "Row 2 marked", canUndo: true))
        let card = try #require(NowWorking(state: state, live: snap))
        #expect(card.fieldName == "North Field")
        #expect(card.place == "Block 1, row 3")
        #expect(card.rows == snap.nextRows)
        #expect(card.rows.map(\.title) == ["Row 3", "Row 4", "Row 5"])
        #expect(card.rows.map { card.showsBlock($0) } == [false, false, false])
        #expect(card.lastAction == "Row 2 marked")
        #expect(card.canUndo)
        #expect(!card.onBreak)
        #expect(card.done == nil)
        #expect(card.shiftTrees == 20)
        #expect(card.fieldShaped == 20)
        #expect(card.fieldTotal == 200)
        #expect(card.fieldPercent == 10)
        #expect(card.blocks.map(\.title) == ["Block 1", "Block 2"])
    }

    @Test func rowsInTheNextBlockSayWhichBlock() throws {
        let open = f.shift(f.today(7, 0))
        let state = f.state(shifts: [open], marks: f.marks(rows: 0...8, on: open))
        let card = try #require(NowWorking(state: state, live: live(state, now: f.today(8, 0))))
        #expect(card.rows.map(\.title) == ["Row 10", "Row 1", "Row 2"])
        #expect(card.rows.map { card.showsBlock($0) } == [false, true, true])
    }

    @Test func onABreakTheRowsWait() throws {
        let open = f.shift(f.today(7, 0), breaks: [Break(kind: .lunch, start: f.today(12, 0))])
        let state = f.state(shifts: [open])
        let card = try #require(NowWorking(state: state, live: live(state, now: f.today(12, 5))))
        #expect(card.onBreak)
        #expect(card.waiting == "Row 1 is next when you’re back.")
    }

    @Test func aShapedFieldSaysSo() throws {
        let open = f.shift(f.today(7, 0))
        let state = f.state(shifts: [open], marks: f.marks(rows: 0...9, on: open) + f.marks(block: f.block2, rows: 0...9, on: open))
        let card = try #require(NowWorking(state: state, live: live(state, now: f.today(8, 0))))
        #expect(card.rows.isEmpty)
        #expect(card.place == nil)
        #expect(card.done == "Every row in North Field is shaped.")
        #expect(card.fieldPercent == 100)
    }

    @Test func noFieldYet() throws {
        let open = f.shift(f.today(7, 0))
        let state = FieldState(farm: f.farm, me: f.me, season: f.season, fields: [], blocks: [], myShifts: [open], marks: [],
                               members: [f.me], position: nil)
        let card = try #require(NowWorking(state: state, live: live(state, now: f.today(8, 0))))
        #expect(card.done == Speech.noField)
        #expect(card.fieldTotal == 0)
        #expect(card.fieldPercent == 0)
    }
}

@Suite("Field summary off the clock")
struct FieldSummaryTests {
    let f = ClockFixture()

    @Test func percentOfTheCurrentField() throws {
        let monday = f.shift(f.at(f.day(-2), 7, 0), f.at(f.day(-2), 9, 0))
        let summary = try #require(FieldSummary(state: f.state(shifts: [monday], marks: f.marks(rows: 0...2, on: monday))))
        #expect(summary.fieldName == "North Field")
        #expect(summary.shaped == 30)
        #expect(summary.total == 200)
        #expect(summary.percent == 15)
        #expect(summary.line == "30 of 200 trees shaped")
    }

    @Test func noBlocksNoSummary() {
        let state = FieldState(farm: f.farm, me: f.me, season: f.season, fields: [f.field], blocks: [], myShifts: [], marks: [],
                               members: [f.me], position: nil)
        #expect(FieldSummary(state: state) == nil)
    }
}

@MainActor
@Suite("Shift notes autosave")
struct ShiftNotesTests {
    let f = ClockFixture()

    @Test func typingIsKeptAsTypedButClampedToTheLimit() throws {
        let shift = f.shift(f.today(7, 0))
        let now = f.today(9, 0, 0).addingTimeInterval(0.000_7)
        let updated = try #require(ShiftNotesEditor.updated(shift, notes: "Rows 3 to 5 \n", now: now))
        #expect(updated.notes == "Rows 3 to 5 \n")
        #expect(updated.updatedAt == now.roundedToMillisecond)
        #expect(updated.breaks == shift.breaks)

        let long = String(repeating: "a", count: Limits.notes + 50)
        #expect(ShiftNotesEditor.updated(shift, notes: long, now: now)?.notes.count == Limits.notes)
        #expect(ShiftNotesEditor.updated(updated, notes: "Rows 3 to 5 \n", now: now) == nil)
    }

    @Test func savesOnceAfterAPause() async throws {
        var saved: [String] = []
        let editor = ShiftNotesEditor(debounce: .milliseconds(30))
        editor.load(shiftId: UUID(), notes: "")
        editor.save = { _, text in saved.append(text) }
        editor.text = "R"
        editor.edited()
        editor.text = "Row"
        editor.edited()
        editor.text = "Row 4 "
        editor.edited()
        #expect(editor.status == .saving)
        try await Task.sleep(for: .milliseconds(150))
        #expect(saved == ["Row 4 "])
        #expect(editor.status == .saved)
    }

    @Test func flushSavesRightAway() {
        var saved: [String] = []
        let editor = ShiftNotesEditor(debounce: .seconds(5))
        editor.load(shiftId: UUID(), notes: "")
        editor.save = { _, text in saved.append(text) }
        editor.text = "Fuel low"
        editor.edited()
        editor.flush()
        #expect(saved == ["Fuel low"])
        editor.flush()
        #expect(saved == ["Fuel low"])
    }

    @Test func aFailedSaveSaysSo() {
        struct Boom: Error {}
        let editor = ShiftNotesEditor(debounce: .seconds(5))
        editor.load(shiftId: UUID(), notes: "")
        editor.save = { _, _ in throw Boom() }
        editor.text = "x"
        editor.edited()
        editor.flush()
        #expect(editor.status == .failed)
    }

    @Test func notesAddedElsewhereShowUpUnlessYouAreTyping() {
        let id = UUID()
        let editor = ShiftNotesEditor(debounce: .seconds(5))
        editor.save = { _, _ in }
        editor.load(shiftId: id, notes: "Start at block 2")
        #expect(editor.text == "Start at block 2")
        #expect(editor.status == .saved)

        // Siri added a line: no edits here, so take it.
        editor.load(shiftId: id, notes: "Start at block 2\nFuel low")
        #expect(editor.text == "Start at block 2\nFuel low")

        // Typing, then another change arrives: keep what's being typed.
        editor.text = "Start at block 2\nFuel low\nRain"
        editor.edited()
        editor.load(shiftId: id, notes: "Something else")
        #expect(editor.text == "Start at block 2\nFuel low\nRain")

        // A new shift starts fresh.
        editor.load(shiftId: UUID(), notes: "")
        #expect(editor.text == "")
        #expect(editor.status == .idle)
    }

    @Test func aTrimmedServerEchoDoesntChangeWhatYouTyped() {
        let id = UUID()
        var saved: [String] = []
        let editor = ShiftNotesEditor(debounce: .seconds(5))
        editor.save = { _, text in saved.append(text) }
        editor.load(shiftId: id, notes: "")
        editor.setEditing(true)
        editor.text = "Rows 3 to 5 done.\n"
        editor.edited()
        editor.flush()
        #expect(saved == ["Rows 3 to 5 done.\n"])

        // The server stores notes trimmed, and the next pull brings that copy back.
        editor.load(shiftId: id, notes: "Rows 3 to 5 done.")
        #expect(editor.text == "Rows 3 to 5 done.\n")
        editor.setEditing(false)
        #expect(editor.text == "Rows 3 to 5 done.\n")

        // The next words go on the new line, not "done.Fuel low".
        editor.text += "Fuel low"
        editor.edited()
        editor.flush()
        #expect(saved.last == "Rows 3 to 5 done.\nFuel low")
    }

    @Test func sirisNewLineStillShowsWhenYoureNotTyping() {
        let id = UUID()
        let editor = ShiftNotesEditor(debounce: .seconds(5))
        editor.save = { _, _ in }
        editor.load(shiftId: id, notes: "Rows 3 to 5 done.")
        editor.load(shiftId: id, notes: "Rows 3 to 5 done.\nFuel low")
        #expect(editor.text == "Rows 3 to 5 done.\nFuel low")
    }

    @Test func notesThatArriveWhileTheBoxHasFocusWaitUntilYouLetGo() {
        let id = UUID()
        var saved: [String] = []
        let editor = ShiftNotesEditor(debounce: .seconds(5))
        editor.save = { _, text in saved.append(text) }
        editor.load(shiftId: id, notes: "Block 2")
        editor.setEditing(true)
        editor.load(shiftId: id, notes: "Block 2\nFuel low")
        #expect(editor.text == "Block 2")
        editor.setEditing(false)
        #expect(editor.text == "Block 2\nFuel low")

        // Typing meanwhile wins: it saves over what came in.
        editor.setEditing(true)
        editor.load(shiftId: id, notes: "Something else")
        editor.text = "Block 2\nFuel low\nRain"
        editor.edited()
        editor.flush()
        editor.setEditing(false)
        #expect(editor.text == "Block 2\nFuel low\nRain")
        #expect(saved == ["Block 2\nFuel low\nRain"])
    }
}

@Suite("Toasts")
struct ToastTests {
    @Test func longerMessagesStayLonger() {
        #expect(ClockToast(text: "Lunch started at 12:01.", succeeded: true).duration == .seconds(3))
        let long = ClockToast(text: "Row 14 was shaped by Sam on Oct 16. Next open row is 15. That's a long one to read with gloves on.", succeeded: false)
        #expect(long.duration > .seconds(4))
        #expect(long.duration <= .seconds(7))
    }
}
