import Foundation
import Testing
@testable import TreeFarmKit

/// With the phone out of reach, commands that are bound to fail aren't queued.
@Suite("Watch precheck")
struct WatchPrecheckTests {
    var f = FieldFixture()
    var undo = UndoStack<UndoEntry>()
    var cal: FarmCalendar { FarmCalendar(farm: f.farm) }

    func watchState(at now: Date) -> WatchState {
        WatchStateBuilder.build(state: f.state, now: now, epoch: UUID(), revision: 1, recordWorkouts: true,
                                appliedRequestIds: [], lastAction: nil, canUndo: false)
    }

    /// The phone's own answer for the same command, so the watch says what it would.
    func phoneSays(_ command: FieldCommand, at now: Date) -> String? {
        var scratch = undo
        if case .failure(let failure) = FieldEngine.perform(command, state: f.state, undo: &scratch, now: now) { return failure.speech }
        return nil
    }

    @Test func withNoStateEveryCommandIsRefused() {
        for command in WatchLinkTests.commands {
            #expect(WatchPrecheck.refusal(for: command, state: nil) == "Open Time Card on your iPhone once.")
        }
    }

    @Test func signedOutEveryCommandIsRefused() {
        let s = WatchState.signedOut(epoch: UUID(), revision: 1, now: f.monday9)
        for command in WatchLinkTests.commands {
            #expect(WatchPrecheck.refusal(for: command, state: s) == "Open Time Card on your iPhone to sign in.")
        }
    }

    @Test func notClockedIn() {
        let s = watchState(at: f.monday9)
        for command: FieldCommand in [.clockOut, .startBreak(.lunch, reason: ""), .endBreak, .markRow(f.row(f.block1, 1)),
                                      .markTrees(f.row(f.block1, 1), positions: 0...1), .cancelShift(UUID())] {
            #expect(WatchPrecheck.refusal(for: command, state: s) == Speech.notClockedIn)
            #expect(WatchPrecheck.refusal(for: command, state: s) == phoneSays(command, at: f.monday9))
        }
        // A note needs the shift it's for, which the watch only knows while clocked in.
        #expect(WatchPrecheck.refusal(for: .addShiftNote("x"), state: s) == Speech.notClockedIn)
        #expect(WatchPrecheck.refusal(for: .clockIn(fieldId: nil), state: s) == nil)
    }

    @Test mutating func alreadyClockedIn() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let s = watchState(at: f.at(1))
        #expect(WatchPrecheck.refusal(for: .clockIn(fieldId: nil), state: s) == "You’re already clocked in since \(Fmt.spokenTime(f.monday9, cal)).")
        #expect(WatchPrecheck.refusal(for: .clockIn(fieldId: nil), state: s) == phoneSays(.clockIn(fieldId: nil), at: f.at(2)))
        for command: FieldCommand in [.clockOut, .startBreak(.lunch, reason: ""), .markRow(f.row(f.block1, 1)), .addShiftNote("x")] {
            #expect(WatchPrecheck.refusal(for: command, state: s) == nil)
        }
    }

    @Test mutating func alreadyOnABreak() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.startBreak(.lunch, reason: ""), &f.state, &undo, at: f.at(180))
        let s = watchState(at: f.at(181))
        for command: FieldCommand in [.startBreak(.lunch, reason: ""), .startBreak(.break, reason: "")] {
            #expect(WatchPrecheck.refusal(for: command, state: s) == phoneSays(command, at: f.at(182)))
            #expect(WatchPrecheck.refusal(for: command, state: s)?.hasPrefix("You’re already on lunch since") == true)
        }
        #expect(WatchPrecheck.refusal(for: .endBreak, state: s) == nil)
        #expect(WatchPrecheck.refusal(for: .clockOut, state: s) == nil)
    }

    @Test mutating func onAnotherBreak() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.startBreak(.break, reason: ""), &f.state, &undo, at: f.at(60))
        let s = watchState(at: f.at(61))
        #expect(WatchPrecheck.refusal(for: .startBreak(.lunch, reason: ""), state: s) == phoneSays(.startBreak(.lunch, reason: ""), at: f.at(62)))
    }

    @Test mutating func notOnABreak() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let s = watchState(at: f.at(1))
        #expect(WatchPrecheck.refusal(for: .endBreak, state: s) == "You’re not on a break.")
        #expect(WatchPrecheck.refusal(for: .endBreak, state: s) == phoneSays(.endBreak, at: f.at(2)))
    }

    @Test mutating func cancellingAnotherShift() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let open = try #require(f.state.openShift)
        let s = watchState(at: f.at(1))
        #expect(WatchPrecheck.refusal(for: .cancelShift(open.id), state: s) == nil)
        let other = FieldCommand.cancelShift(UUID())
        #expect(WatchPrecheck.refusal(for: other, state: s) == phoneSays(other, at: f.at(2)))
    }

    @Test mutating func questionsAndUndoAreForThePhoneToAnswer() {
        let s = watchState(at: f.monday9)
        #expect(WatchPrecheck.refusal(for: .undo, state: s) == nil)
        #expect(WatchPrecheck.refusal(for: .moveTo(blockId: f.block2.id, row: nil), state: s) == nil)
    }
}
