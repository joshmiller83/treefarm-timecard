import Foundation
import Testing
@testable import TreeFarmKit

/// What the Apple Watch adds to the engine: a clock-in with the id the watch minted, and
/// `cancelShift`, the watch's "Undo clock-in".
@Suite("FieldEngine for the watch")
struct FieldEngineWatchTests {
    var f = FieldFixture()
    var undo = UndoStack<UndoEntry>()
    var cal: FarmCalendar { FarmCalendar(farm: f.farm) }
    func t(_ d: Date) -> String { Fmt.spokenTime(d, cal) }

    @Test func clockInCanUseAGivenId() throws {
        let id = UUID()
        let s = try Clock.clockIn(id: id, userId: f.josh.userId, farmId: f.farm.id, rateCents: 1500, at: f.monday9, shifts: [])
        #expect(s.id == id)
        #expect(s.start == f.monday9)
        // Without one, every clock-in still gets its own.
        let a = try Clock.clockIn(userId: f.josh.userId, farmId: f.farm.id, rateCents: 1500, at: f.monday9, shifts: [])
        let b = try Clock.clockIn(userId: f.josh.userId, farmId: f.farm.id, rateCents: 1500, at: f.monday9, shifts: [])
        #expect(a.id != b.id)
    }

    @Test mutating func clockInWithNewShiftIdUsesIt() throws {
        let minted = UUID()
        let result = FieldEngine.perform(.clockIn(fieldId: nil), state: f.state, undo: &undo, now: f.monday9, newShiftId: minted)
        let outcome = try result.get()
        guard case .shift(let shift)? = outcome.records.first else { Issue.record("no shift"); return }
        #expect(shift.id == minted)
        #expect(outcome.speech == "Clocked in at \(t(f.monday9)). You’re on block 1, row 1.")
    }

    @Test mutating func newShiftIdIsIgnoredByOtherCommands() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        let r = FieldEngine.perform(.startBreak(.lunch, reason: ""), state: f.state, undo: &undo, now: f.at(10), newShiftId: UUID())
        guard case .shift(let shift)? = try r.get().records.first else { Issue.record("no shift"); return }
        #expect(shift.id == open.id)
    }

    // MARK: cancelShift

    @Test mutating func cancelShiftSoftDeletesAnEmptyShiftWithinFiveMinutes() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        let r = FieldEngine.run(.cancelShift(open.id), &f.state, &undo, at: f.at(5))
        let outcome = try r.get()
        #expect(outcome.speech == "Cancelled the clock-in at \(t(f.monday9)).")
        #expect(outcome.lastAction == "Clock-in cancelled")
        guard case .shift(let gone)? = outcome.records.first else { Issue.record("no shift"); return }
        #expect(gone.id == open.id)
        #expect(gone.deletedAt != nil)
        #expect(gone.updatedAt > open.updatedAt)
        #expect(f.state.openShift == nil)
        #expect(f.state.liveShifts.isEmpty)
    }

    @Test mutating func cancelShiftLeavesTheUndoStackAlone() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        _ = FieldEngine.run(.addShiftNote("Wrong farm"), &f.state, &undo, at: f.at(1))
        let before = undo.count
        _ = FieldEngine.run(.cancelShift(open.id), &f.state, &undo, at: f.at(2))
        #expect(undo.count == before)
    }

    @Test mutating func cancelShiftRefusesAShiftWithMarks() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(1))
        let r = FieldEngine.run(.cancelShift(open.id), &f.state, &undo, at: f.at(2))
        #expect(r.speech == "That shift already has work on it. Change it in the Log.")
        #expect(f.state.openShift?.id == open.id)
    }

    @Test mutating func cancelShiftRefusesAShiftWithBreaks() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        _ = FieldEngine.run(.startBreak(.break, reason: ""), &f.state, &undo, at: f.at(1))
        let r = FieldEngine.run(.cancelShift(open.id), &f.state, &undo, at: f.at(2))
        #expect(r.speech == "That shift already has work on it. Change it in the Log.")
        #expect(f.state.openShift != nil)
    }

    @Test mutating func cancelShiftRefusesAfterFiveMinutes() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        let r = FieldEngine.run(.cancelShift(open.id), &f.state, &undo, at: f.at(5.1))
        #expect(r.speech == "That shift already has work on it. Change it in the Log.")
        #expect(f.state.openShift != nil)
    }

    @Test mutating func cancelShiftWithNothingOnTheClock() {
        let r = FieldEngine.run(.cancelShift(UUID()), &f.state, &undo, at: f.monday9)
        #expect(r.speech == Speech.notClockedIn)
    }

    @Test mutating func cancelShiftForAnotherShiftChangesNothing() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let r = FieldEngine.run(.cancelShift(UUID()), &f.state, &undo, at: f.at(1))
        #expect(r.speech == "That shift isn’t the one on the clock, so nothing was cancelled.")
        #expect(f.state.openShift != nil)
    }

    @Test func cancelShiftTravels() throws {
        let command = FieldCommand.cancelShift(UUID())
        #expect(try JSONCoding.decoder().decode(FieldCommand.self, from: JSONCoding.encoder().encode(command)) == command)
    }
}
