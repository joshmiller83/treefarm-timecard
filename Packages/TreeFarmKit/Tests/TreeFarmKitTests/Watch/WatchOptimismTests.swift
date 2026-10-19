import Foundation
import Testing
@testable import TreeFarmKit

/// The state the watch shows before the phone answers: the confirmed state with every waiting
/// tap applied, so the screen moves at once and stays right while taps wait.
@Suite("Watch optimism")
struct WatchOptimismTests {
    static let zone = "America/Indiana/Indianapolis"
    let block = UUID()
    let cal = FarmCalendar(timeZone: TimeZone(identifier: WatchOptimismTests.zone)!, weekStart: .monday)
    let shift = UUID()
    let epoch = UUID()
    let user = UUID()
    func at(_ h: Int, _ m: Int) -> Date { cal.date(on: DayKey(year: 2026, month: 10, day: 19), hour: h, minute: m) }

    func chips(_ rows: ClosedRange<Int>) -> [RowChip] {
        rows.map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: "Block 2") }
    }

    func working(rows: ClosedRange<Int> = 14...53, worked: TimeInterval = 3 * 3600, at now: Date? = nil) -> WatchState {
        let now = now ?? at(10, 0)
        let next = chips(rows)
        let snapshot = LiveSnapshot(phase: .working, timerStart: now.addingTimeInterval(-worked), workedSoFar: worked, workedLabel: "worked today",
                                    breakStart: nil, breakReason: "", fieldName: "North", nextRows: Array(next.prefix(3)),
                                    shiftTrees: 38, fieldShaped: 120, fieldTotal: 400, lastAction: nil, canUndo: false)
        return WatchState(signedIn: true, farmName: "Farm", fieldName: "North", snapshot: snapshot, nextRows: next,
                          todayWorked: worked, todayTrees: 38, canUndo: false, recordWorkouts: true, updatedAt: now,
                          epoch: epoch, revision: 7, userId: user, shiftId: shift, shiftStart: at(7, 0), farmTimeZone: Self.zone)
    }

    func offClock(todayWorked: TimeInterval = 0) -> WatchState {
        WatchState(signedIn: true, farmName: "Farm", fieldName: "North", snapshot: nil, nextRows: chips(14...53),
                   todayWorked: todayWorked, todayTrees: 0, canUndo: false, recordWorkouts: true, updatedAt: at(6, 50),
                   epoch: epoch, revision: 7, userId: user, farmTimeZone: Self.zone)
    }

    func mark(_ row: Int) -> FieldCommand { .markRow(RowRef(blockId: block, row: row - 1)) }

    /// Times are Doubles: compare to the millisecond.
    func near(_ a: TimeInterval?, _ b: TimeInterval) -> Bool { a.map { abs($0 - b) < 0.001 } ?? false }
    func near(_ a: Date?, _ b: Date) -> Bool { near(a?.timeIntervalSince(b), 0) }

    // MARK: Marks

    @Test func aMarkDropsTheChipItMarked() {
        let s = WatchOptimism.apply(mark(14), shiftId: shift, to: working(), at: at(10, 1))
        #expect(s.nextRows.first?.title == "Row 15")
        #expect(s.snapshot?.nextRows.map(\.title) == ["Row 15", "Row 16", "Row 17"])
        #expect(s.snapshot?.lastAction == "Row 14 marked")
        #expect(s.canUndo && s.snapshot?.canUndo == true)
        #expect(s.epoch == epoch && s.revision == 7)
    }

    @Test func twoMarksInARowMoveTwoChips() {
        var s = working()
        s = WatchOptimism.apply(mark(14), shiftId: shift, to: s, at: at(10, 1))
        s = WatchOptimism.apply(mark(15), shiftId: shift, to: s, at: at(10, 2))
        #expect(s.nextRows.first?.title == "Row 16")
    }

    @Test func markingTheCrownsChipDropsOnlyThatOne() {
        let s = WatchOptimism.apply(mark(16), shiftId: shift, to: working(), at: at(10, 1))
        #expect(s.nextRows.prefix(3).map(\.title) == ["Row 14", "Row 15", "Row 17"])
    }

    @Test func markingTwelveRowsOfflineKeepsGoingPastTheTenthChip() {
        var s = working()
        for row in 14...25 { s = WatchOptimism.apply(mark(row), shiftId: shift, to: s, at: at(10, row)) }
        #expect(s.nextRows.first?.title == "Row 26")
        #expect(s.nextRows.count == 28)
    }

    @Test func aRowThatIsntAChipChangesOnlyTheLastAction() {
        let s = WatchOptimism.apply(mark(60), shiftId: shift, to: working(), at: at(10, 1))
        #expect(s.nextRows == working().nextRows)
        #expect(s.snapshot?.lastAction == "Row 60 marked")
    }

    @Test func runningOutOfChipsLeavesNone() {
        var s = working(rows: 14...15)
        s = WatchOptimism.apply(mark(14), shiftId: shift, to: s, at: at(10, 1))
        s = WatchOptimism.apply(mark(15), shiftId: shift, to: s, at: at(10, 2))
        #expect(s.nextRows.isEmpty)
        #expect(WatchDisplay.primary(s) == .outOfKnownRows)
    }

    @Test func markingTreesSaysSo() {
        let s = WatchOptimism.apply(.markTrees(RowRef(blockId: block, row: 13), positions: 0...5), shiftId: shift, to: working(), at: at(10, 1))
        #expect(s.snapshot?.lastAction == "Marked trees 1 to 6")
        #expect(s.nextRows == working().nextRows)
    }

    // MARK: Clock and breaks

    @Test func aClockInOpensAShiftWithTheMintedId() {
        let minted = UUID()
        let s = WatchOptimism.apply(.clockIn(fieldId: nil), shiftId: minted, to: offClock(), at: at(7, 0))
        #expect(s.shiftId == minted)
        #expect(s.shiftStart == at(7, 0))
        #expect(s.snapshot?.phase == .working)
        #expect(near(s.snapshot?.timerStart, at(7, 0)))
        #expect(s.snapshot?.nextRows.map(\.title) == ["Row 14", "Row 15", "Row 16"])
        #expect(s.snapshot?.lastAction == "Clocked in")
        #expect(!s.canUndo)
        #expect(WatchDisplay.phase(s) == .working)
    }

    @Test func aSecondClockInTheSameDayCountsTheFirstShift() {
        let s = WatchOptimism.apply(.clockIn(fieldId: nil), shiftId: UUID(), to: offClock(todayWorked: 2 * 3600), at: at(13, 0))
        #expect(near(s.snapshot?.timerStart, at(11, 0)))
    }

    @Test func aClockInWhileOnTheClockChangesNothing() {
        #expect(WatchOptimism.apply(.clockIn(fieldId: nil), shiftId: UUID(), to: working(), at: at(10, 1)) == working())
    }

    @Test func lunchFreezesTheTimer() {
        let s = WatchOptimism.apply(.startBreak(.lunch, reason: ""), shiftId: shift, to: working(), at: at(12, 1))
        #expect(s.snapshot?.phase == .lunch)
        #expect(s.snapshot?.breakStart == at(12, 1))
        #expect(near(s.snapshot?.workedSoFar, 5 * 3600 + 60))
        #expect(s.snapshot?.lastAction == "Lunch started")
        #expect(s.hadLunchToday)
        #expect(WatchDisplay.primary(s) == .backToWork)
    }

    @Test func aBreakKeepsItsReason() {
        let s = WatchOptimism.apply(.startBreak(.break, reason: " Fuel run "), shiftId: shift, to: working(), at: at(10, 30))
        #expect(s.snapshot?.phase == .onBreak)
        #expect(s.snapshot?.breakReason == "Fuel run")
        #expect(!s.hadLunchToday)
        #expect(s.snapshot?.lastAction == "Break started")
    }

    @Test func backToWorkRestartsTheTimerFromTheFrozenTime() {
        var s = WatchOptimism.apply(.startBreak(.lunch, reason: ""), shiftId: shift, to: working(), at: at(12, 0))
        s = WatchOptimism.apply(.endBreak, shiftId: shift, to: s, at: at(12, 30))
        #expect(s.snapshot?.phase == .working)
        #expect(near(s.snapshot?.timerStart, at(7, 30)))
        #expect(s.snapshot?.breakStart == nil)
        #expect(s.snapshot?.lastAction == "Back to work")
    }

    @Test func aBreakWhileOnABreakChangesNothing() {
        let lunch = WatchOptimism.apply(.startBreak(.lunch, reason: ""), shiftId: shift, to: working(), at: at(12, 0))
        #expect(WatchOptimism.apply(.startBreak(.break, reason: ""), shiftId: shift, to: lunch, at: at(12, 5)) == lunch)
        #expect(WatchOptimism.apply(.endBreak, shiftId: shift, to: working(), at: at(12, 5)) == working())
    }

    @Test func clockOutClosesTheShift() {
        let s = WatchOptimism.apply(.clockOut, shiftId: shift, to: working(), at: at(15, 0))
        #expect(s.snapshot == nil && s.shiftId == nil && s.shiftStart == nil)
        #expect(s.lastClosedShift?.shiftId == shift && s.lastClosedShift?.trees == 38)
        #expect(s.lastClosedShift?.start == at(7, 0) && s.lastClosedShift?.end == at(15, 0))
        #expect(near(s.lastClosedShift?.worked, 8 * 3600))
        #expect(near(s.todayWorked, 8 * 3600))
        #expect(WatchDisplay.phase(s) == .offClock)
    }

    @Test func clockOutDuringLunchCountsTheFrozenTime() {
        var s = WatchOptimism.apply(.startBreak(.lunch, reason: ""), shiftId: shift, to: working(), at: at(12, 0))
        s = WatchOptimism.apply(.clockOut, shiftId: shift, to: s, at: at(12, 20))
        #expect(near(s.lastClosedShift?.worked, 5 * 3600))
    }

    @Test func undoClockInGoesBackOffTheClock() {
        let minted = UUID()
        var s = WatchOptimism.apply(.clockIn(fieldId: nil), shiftId: minted, to: offClock(), at: at(7, 0))
        s = WatchOptimism.apply(.cancelShift(minted), shiftId: minted, to: s, at: at(7, 1))
        #expect(s.snapshot == nil && s.shiftId == nil)
        #expect(s.lastClosedShift == nil)
        #expect(WatchDisplay.phase(s) == .offClock)
    }

    @Test func tapsForAnotherShiftChangeNothing() {
        let other = UUID()
        for command: FieldCommand in [mark(14), .clockOut, .startBreak(.lunch, reason: ""), .cancelShift(other), .addShiftNote("x")] {
            #expect(WatchOptimism.apply(command, shiftId: other, to: working(), at: at(10, 1)) == working())
            #expect(WatchOptimism.apply(command, shiftId: nil, to: working(), at: at(10, 1)) == working())
        }
    }

    @Test func undoAndPhoneOnlyCommandsArentPredicted() {
        for command: FieldCommand in [.undo, .moveTo(blockId: block, row: nil), .changeStart(at(6, 0))] {
            #expect(WatchOptimism.apply(command, shiftId: shift, to: working(), at: at(10, 1)) == working())
        }
    }

    @Test func signedOutNothingIsPredicted() {
        let out = WatchState.signedOut(epoch: epoch, revision: 1, now: at(7, 0))
        #expect(WatchOptimism.apply(.clockIn(fieldId: nil), shiftId: UUID(), to: out, at: at(7, 0)) == out)
    }

    // MARK: Displayed

    func request(_ command: FieldCommand, _ minute: Int, shiftId: UUID?) -> WatchRequest {
        WatchRequest(body: .command(command), issuedAt: at(10, minute), shiftId: shiftId)
    }

    @Test func aNewStateWithTwoQueuedMarksStillShowsRow16() {
        let queued = [request(mark(14), 1, shiftId: shift), request(mark(15), 2, shiftId: shift)]
        // A context push from the phone that knows nothing of them yet.
        var pushed = working()
        pushed.revision = 8
        let shown = WatchOptimism.displayed(confirmed: pushed, pending: queued)
        #expect(shown?.nextRows.first?.title == "Row 16")
        #expect(shown?.revision == 8)
    }

    @Test func appliedIdsArentAppliedTwice() {
        let first = request(mark(14), 1, shiftId: shift)
        let second = request(mark(15), 2, shiftId: shift)
        // The phone applied row 14 (its state already shows 15 next) but the reply was lost.
        var confirmed = working(rows: 15...53)
        confirmed.appliedRequestIds = [first.id]
        let shown = WatchOptimism.displayed(confirmed: confirmed, pending: [first, second])
        #expect(shown?.nextRows.first?.title == "Row 16")
    }

    @Test func eachRequestCountsOnceInTheOrderItWasMade() {
        let a = request(mark(14), 1, shiftId: shift)
        let b = request(mark(15), 2, shiftId: shift)
        // In flight and still in the outbox: the same request twice, out of order.
        let shown = WatchOptimism.displayed(confirmed: working(), pending: [b, a, b])
        #expect(shown?.nextRows.first?.title == "Row 16")
        let lunch = request(.startBreak(.lunch, reason: ""), 3, shiftId: shift)
        let back = request(.endBreak, 4, shiftId: shift)
        #expect(WatchOptimism.displayed(confirmed: working(), pending: [back, lunch])?.snapshot?.phase == .working)
    }

    @Test func aRefusedClockInsMarksStillShowOnTheOpenShift() {
        // The phone was already clocked in; the watch's clock-in will be refused and aliased,
        // so the marks made after it still land on the open shift.
        let minted = UUID()
        let shown = WatchOptimism.displayed(confirmed: working(), pending: [
            request(.clockIn(fieldId: nil), 1, shiftId: minted),
            request(mark(14), 2, shiftId: minted),
        ])
        #expect(shown?.shiftId == shift)
        #expect(shown?.nextRows.first?.title == "Row 15")
    }

    @Test func aQueuedClockInThenMarksOpenTheMintedShift() {
        let minted = UUID()
        let shown = WatchOptimism.displayed(confirmed: offClock(), pending: [
            WatchRequest(body: .command(.clockIn(fieldId: nil)), issuedAt: at(7, 0), shiftId: minted),
            WatchRequest(body: .command(mark(14)), issuedAt: at(7, 30), shiftId: minted),
        ])
        #expect(shown?.shiftId == minted)
        #expect(shown?.nextRows.first?.title == "Row 15")
    }

    @Test func nothingConfirmedNothingDisplayed() {
        #expect(WatchOptimism.displayed(confirmed: nil, pending: [request(mark(14), 1, shiftId: shift)]) == nil)
        #expect(WatchOptimism.displayed(confirmed: working(), pending: []) == working())
    }
}
