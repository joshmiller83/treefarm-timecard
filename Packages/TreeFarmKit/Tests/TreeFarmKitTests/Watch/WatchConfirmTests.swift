import Foundation
import Testing
@testable import TreeFarmKit

/// The watch asks the same questions Siri does, from its cached state, with no round trip.
@Suite("Watch confirm")
struct WatchConfirmTests {
    var f = FieldFixture()
    var undo = UndoStack<UndoEntry>()
    let big: Block

    init() {
        big = Block(fieldId: f.field.id, name: "3", gridRow: 1, gridColumn: 0, rowCount: 60, treesPerRow: 4, updatedAt: f.monday9)
        f.state.blocks.append(big)
    }

    func watchState(at now: Date) -> WatchState {
        WatchStateBuilder.build(state: f.state, now: now, epoch: UUID(), revision: 1, recordWorkouts: true,
                                appliedRequestIds: [], lastAction: nil, canUndo: false)
    }

    func expectSame(_ command: FieldCommand, builtAt: Date, askedAt: Date, sourceLocation: SourceLocation = #_sourceLocation) {
        let phone = FieldEngine.confirmation(for: command, state: f.state, now: askedAt)
        let watch = WatchConfirm.question(for: command, state: watchState(at: builtAt), now: askedAt)
        #expect(watch == phone, sourceLocation: sourceLocation)
    }

    @Test mutating func clockOutAsksWithTodaysHours() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        // The state was sent at 9:30; the question is asked at 16:12, the timer having run on.
        expectSame(.clockOut, builtAt: f.at(30), askedAt: f.at(7 * 60 + 12))
        #expect(WatchConfirm.question(for: .clockOut, state: watchState(at: f.at(30)), now: f.at(7 * 60 + 12))
                == "You’ve worked 7 hours 12 minutes today. Clock out?")
    }

    @Test mutating func clockOutDuringLunchCountsTheFrozenTime() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(180))
        expectSame(.clockOut, builtAt: f.at(181), askedAt: f.at(200))
    }

    @Test mutating func clockOutAfterAnEarlierShiftToday() {
        f.state.myShifts = [Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(-120), end: f.at(-60), rateCents: 1500)]
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        expectSame(.clockOut, builtAt: f.at(10), askedAt: f.at(90))
    }

    @Test mutating func clockOutOfAShiftFromYesterdaySaysThisShift() {
        f.state.myShifts = [Shift(userId: f.josh.userId, farmId: f.farm.id, start: f.at(-20 * 60), rateCents: 1500, updatedAt: f.at(-20 * 60))]
        expectSame(.clockOut, builtAt: f.at(0), askedAt: f.at(5))
        #expect(WatchConfirm.question(for: .clockOut, state: watchState(at: f.at(0)), now: f.at(5))?.hasSuffix("this shift. Clock out?") == true)
    }

    @Test mutating func aRowMoreThanFiveAwayAsks() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        f.state.position = WorkPosition(fieldId: f.field.id, next: RowRef(blockId: big.id, row: 13))
        // Row 40 in block 3: 26 rows ahead. Not one of the watch's chips.
        expectSame(.markRow(RowRef(blockId: big.id, row: 39)), builtAt: f.at(1), askedAt: f.at(2))
        #expect(WatchConfirm.question(for: .markRow(RowRef(blockId: big.id, row: 39)), state: watchState(at: f.at(1)), now: f.at(2))
                == "Row 40 in block 3? That’s 26 rows ahead.")
        // Behind, too.
        f.state.position = WorkPosition(fieldId: f.field.id, next: RowRef(blockId: big.id, row: 30))
        expectSame(.markRow(RowRef(blockId: big.id, row: 10)), builtAt: f.at(1), askedAt: f.at(2))
    }

    @Test mutating func closeRowsJustGo() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        f.state.position = WorkPosition(fieldId: f.field.id, next: RowRef(blockId: big.id, row: 13))
        for row in [13, 14, 18, 8] {
            let command = FieldCommand.markRow(RowRef(blockId: big.id, row: row))
            #expect(WatchConfirm.question(for: command, state: watchState(at: f.at(1)), now: f.at(2)) == nil)
            expectSame(command, builtAt: f.at(1), askedAt: f.at(2))
        }
    }

    @Test mutating func aRowInAnotherBlockAsks() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        // Next is block 1, row 1; block 2 appears among the chips.
        let command = FieldCommand.markRow(f.row(f.block2, 2))
        expectSame(command, builtAt: f.at(1), askedAt: f.at(2))
        #expect(WatchConfirm.question(for: command, state: watchState(at: f.at(1)), now: f.at(2)) == "Row 2 in block 2? You’re in block 1.")
    }

    @Test mutating func aBlockTheWatchHasNoNameForStillAsks() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let state = watchState(at: f.at(1))
        #expect(WatchConfirm.question(for: .markRow(RowRef(blockId: UUID(), row: 3)), state: state, now: f.at(2))
                == "Row 4 in another block? You’re in block 1.")
    }

    @Test mutating func otherCommandsNeverAsk() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let state = watchState(at: f.at(1))
        for command: FieldCommand in [.startBreak(.lunch, reason: ""), .endBreak, .clockIn(fieldId: nil), .undo, .cancelShift(UUID()), .addShiftNote("x")] {
            #expect(WatchConfirm.question(for: command, state: state, now: f.at(2)) == nil)
        }
    }

    @Test func offTheClockClockOutDoesntAsk() {
        let state = watchState(at: f.monday9)
        #expect(WatchConfirm.question(for: .clockOut, state: state, now: f.monday9) == nil)
        #expect(FieldEngine.confirmation(for: .clockOut, state: f.state, now: f.monday9) == nil)
    }
}
