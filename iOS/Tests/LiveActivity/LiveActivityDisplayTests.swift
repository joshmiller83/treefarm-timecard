import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// What the lock screen and the Dynamic Island show for each phase. The views only lay
/// these strings out, so the wording is pinned here.
@Suite("Live Activity display")
struct LiveActivityDisplayTests {
    typealias F = LiveFixtures

    @Test func workingShowsTheTimerTreesAndThreeRowButtons() {
        let d = LiveActivityDisplay(F.working())
        #expect(d.tone == .working)
        #expect(!d.isOnBreak)
        #expect(d.statusTitle == "Working")
        #expect(d.place == "North Field · Block 2")
        #expect(d.blockTitle == "Block 2")
        #expect(d.timerStart == F.now.addingTimeInterval(-(6 * 3600 + 42 * 60 + 10)))
        #expect(d.timerCaption == "worked today")
        #expect(d.frozenWorked == nil)
        #expect(d.trees == "212")
        #expect(d.treesCaption == "trees this shift")
        #expect(d.rows.map(\.number) == ["13", "14", "15"])
        #expect(d.rows.map(\.caption) == ["Row", "Row", "Row"])
        #expect(d.rows.map(\.accessibilityLabel) == ["Mark row 13 shaped", "Mark row 14 shaped", "Mark row 15 shaped"])
        #expect(d.fieldMessage == nil)
        #expect(d.compactRow == "13")
    }

    @Test func treesAreCountedWithThousandsAndOneIsSingular() {
        #expect(LiveActivityDisplay(F.working(trees: 1)).treesCaption == "tree this shift")
        #expect(LiveActivityDisplay(F.working(trees: 1_204)).trees == "1,204")
        #expect(LiveActivityDisplay(F.working(trees: 0)).treesCaption == "trees this shift")
    }

    @Test func fieldProgressIsAFractionWithASpokenLabel() {
        let d = LiveActivityDisplay(F.working(shaped: 2_135, total: 8_540))
        #expect(d.progress == 0.25)
        #expect(d.progressLabel == "2,135 of 8,540 trees shaped in North Field")
        #expect(LiveActivityDisplay(F.working(shaped: 0, total: 0)).progress == 0)
        #expect(LiveActivityDisplay(F.working(shaped: 9, total: 4)).progress == 1)
    }

    @Test func aRowInTheNextBlockSaysWhichBlock() {
        let rows = [F.chip(20), F.chip(1, block: F.block3, name: "Block 3"), F.chip(2, block: F.block3, name: "Block 3")]
        let d = LiveActivityDisplay(F.working(rows: rows))
        #expect(d.rows.map(\.caption) == ["Row", "Block 3", "Block 3"])
        // Voice Control: the words on the tile work, and so does "Mark row 1".
        #expect(d.rows.map(\.inputLabels) == [["Row 20", "Mark row 20"], ["Block 3 row 1", "Row 1", "Mark row 1"], ["Block 3 row 2", "Row 2", "Mark row 2"]])
        #expect(d.rows.map(\.number) == ["20", "1", "2"])
        #expect(d.rows[1].accessibilityLabel == "Mark Block 3, row 1 shaped")
        #expect(d.blockTitle == "Block 2")
    }

    @Test func aShapedFieldSaysSoInTheEngineWords() {
        let d = LiveActivityDisplay(F.working(rows: []))
        #expect(d.rows.isEmpty)
        #expect(d.fieldMessage == "Every row in North Field is shaped.")
        #expect(d.place == "North Field")
        #expect(d.compactRow == nil)
    }

    @Test func noFieldYetPointsToTheTreesTab() {
        let d = LiveActivityDisplay(F.working(rows: [], shaped: 0, total: 0, field: ""))
        #expect(d.fieldMessage == Speech.noField)
        #expect(d.place == "")
    }

    @Test func aStaleShiftSaysThisShift() {
        #expect(LiveActivityDisplay(F.working(label: "worked this shift")).timerCaption == "worked this shift")
    }

    @Test func lunchFreezesWorkedTimeAndCountsTheBreak() {
        let d = LiveActivityDisplay(F.onBreak(.lunch))
        #expect(d.tone == .lunch)
        #expect(d.isOnBreak)
        #expect(d.statusTitle == "On lunch")
        #expect(d.timerStart == F.now.addingTimeInterval(-12.5 * 60))
        #expect(d.frozenWorked == "4:12:08")
        #expect(d.frozenWorkedCaption == "worked today")
        #expect(d.breakDetail == nil)
    }

    @Test func aBreakShowsItsReason() {
        let d = LiveActivityDisplay(F.onBreak(.onBreak, reason: "Parts run", lastAction: "Break started"))
        #expect(d.tone == .onBreak)
        #expect(d.statusTitle == "On break")
        #expect(d.breakDetail == "Parts run")
        #expect(d.lastAction == .init(text: "Break started", canUndo: true))
    }

    @Test func aRowTapShowsTheLastActionWithUndo() {
        let d = LiveActivityDisplay(F.working(lastAction: "Row 14 marked", canUndo: true))
        #expect(d.lastAction == .init(text: "Row 14 marked", canUndo: true))
    }

    @Test func clockingInIsNotOfferedForUndo() {
        // The undo stack may still hold an earlier shift's rows; "Clocked in · Undo" would undo those.
        #expect(LiveActivityDisplay(F.working(lastAction: "Clocked in", canUndo: true)).lastAction == nil)
        #expect(LiveActivityDisplay(F.working(lastAction: "Clocked in", canUndo: false)).lastAction == nil)
    }

    @Test func anUndoIsConfirmedWithoutAnotherUndoButton() {
        let d = LiveActivityDisplay(F.working(lastAction: "Undid row 14", canUndo: true))
        #expect(d.lastAction == .init(text: "Undid row 14", kind: .undone, canUndo: false))
    }

    @Test func aRefusedTapSaysWhyWithoutACheckOrUndo() {
        // The row was shaped by someone else between the screen drawing and the tap.
        let d = LiveActivityDisplay(F.working(lastAction: "Row 14 was shaped by Sam on Oct 16.", canUndo: true))
        #expect(d.lastAction == .init(text: "Row 14 was shaped by Sam on Oct 16.", kind: .notice, canUndo: false))
        #expect(LiveActivityDisplay(F.working(lastAction: "That block isn’t on the map anymore.")).lastAction?.kind == .notice)
    }

    @Test func nothingToUndoShowsNoButton() {
        let d = LiveActivityDisplay(F.working(lastAction: "Row 14 marked", canUndo: false))
        #expect(d.lastAction == .init(text: "Row 14 marked", canUndo: false))
        #expect(LiveActivityDisplay(F.working(lastAction: nil)).lastAction == nil)
        #expect(LiveActivityDisplay(F.working(lastAction: "")).lastAction == nil)
    }

    @Test func timersReserveRoomForTheDigitsTheyWillReach() {
        // A running timer can't be measured, so it gets the width of the most it can show
        // before the next update. That may not come until iOS ends the activity, 8 h on.
        #expect(LiveActivityDisplay(F.working(worked: 5 * 60)).timerCharacters == 7)
        #expect(LiveActivityDisplay(F.working(worked: 1.9 * 3600)).timerCharacters == 7)
        #expect(LiveActivityDisplay(F.working(worked: 2.5 * 3600)).timerCharacters == 8, "10:30:00 by the time the card ends")
        #expect(LiveActivityDisplay(F.working(worked: 91 * 3600)).timerCharacters == 8)
        #expect(LiveActivityDisplay(F.working(worked: 99 * 3600)).timerCharacters == 9, "a clock-in left open for days")
        // On a break the timer counts the break.
        #expect(LiveActivityDisplay(F.onBreak(.lunch)).timerCharacters == 7)
        #expect(LiveActivityDisplay(F.onBreak(.onBreak, minutes: 3 * 60)).timerCharacters == 8)
    }

    @Test func aBreakTimerNeedsNoCaptionBesideThePill() {
        #expect(LiveActivityDisplay(F.onBreak(.lunch)).timerCaption == nil)
        #expect(LiveActivityDisplay(F.onBreak(.onBreak, reason: "Parts run")).timerCaption == nil)
    }

    @Test func frozenWorkedTimeReadsAloudInWords() {
        // The running timers speak for themselves; the frozen total needs words.
        #expect(LiveActivityDisplay(F.onBreak(.lunch)).frozenWorkedAccessibilityLabel == "4 hours 12 minutes worked today")
        #expect(LiveActivityDisplay(F.working()).frozenWorkedAccessibilityLabel == nil)
    }
}
