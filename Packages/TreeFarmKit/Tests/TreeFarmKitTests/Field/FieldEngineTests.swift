import Foundation
import Testing
@testable import TreeFarmKit

@Suite("FieldEngine")
struct FieldEngineTests {
    var f = FieldFixture()
    var undo = UndoStack<UndoEntry>()
    var cal: FarmCalendar { FarmCalendar(farm: f.farm) }
    func t(_ d: Date) -> String { Fmt.spokenTime(d, cal) }

    // MARK: clock

    @Test mutating func clockInStartsAShiftAndSaysWhereYouAre() throws {
        let r = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        #expect(r.speech == "Clocked in at \(t(f.monday9)). You’re on block 1, row 1.")
        let shift = try #require(f.state.openShift)
        #expect(shift.start == f.monday9)
        #expect(shift.rateCents == 1500)
        #expect(shift.userId == f.josh.userId)
        #expect(f.state.position == WorkPosition(fieldId: f.field.id, next: f.row(f.block1, 1)))
    }

    @Test mutating func clockingInTwiceSaysSinceWhen() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.at(5))
        #expect(r.speech == "You’re already clocked in since \(t(f.monday9)).")
    }

    @Test mutating func clockInWithNoBlocksJustSaysTheTime() {
        f.state.blocks = []
        let r = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        #expect(r.speech == "Clocked in at \(t(f.monday9)).")
    }

    @Test mutating func clockOutAsksFirstWithTodaysHours() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let ask = FieldEngine.confirmation(for: .clockOut, state: f.state, now: f.at(60))
        #expect(ask == "You’ve worked \(Fmt.spokenDuration(3600)) today. Clock out?")
    }

    @Test mutating func clockOutSaysHoursAndTrees() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(20))
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(40))
        let r = FieldEngine.run(.clockOut, &f.state, &undo, at: f.at(90))
        #expect(r.speech == "Clocked out at \(t(f.at(90))). \(Fmt.spokenDuration(5400)), 8 trees.")
        #expect(f.state.openShift == nil)
    }

    @Test mutating func clockOutWhenNotClockedIn() {
        let r = FieldEngine.run(.clockOut, &f.state, &undo, at: f.monday9)
        #expect(r.speech == "You’re not clocked in. Say \"clock in with Time Card\" first.")
    }

    @Test mutating func clockOutDuringLunchClosesTheLunch() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(180))
        _ = FieldEngine.run(.clockOut, &f.state, &undo, at: f.at(200))
        let shift = try #require(f.state.myShifts.first)
        #expect(shift.end == f.at(200))
        #expect(shift.breaks.first?.end == f.at(200))
    }

    // MARK: breaks

    @Test mutating func lunchAndBackToWork() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let start = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(180))
        #expect(start.speech == "Lunch started at \(t(f.at(180))).")
        let again = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(185))
        #expect(again.speech == "You’re already on lunch since \(t(f.at(180))). Say \"back to work\" when you’re done.")
        let back = FieldEngine.run(.endBreak, &f.state, &undo, at: f.at(210))
        #expect(back.speech == "Back at \(t(f.at(210))). Lunch was 30 minutes.")
        let notOnBreak = FieldEngine.run(.endBreak, &f.state, &undo, at: f.at(211))
        #expect(notOnBreak.speech == "You’re not on a break.")
    }

    @Test mutating func breakWithAReason() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.startBreak(.break, reason: "  fuel run "), &f.state, &undo, at: f.at(60))
        #expect(r.speech == "Break for fuel run started at \(t(f.at(60))).")
        #expect(f.state.openShift?.openBreak?.reason == "fuel run")
    }

    // MARK: rows

    @Test mutating func markingNeedsAShift() {
        let r = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.monday9)
        #expect(r.speech == "You’re not clocked in. Say \"clock in with Time Card\" first.")
    }

    @Test mutating func nextRowMarksTheFirstOpenRowAndMovesOn() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Row 1 marked, 4 trees. Next is row 2.")
        #expect(f.state.marks.count == 4)
        #expect(f.state.marks.allSatisfy { $0.userId == f.josh.userId && $0.seasonId == f.season.id })
        #expect(f.state.position?.next == f.row(f.block1, 2))
        if case .success(let o) = r { #expect(o.lastAction == "Row 1 marked") }
    }

    @Test mutating func nextRowSkipsRowsSomeoneElseShaped() {
        f.state.marks = f.samShaped(f.block1, rows: [1, 2], on: f.monday9.addingTimeInterval(-7 * 86400))
        let r0 = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        #expect(r0.speech == "Clocked in at \(t(f.monday9)). You’re on block 1, row 3.")
        let r = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Row 3 marked, 4 trees. Next is row 4.")
    }

    @Test mutating func partlyShapedRowsSayHowManyWereAlreadyDone() {
        f.state.marks = Array(f.samShaped(f.block1, rows: [1], on: f.monday9).prefix(2))
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Row 1 marked, 2 trees. 2 were already shaped. Next is row 2.")
    }

    @Test mutating func nextRowSaysTheBlockWhenItChanges() {
        f.state.marks = f.samShaped(f.block1, rows: [1, 2, 3, 4], on: f.monday9)
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Row 5 marked, 4 trees. Next is block 2, row 1.")
    }

    @Test mutating func theLastOpenRowAndThenAFinishedField() {
        f.state.marks = f.samShaped(f.block1, rows: [1, 2, 3, 4, 5], on: f.monday9) + f.samShaped(f.block2, rows: [1, 2], on: f.monday9)
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let last = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(10))
        #expect(last.speech == "Row 3 marked, 4 trees. That was the last open row in North.")
        let done = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(11))
        #expect(done.speech == "Every row in North is shaped.")
    }

    @Test mutating func markARowByNumberMovesPastIt() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markRow(f.row(f.block1, 3)), &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Row 3 marked, 4 trees. Next is row 4.")
        #expect(f.state.position?.next == f.row(f.block1, 4))
    }

    @Test mutating func markARowOutOfRange() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markRow(f.row(f.block1, 9)), &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Block 1 has rows 1 to 5.")
    }

    @Test mutating func markARowSomeoneElseShaped() {
        let lastMonday = f.monday9.addingTimeInterval(-7 * 86400)
        f.state.marks = f.samShaped(f.block1, rows: [2], on: lastMonday)
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markRow(f.row(f.block1, 2)), &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Row 2 was shaped by Sam on \(Fmt.monthDay(lastMonday, cal)). Next open row is 1.")
    }

    @Test mutating func markARowYouAlreadyMarked() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markRow(f.row(f.block1, 1)), &f.state, &undo, at: f.at(10))
        let r = FieldEngine.run(.markRow(f.row(f.block1, 1)), &f.state, &undo, at: f.at(11))
        #expect(r.speech == "Row 1 is already marked.")
    }

    @Test mutating func someTreesInARow() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.markTrees(f.row(f.block1, 2), positions: 0...2), &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Marked trees 1 to 3 in row 2.")
        let one = FieldEngine.run(.markTrees(f.row(f.block1, 2), positions: 3...3), &f.state, &undo, at: f.at(11))
        #expect(one.speech == "Marked tree 4 in row 2.")
        let bad = FieldEngine.run(.markTrees(f.row(f.block1, 3), positions: 2...7), &f.state, &undo, at: f.at(12))
        #expect(bad.speech == "Block 1 has 4 trees in each row.")
    }

    @Test mutating func farRowsAskFirst() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        #expect(FieldEngine.confirmation(for: .markRow(f.row(f.block1, 2)), state: f.state, now: f.at(1)) == nil)
        #expect(FieldEngine.confirmation(for: .markRow(f.row(f.block2, 2)), state: f.state, now: f.at(1)) == "Row 2 in block 2? You’re in block 1.")
        var big = f.block1
        big.rowCount = 61
        f.state.blocks = [big, f.block2]
        #expect(FieldEngine.confirmation(for: .markRow(f.row(big, 40)), state: f.state, now: f.at(1)) == "Row 40 in block 1? That’s 39 rows ahead.")
        #expect(FieldEngine.confirmation(for: .markRow(f.row(big, 6)), state: f.state, now: f.at(1)) == nil)
    }

    @Test mutating func moveToABlock() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.moveTo(blockId: f.block2.id, row: nil), &f.state, &undo, at: f.at(1))
        #expect(r.speech == "Okay, block 2, row 1 is next.")
        #expect(f.state.position?.next == f.row(f.block2, 1))
    }

    @Test mutating func moveToAShapedRowFindsTheNextOpenOne() {
        f.state.marks = f.samShaped(f.block2, rows: [2], on: f.monday9)
        let r = FieldEngine.run(.moveTo(blockId: f.block2.id, row: 1), &f.state, &undo, at: f.at(1))
        #expect(r.speech == "Row 2 in block 2 is already shaped. Next open row is 3.")
        #expect(f.state.position?.next == f.row(f.block2, 3))
    }

    // MARK: undo

    @Test mutating func undoARow() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(10))
        let r = FieldEngine.run(.undo, &f.state, &undo, at: f.at(11))
        #expect(r.speech == "Undid row 1.")
        #expect(f.state.marks.isEmpty)
        #expect(f.state.position?.next == f.row(f.block1, 1))
        if case .success(let o) = r {
            #expect(o.records.count == 4)
            #expect(o.records.allSatisfy { if case .treeMark(let m) = $0 { m.deletedAt == f.at(11) && m.updatedAt == f.at(11) } else { false } })
        }
        let nothing = FieldEngine.run(.undo, &f.state, &undo, at: f.at(12))
        #expect(nothing.speech == "There’s nothing to undo.")
    }

    @Test mutating func undoALunch() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(180))
        let r = FieldEngine.run(.undo, &f.state, &undo, at: f.at(181))
        #expect(r.speech == "Undid lunch.")
        let shift = try #require(f.state.openShift)
        #expect(shift.breaks.isEmpty)
        #expect(shift.updatedAt == f.at(181))
    }

    @Test mutating func clockingInAndOutCantBeUndoneByVoice() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        #expect(undo.isEmpty)
    }

    // MARK: notes and start time

    @Test mutating func shiftNotesAppend() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.addShiftNote("Fuel low on the shears"), &f.state, &undo, at: f.at(5))
        #expect(r.speech == "Added to today’s notes.")
        _ = FieldEngine.run(.addShiftNote("Rows 3 and 4 are wet"), &f.state, &undo, at: f.at(6))
        #expect(try #require(f.state.openShift).notes == "Fuel low on the shears\nRows 3 and 4 are wet")
        let long = FieldEngine.run(.addShiftNote(String(repeating: "x", count: 2100)), &f.state, &undo, at: f.at(7))
        #expect(long.speech == "Added to today’s notes, but it was cut short to fit.")
        #expect(try #require(f.state.openShift).notes.count == Limits.notes)
    }

    @Test mutating func shiftNotesNeedAShiftToday() {
        let r = FieldEngine.run(.addShiftNote("hello"), &f.state, &undo, at: f.monday9)
        #expect(r.speech == "You’re not clocked in. Say \"clock in with Time Card\" first.")
    }

    @Test mutating func treeNotes() throws {
        let tree = TreeRef(blockId: f.block1.id, row: 1, position: 2)
        let r = FieldEngine.run(.addTreeNote(tree, body: " Leader is broken ", flag: .attention), &f.state, &undo, at: f.monday9)
        #expect(r.speech == "Noted on block 1, row 2, tree 3.")
        guard case .success(let o) = r, case .treeNote(let note)? = o.records.first else { Issue.record("no note"); return }
        #expect(note.body == "Leader is broken")
        #expect(note.authorName == "Josh")
        #expect(note.flag == .attention)
        let bad = FieldEngine.run(.addTreeNote(TreeRef(blockId: f.block1.id, row: 1, position: 9), body: "x", flag: .none), &f.state, &undo, at: f.monday9)
        #expect(bad.speech == "Block 1 has 4 trees in each row.")
        let empty = FieldEngine.run(.addTreeNote(tree, body: "  ", flag: .none), &f.state, &undo, at: f.monday9)
        #expect(empty.speech == "The note was empty, so nothing was saved.")
    }

    @Test mutating func changeTheStartTime() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.changeStart(f.at(-30)), &f.state, &undo, at: f.at(10))
        #expect(r.speech == "Start time changed to \(t(f.at(-30))).")
        #expect(try #require(f.state.openShift).start == f.at(-30))
        let future = FieldEngine.run(.changeStart(f.at(60)), &f.state, &undo, at: f.at(10))
        if case .failure(let e) = future { #expect(!e.speech.isEmpty) } else { Issue.record("a start in the future was accepted") }
    }
}
