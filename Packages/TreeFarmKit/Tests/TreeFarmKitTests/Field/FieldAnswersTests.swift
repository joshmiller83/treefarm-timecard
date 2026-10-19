import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Field answers and the lock-screen snapshot")
struct FieldAnswersTests {
    var f = FieldFixture()
    var undo = UndoStack<UndoEntry>()

    /// Clocked in at 9:00, two rows (8 trees) marked by 9:30.
    mutating func workAHalfHour() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(15))
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(30))
    }

    @Test mutating func hoursWorked() {
        workAHalfHour()
        let a = FieldAnswers.answer(.hours, state: f.state, now: f.at(90))
        #expect(a == "\(Fmt.spokenDuration(5400)) today, \(Fmt.spokenDuration(5400)) this week.")
    }

    @Test mutating func treesAndPace() {
        workAHalfHour()
        #expect(FieldAnswers.answer(.trees, state: f.state, now: f.at(30)) == "8 trees today, 16 an hour. You’re on block 1, row 3.")
    }

    @Test func treesBeforeAnyMarks() {
        #expect(FieldAnswers.answer(.trees, state: f.state, now: f.monday9) == "No trees marked yet today. You’re on block 1, row 1.")
    }

    @Test mutating func whereAmI() {
        workAHalfHour()
        #expect(FieldAnswers.answer(.whereAmI, state: f.state, now: f.at(30)) == "You’re on block 1, row 3. Next are rows 4 and 5.")
    }

    @Test mutating func whereAmIAtTheEndOfABlock() {
        f.state.marks = f.samShaped(f.block1, rows: [1, 2, 3], on: f.monday9)
        #expect(FieldAnswers.answer(.whereAmI, state: f.state, now: f.monday9) == "You’re on block 1, row 4. Next are row 5 and block 2, row 1.")
    }

    @Test mutating func pace() {
        workAHalfHour()
        #expect(FieldAnswers.answer(.pace, state: f.state, now: f.at(30)) == "16 trees an hour today. Your season pace is 16 an hour.")
    }

    @Test mutating func tooEarlyForAPace() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(1))
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(2))
        #expect(FieldAnswers.answer(.trees, state: f.state, now: f.at(2)) == "8 trees today. Too early for a pace. You’re on block 1, row 3.")
        #expect(FieldAnswers.answer(.pace, state: f.state, now: f.at(2)) == "8 trees today. Too early for a pace.")
        #expect(FieldAnswers.answer(.trees, state: f.state, now: f.at(15)).hasPrefix("8 trees today, 32 an hour."))
    }

    @Test mutating func theSeasonPaceComesWithEarlierDays() {
        // Last Monday: a shift with 2 rows over an hour.
        let lastWeek = f.monday9.addingTimeInterval(-7 * 86400)
        let old = Shift(userId: f.josh.userId, farmId: f.farm.id, start: lastWeek, end: lastWeek.addingTimeInterval(3600), rateCents: 1500, updatedAt: lastWeek)
        f.state.myShifts = [old]
        f.state.marks = (0..<2).flatMap { r in (0..<4).map { TreeMark(seasonId: f.season.id, tree: TreeRef(blockId: f.block2.id, row: r, position: $0), shiftId: old.id, userId: f.josh.userId, markedAt: lastWeek) } }
        workAHalfHour()
        #expect(FieldAnswers.answer(.pace, state: f.state, now: f.at(30)) == "16 trees an hour today. Your season pace is 11 an hour.")
    }

    @Test func aRateNeedsFifteenMinutes() {
        #expect(!PaceStats(trees: 24, worked: 14 * 60, treesPerHour: 102, minutesPerTree: 0.6, payCentsPerTree: 0).hasRate)
        #expect(PaceStats(trees: 24, worked: 15 * 60, treesPerHour: 96, minutesPerTree: 0.6, payCentsPerTree: 0).hasRate)
        #expect(!PaceStats(trees: 0, worked: 3600, treesPerHour: 0, minutesPerTree: 0, payCentsPerTree: 0).hasRate)
    }

    @Test mutating func payIsPrivateWhenLocked() {
        workAHalfHour()
        #expect(FieldAnswers.answer(.pay(locked: true, sayWhenLocked: false), state: f.state, now: f.at(90)) == "Unlock your phone to hear your pay.")
        #expect(FieldAnswers.answer(.pay(locked: true, sayWhenLocked: true), state: f.state, now: f.at(90)) == "$22.50 today, $22.50 this week.")
        #expect(FieldAnswers.answer(.pay(locked: false, sayWhenLocked: false), state: f.state, now: f.at(90)) == "$22.50 today, $22.50 this week.")
    }

    // MARK: snapshot

    @Test func noSnapshotWhenOffTheClock() {
        #expect(LiveSnapshot.build(state: f.state, now: f.monday9) == nil)
    }

    @Test mutating func workingSnapshot() throws {
        workAHalfHour()
        let s = try #require(LiveSnapshot.build(state: f.state, now: f.at(45), lastAction: "Row 2 marked", canUndo: true))
        #expect(s.phase == .working)
        #expect(s.timerStart == f.monday9)
        #expect(s.workedSoFar == 45 * 60)
        #expect(s.workedLabel == "worked today")
        #expect(s.nextRows.map(\.title) == ["Row 3", "Row 4", "Row 5"])
        #expect(s.nextRows.map(\.blockName) == ["Block 1", "Block 1", "Block 1"])
        #expect(s.nextRows.first?.blockId == f.block1.id)
        #expect(s.nextRows.first?.row == 2)
        #expect(s.shiftTrees == 8)
        #expect(s.fieldShaped == 8)
        #expect(s.fieldTotal == 32)
        #expect(s.fieldName == "North")
        #expect(s.lastAction == "Row 2 marked")
        #expect(s.canUndo)
        #expect(s.breakStart == nil)
    }

    @Test mutating func snapshotOnLunchFreezesTheWorkedTime() throws {
        workAHalfHour()
        _ = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(60))
        let s = try #require(LiveSnapshot.build(state: f.state, now: f.at(75)))
        #expect(s.phase == .lunch)
        #expect(s.workedSoFar == 3600)
        #expect(s.breakStart == f.at(60))
        // After lunch the timer picks up where it left off.
        _ = FieldEngine.run(.endBreak, &f.state, &undo, at: f.at(90))
        let back = try #require(LiveSnapshot.build(state: f.state, now: f.at(90)))
        #expect(back.phase == .working)
        #expect(back.timerStart == f.at(30))
    }

    @Test mutating func snapshotCrossesBlocks() throws {
        f.state.marks = f.samShaped(f.block1, rows: [1, 2, 3], on: f.monday9)
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let s = try #require(LiveSnapshot.build(state: f.state, now: f.monday9))
        #expect(s.nextRows.map(\.title) == ["Row 4", "Row 5", "Row 1"])
        #expect(s.nextRows.map(\.blockName) == ["Block 1", "Block 1", "Block 2"])
    }

    @Test mutating func snapshotForAShiftFromYesterday() throws {
        f.state.myShifts = [Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.monday9.addingTimeInterval(-86400), rateCents: 1500)]
        let s = try #require(LiveSnapshot.build(state: f.state, now: f.monday9))
        #expect(s.workedLabel == "worked this shift")
        #expect(s.workedSoFar == 86400)
    }

    @Test func snapshotsSurviveJSON() throws {
        let s = LiveSnapshot(phase: .onBreak, timerStart: Date(timeIntervalSince1970: 0), workedSoFar: 60, workedLabel: "worked today",
                             breakStart: Date(timeIntervalSince1970: 30), breakReason: "Fuel", fieldName: "North",
                             nextRows: [RowChip(blockId: UUID(), row: 3, title: "Row 4", blockName: "Block 1")],
                             shiftTrees: 4, fieldShaped: 10, fieldTotal: 20, lastAction: nil, canUndo: false)
        let back = try JSONDecoder().decode(LiveSnapshot.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
