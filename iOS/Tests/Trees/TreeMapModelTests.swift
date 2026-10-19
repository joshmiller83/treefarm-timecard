import CoreGraphics
import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@MainActor
@Suite("Tree map")
struct TreeMapModelTests {
    // MARK: Field and shift

    @Test func opensOnTheFirstFieldAndTheOpenShift() {
        let f = TreeMapFixture()
        #expect(f.model.field?.id == f.north.id)
        #expect(f.model.blocks.map(\.id) == [f.block1.id, f.block2.id, f.block3.id])
        #expect(f.model.markingShift?.id == f.open?.id)
        #expect(!f.model.isMarkingEarlierShift)
        #expect(f.model.myShifts.map(\.id) == [f.open!.id, f.earlier.id])
    }

    @Test func theWorkingFieldWinsUntilOneIsPicked() {
        let f = TreeMapFixture()
        f.model.workingFieldId = f.creek.id
        #expect(f.model.field?.id == f.creek.id)
        f.model.chosenFieldId = f.north.id
        #expect(f.model.field?.id == f.north.id)
    }

    @Test func offTheClockTreesGoOnTheLatestShift() {
        let f = TreeMapFixture(clockedIn: false)
        #expect(f.model.markingShift?.id == f.earlier.id)
        #expect(!f.model.isMarkingEarlierShift)
    }

    @Test func anEarlierShiftCanBePickedAndSwitchedBack() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        #expect(f.model.markingShift?.id == f.earlier.id)
        #expect(f.model.isMarkingEarlierShift)
        #expect(f.model.takeDirtyRows() == nil, "every shaped tree changes color")
        f.model.useOpenShift()
        #expect(f.model.markingShift?.id == f.open?.id)
        #expect(f.model.chosenShiftId == nil, "back to following the clock")
    }

    @Test func pickingTheOpenShiftFollowsTheClock() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        #expect(f.model.chosenShiftId == f.earlier.id)
        f.model.pickShift(f.open!.id)
        #expect(f.model.chosenShiftId == nil)
        f.model.perform(.markFor(shiftId: f.open!.id))
        #expect(f.model.chosenShiftId == nil)
    }

    @Test func switchBackFollowsTheNextClockIn() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        f.model.useOpenShift()
        f.clockOut()
        let next = f.clockInElsewhere()
        #expect(f.model.markingShift?.id == next.id)
        #expect(!f.model.isMarkingEarlierShift)
        f.model.tap(at: f.point(f.block2, row: 2, tree: 2))
        #expect(f.live(f.tree(f.block2, row: 2, tree: 2))?.shiftId == next.id)
    }

    @Test func clockingInElsewhereResetsTheMarkingShift() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        f.model.mode = .fill
        f.model.tap(at: f.point(f.block2, row: 9, tree: 1))
        #expect(f.model.anchor != nil)
        f.clockOut()
        #expect(f.model.markingShift?.id == f.earlier.id, "clocking out keeps the shift you picked")
        let next = f.clockInElsewhere()
        #expect(f.model.chosenShiftId == nil)
        #expect(f.model.markingShift?.id == next.id)
        #expect(f.model.anchor == nil, "the first tree was for the old shift")
        f.model.mode = .one
        f.model.tap(at: f.point(f.block2, row: 9, tree: 2))
        #expect(f.live(f.tree(f.block2, row: 9, tree: 2))?.shiftId == next.id)
    }

    @Test func pickingAnotherShiftClearsTheLastMessage() {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block1, row: 8))
        #expect(f.model.message != nil)
        f.model.pickShift(f.earlier.id)
        #expect(f.model.message == nil, "“Marked 12 trees…” was about the other shift")
    }

    @Test func clockingInFromTheMapKeepsItsMessage() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        f.reply = FieldReply(speech: "Clocked in at 9:00.", succeeded: true)
        f.model.clockIn()
        #expect(f.model.chosenShiftId == nil)
        #expect(f.model.message == MapMessage("Clocked in at 9:00.", tone: .done))
    }

    @Test func thePickerListsAPickedShiftOlderThanTheList() {
        let f = TreeMapFixture()
        // Sixty short shifts after Oct 18 push the Oct 18 shift off the list.
        for i in 0..<TreeMapModel.pickerLimit {
            let start = f.earlier.end!.addingTimeInterval(Double(i + 1) * 600)
            f.snapshot.apply(.shift(Shift(userId: f.me.userId, farmId: f.farm.id, start: start, end: start.addingTimeInterval(300), rateCents: 2000)))
        }
        f.sync()
        #expect(f.model.pickerShifts.count == TreeMapModel.pickerLimit)
        #expect(!f.model.pickerShifts.contains { $0.id == f.earlier.id })
        f.model.perform(.markFor(shiftId: f.earlier.id))
        #expect(f.model.pickerShifts.count == TreeMapModel.pickerLimit + 1)
        #expect(f.model.pickerShifts.last?.id == f.earlier.id)
    }

    @Test func aShiftAddedFromTheMapIsPicked() {
        let f = TreeMapFixture(clockedIn: false)
        f.model.beginAddingShift()
        let added = Shift(userId: f.me.userId, farmId: f.farm.id, start: f.calendar.date(on: DayKey(year: 2026, month: 10, day: 16), hour: 8, minute: 0),
                          end: f.calendar.date(on: DayKey(year: 2026, month: 10, day: 16), hour: 12, minute: 0), rateCents: 2000)
        f.snapshot.apply(.shift(added))
        f.sync()
        f.model.finishAddingShift()
        #expect(f.model.markingShift?.id == added.id)

        f.model.beginAddingShift()
        f.model.finishAddingShift()
        #expect(f.model.markingShift?.id == added.id, "cancelling the editor changes nothing")
    }

    // MARK: A shift left open

    @Test func aShiftLeftOpenSinceYesterdayIsFlagged() {
        let f = TreeMapFixture(clockedIn: false)
        let start = f.calendar.date(on: DayKey(year: 2026, month: 10, day: 18), hour: 15, minute: 0)
        let left = Shift(userId: f.me.userId, farmId: f.farm.id, start: start, rateCents: 2000)
        f.snapshot.apply(.shift(left))
        f.sync()
        #expect(f.model.markingShift?.id == left.id)
        #expect(!f.model.isMarkingEarlierShift)
        #expect(f.model.isMarkingStaleShift)
        #expect(f.model.staleShiftNote == "You’ve been clocked in since Sun, Oct 18 at 3:00 PM.")
    }

    @Test func todaysShiftIsFlaggedAfterSixteenHours() {
        let f = TreeMapFixture()
        #expect(!f.model.isMarkingStaleShift)
        #expect(f.model.staleShiftNote == nil)
        f.now = f.open!.start.addingTimeInterval(16 * 3600 + 1)
        #expect(f.model.isMarkingStaleShift)
        f.model.pickShift(f.earlier.id)
        #expect(!f.model.isMarkingStaleShift, "an earlier, closed shift has its own note")
    }

    @Test func shiftTitlesReadLikeTheArtifact() {
        let f = TreeMapFixture()
        #expect(f.model.shiftTitle(f.earlier) == "Sun, Oct 18 · 8:00 AM – 10:00 AM · 12 trees")
        #expect(f.model.shiftTitle(f.open!) == "Today · 7:00 AM – now")
    }

    // MARK: Row numbers

    @Test func aRowNumberMarksTheRowThenClearsIt() throws {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block1, row: 5))
        #expect(f.savedMarks.count == 12)
        #expect(f.savedMarks.allSatisfy { $0.shiftId == f.open?.id && $0.userId == f.me.userId && $0.seasonId == f.season.id })
        #expect(f.savedMarks.allSatisfy { $0.markedAt == f.now.roundedToMillisecond })
        #expect(f.model.message == MapMessage("Marked 12 trees in Block 1, row 5. Tap the row number again to clear it.", tone: .done))
        #expect(f.model.canUndo)

        f.model.tap(at: f.rowNumber(f.block1, row: 5))
        #expect(f.model.message?.text == "Cleared 12 trees from Block 1, row 5.")
        #expect(f.live(f.tree(f.block1, row: 5, tree: 1)) == nil)
    }

    @Test func aRowShapedByOthersSaysSo() {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block1, row: 1))
        #expect(f.saved.isEmpty)
        #expect(f.model.message == MapMessage("Every tree in Block 1, row 1 was shaped on another day.", tone: .warning))
    }

    @Test func downBlocksTakeRowTapsAcrossTheTop() {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block3, row: 2))
        #expect(f.savedMarks.count == 4)
        #expect(f.savedMarks.allSatisfy { $0.blockId == f.block3.id && $0.row == 1 })
        #expect(f.model.message?.text == "Marked 4 trees in Block 3, row 2. Tap the row number again to clear it.")
    }

    @Test func rowTapsInNotesModeOnlyExplain() {
        let f = TreeMapFixture()
        f.model.mode = .notes
        f.model.tap(at: f.rowNumber(f.block1, row: 5))
        #expect(f.saved.isEmpty)
        #expect(f.model.message?.tone == .hint)
    }

    // MARK: One tree, erase and fill

    @Test func aTreeTapTogglesIt() {
        let f = TreeMapFixture()
        f.model.tap(at: f.point(f.block1, row: 6, tree: 3))
        #expect(f.model.message?.text == "Marked Block 1, row 6, tree 3.")
        #expect(f.live(f.tree(f.block1, row: 6, tree: 3))?.shiftId == f.open?.id)
        f.model.tap(at: f.point(f.block1, row: 6, tree: 3))
        #expect(f.model.message?.text == "Unmarked Block 1, row 6, tree 3.")
        #expect(f.live(f.tree(f.block1, row: 6, tree: 3)) == nil)
    }

    @Test func someoneElsesTreeSaysWhenItWasShaped() {
        let f = TreeMapFixture()
        f.model.tap(at: f.point(f.block1, row: 1, tree: 4))
        #expect(f.saved.isEmpty)
        #expect(f.model.message == MapMessage("Block 1, row 1, tree 4 was shaped on Sep 22.", tone: .warning))
    }

    @Test func myEarlierShiftsTreeOffersThatShift() {
        let f = TreeMapFixture()
        f.model.tap(at: f.point(f.block1, row: 3, tree: 1))
        #expect(f.model.message == MapMessage("Block 1, row 3, tree 1 was shaped on Oct 18.", tone: .warning, action: .markFor(shiftId: f.earlier.id)))
        f.model.perform(.markFor(shiftId: f.earlier.id))
        #expect(f.model.markingShift?.id == f.earlier.id)
        f.model.tap(at: f.point(f.block1, row: 3, tree: 1))
        #expect(f.model.message?.text == "Unmarked Block 1, row 3, tree 1.")
    }

    @Test func eraseOnlyTakesThisShiftsTrees() {
        let f = TreeMapFixture()
        f.model.mode = .erase
        f.model.tap(at: f.point(f.block1, row: 7, tree: 1))
        #expect(f.model.message?.text == "Block 1, row 7, tree 1 isn’t marked on this shift.")
        #expect(f.saved.isEmpty)
        f.model.mode = .one
        f.model.tap(at: f.point(f.block1, row: 7, tree: 1))
        f.model.mode = .erase
        f.model.tap(at: f.point(f.block1, row: 7, tree: 1))
        #expect(f.model.message?.text == "Unmarked Block 1, row 7, tree 1.")
        f.model.tap(at: f.rowNumber(f.block1, row: 1))
        #expect(f.model.message?.text == "Nothing in Block 1, row 1 is marked on this shift.")
    }

    @Test func fillMarksEverythingBetweenTwoTrees() {
        let f = TreeMapFixture()
        f.model.mode = .fill
        f.model.tap(at: f.point(f.block2, row: 5, tree: 11))
        #expect(f.model.anchor == f.tree(f.block2, row: 5, tree: 11))
        #expect(f.model.message == MapMessage("Start: Block 2, row 5, tree 11. Now tap the last tree.", tone: .hint, action: .cancelFill))
        #expect(f.saved.isEmpty)
        f.model.tap(at: f.point(f.block2, row: 6, tree: 2))
        #expect(f.model.anchor == nil)
        #expect(f.savedMarks.count == 4)
        #expect(f.model.message?.text == "Marked 4 trees, from row 5, tree 11 to row 6, tree 2.")
    }

    @Test func fillStaysInOneBlock() {
        let f = TreeMapFixture()
        f.model.mode = .fill
        f.model.tap(at: f.point(f.block1, row: 5, tree: 1))
        f.model.tap(at: f.point(f.block2, row: 5, tree: 1))
        #expect(f.model.message?.text == MarkMessages.fillOneBlock)
        #expect(f.model.anchor == nil)
        #expect(f.saved.isEmpty)
    }

    @Test func fillCanBeCancelled() {
        let f = TreeMapFixture()
        f.model.mode = .fill
        f.model.tap(at: f.point(f.block1, row: 5, tree: 1))
        f.model.perform(.cancelFill)
        #expect(f.model.anchor == nil)
        #expect(f.model.message == nil)
    }

    @Test func changingModeDropsTheFirstTree() {
        let f = TreeMapFixture()
        f.model.mode = .fill
        f.model.tap(at: f.point(f.block1, row: 5, tree: 1))
        f.model.mode = .one
        #expect(f.model.anchor == nil)
    }

    // MARK: Undo

    @Test func undoTakesBackTheLastEdit() {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block1, row: 8))
        f.model.tap(at: f.point(f.block1, row: 9, tree: 1))
        f.model.undo()
        #expect(f.model.message == MapMessage(MarkMessages.undid, tone: .done))
        #expect(f.live(f.tree(f.block1, row: 9, tree: 1)) == nil)
        #expect(f.live(f.tree(f.block1, row: 8, tree: 1)) != nil)
        f.model.undo()
        #expect(f.live(f.tree(f.block1, row: 8, tree: 12)) == nil)
        #expect(!f.model.canUndo)
        f.model.undo()
        #expect(f.model.message == MapMessage(Speech.nothingToUndo, tone: .warning))
    }

    @Test func undoBringsBackClearedTrees() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        f.model.tap(at: f.rowNumber(f.block1, row: 3))
        #expect(f.model.message?.text == "Cleared 12 trees from Block 1, row 3.")
        f.model.undo()
        let back = f.live(f.tree(f.block1, row: 3, tree: 5))
        #expect(back?.shiftId == f.earlier.id)
        #expect(back?.markedAt == f.earlier.start.addingTimeInterval(1800), "the original time comes back")
    }

    @Test func undoSkipsEditsOnADeletedShift() {
        let f = TreeMapFixture()
        f.model.pickShift(f.earlier.id)
        f.model.tap(at: f.point(f.block2, row: 1, tree: 1))
        var gone = f.earlier
        gone.deletedAt = f.now
        f.snapshot.apply(.shift(gone))
        f.sync()
        #expect(!f.model.canUndo)
    }

    @Test func undoNeverPutsMarksOnADeletedBlock() {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block2, row: 4))
        f.model.tap(at: f.rowNumber(f.block2, row: 4))
        #expect(f.live(f.tree(f.block2, row: 4, tree: 1)) == nil)
        var gone = f.block2
        gone.deletedAt = f.now
        f.snapshot.apply(.block(gone))
        f.sync()
        #expect(!f.model.canUndo, "both edits were in the deleted block")
        f.model.undo()
        #expect(f.model.message == MapMessage(Speech.nothingToUndo, tone: .warning))
        #expect(!f.snapshot.marks.values.contains { $0.tree.blockId == f.block2.id && $0.isLive })
    }

    @Test func undoNeverPutsMarksPastTheEndOfAShrunkBlock() {
        let f = TreeMapFixture()
        f.model.tap(at: f.rowNumber(f.block2, row: 2))
        f.model.tap(at: f.rowNumber(f.block2, row: 20))
        f.model.tap(at: f.rowNumber(f.block2, row: 20))
        var shorter = f.block2
        shorter.rowCount = 10
        f.snapshot.apply(.block(shorter))
        f.sync()
        #expect(f.model.canUndo, "row 2 still fits")
        f.model.undo()
        #expect(f.live(f.tree(f.block2, row: 2, tree: 1)) == nil)
        #expect(!f.snapshot.marks.values.contains { $0.tree.blockId == f.block2.id && $0.tree.row >= 10 && $0.isLive })
    }

    @Test func undoFallsBackToTheLockScreensUndo() {
        let f = TreeMapFixture()
        #expect(!f.model.canUndo)
        f.fieldCanUndo = true
        f.sync()
        #expect(f.model.canUndo)
        f.reply = FieldReply(speech: "Undid the note on row 3, tree 5.", succeeded: true)
        f.model.undo()
        #expect(f.commands == [.undo])
        #expect(f.model.message == MapMessage("Undid the note on row 3, tree 5.", tone: .done))

        // The map's own edits come first.
        f.commands = []
        f.model.toggle(f.tree(f.block2, row: 5, tree: 5))
        f.model.undo()
        #expect(f.commands.isEmpty)
        #expect(f.model.message == MapMessage(MarkMessages.undid, tone: .done))
    }

    // MARK: Nothing to mark with

    @Test func withoutAShiftItSaysClockInFirst() {
        let f = TreeMapFixture(clockedIn: false)
        var gone = f.earlier
        gone.deletedAt = f.now
        f.snapshot.apply(.shift(gone))
        f.sync()
        #expect(f.model.markingShift == nil)
        f.model.tap(at: f.rowNumber(f.block1, row: 5))
        #expect(f.model.message == MapMessage(MarkMessages.needShift, tone: .warning))
        #expect(f.saved.isEmpty)
    }

    @Test func withoutASeasonItSaysWhoToAsk() {
        let f = TreeMapFixture(withSeason: false)
        f.model.tap(at: f.point(f.block1, row: 5, tree: 1))
        #expect(f.model.message?.text == Speech.noSeason)
        #expect(f.saved.isEmpty)
    }

    @Test func aFailedSaveSaysSoAndKeepsNothing() {
        let f = TreeMapFixture()
        f.failSaves = true
        f.model.tap(at: f.rowNumber(f.block1, row: 5))
        #expect(f.model.message == MapMessage(Speech.saveFailed, tone: .warning))
        #expect(!f.model.canUndo)
        #expect(f.model.rowSummary(RowRef(blockId: f.block1.id, row: 4))?.shaped == 0)
    }

    @Test func clockingInFromTheMapUsesFieldActions() {
        let f = TreeMapFixture(clockedIn: false)
        f.reply = FieldReply(speech: "Clocked in at 9:00. You’re on block 1, row 4.", succeeded: true)
        f.model.clockIn()
        #expect(f.commands == [.clockIn(fieldId: f.north.id)])
        #expect(f.model.message == MapMessage("Clocked in at 9:00. You’re on block 1, row 4.", tone: .done))
    }

    // MARK: Zoom

    @Test func theOverviewTapZoomsIntoABlock() {
        let f = TreeMapFixture()
        f.model.setZoom(.l)
        f.model.setZoom(.all)
        #expect(f.model.layout.metrics.isOverview)
        let frame = f.model.layout.frame(of: f.block2.id)!.frame
        f.model.tap(at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(f.model.zoom == .l)
        #expect(f.model.scrollRequest?.blockId == f.block2.id)
        #expect(f.model.message?.text == "Showing Block 2. Tap All to see the whole field again.")
        #expect(f.saved.isEmpty)
    }

    @Test func pinchingSnapsToTheNearestSize() {
        #expect(MapZoom.nearest(cellWidth: 27, overviewWidth: 4) == .m)
        #expect(MapZoom.nearest(cellWidth: 60, overviewWidth: 4) == .l)
        #expect(MapZoom.nearest(cellWidth: 14, overviewWidth: 4) == .xs)
        #expect(MapZoom.nearest(cellWidth: 21, overviewWidth: 4) == .s)
        #expect(MapZoom.nearest(cellWidth: 5, overviewWidth: 4) == .all)
        #expect(MapZoom.nearest(cellWidth: 5, overviewWidth: 12) == .xs, "a small field's overview is as big as XS")
        let f = TreeMapFixture()
        #expect(f.model.pinchEnded(cellWidth: 26 * 1.5) == .l)
        #expect(f.model.zoom == .l)
    }

    @Test func theLayoutFollowsZoomAndWidth() {
        let f = TreeMapFixture()
        let medium = f.model.layoutKey
        f.model.setZoom(.s)
        #expect(f.model.layoutKey != medium)
        #expect(f.model.layout.metrics == .s)
        f.model.setZoom(.all)
        let narrow = f.model.layoutKey
        f.model.viewportWidth = 700
        #expect(f.model.layoutKey != narrow)
        #expect(f.model.layout.size.width <= 700)
    }

    // MARK: Redrawing

    @Test func onlyTouchedRowsAreRedrawn() {
        let f = TreeMapFixture()
        _ = f.model.takeDirtyRows()
        f.model.tap(at: f.point(f.block1, row: 6, tree: 3))
        #expect(f.model.takeDirtyRows() == [RowRef(blockId: f.block1.id, row: 5)])
        f.sync()
        #expect(f.model.takeDirtyRows() == [], "the session's copy matches what the map already shows")

        // Someone else's mark arrives from the server.
        let theirs = TreeMark(seasonId: f.season.id, tree: f.tree(f.block2, row: 10, tree: 1), shiftId: f.samShift.id,
                              userId: f.sam.userId, markedAt: f.now)
        f.snapshot.apply(.treeMark(theirs))
        let before = f.model.revision
        f.sync()
        #expect(f.model.revision > before)
        #expect(f.model.takeDirtyRows() == [RowRef(blockId: f.block2.id, row: 9)])
        #expect(f.model.rowSummary(RowRef(blockId: f.block2.id, row: 9))?.shaped == 1)
    }

    // MARK: Tree card and notes

    @Test func longPressAndNotesModeOpenTheTreeCard() {
        let f = TreeMapFixture()
        f.model.longPress(at: f.point(f.block1, row: 4, tree: 2))
        #expect(f.model.openTree?.tree == f.tree(f.block1, row: 4, tree: 2))
        f.model.openTree = nil
        f.model.mode = .notes
        f.model.tap(at: f.point(f.block2, row: 1, tree: 1))
        #expect(f.model.openTree?.tree == f.tree(f.block2, row: 1, tree: 1))
        #expect(f.saved.isEmpty)
    }

    @Test func theTreeCardSaysWhoShapedItAndWhen() throws {
        let f = TreeMapFixture()
        let sams = try #require(f.model.treeInfo(f.tree(f.block1, row: 1, tree: 2)))
        #expect(sams.title == "Block 1, row 1, tree 2")
        #expect(sams.state == .earlier)
        #expect(sams.status == "Shaped by Sam Ortiz on Tue, Sep 22 at 9:00 AM.")
        #expect(!sams.canToggle)

        let mine = try #require(f.model.treeInfo(f.tree(f.block1, row: 3, tree: 2)))
        #expect(mine.status == "Shaped by you on Sun, Oct 18 at 8:30 AM.")

        f.model.toggle(f.tree(f.block1, row: 4, tree: 2))
        let now = try #require(f.model.treeInfo(f.tree(f.block1, row: 4, tree: 2)))
        #expect(now.state == .thisShift)
        #expect(now.status == "Shaped on this shift at 9:00 AM.")
        #expect(now.canToggle)

        let free = try #require(f.model.treeInfo(f.tree(f.block1, row: 9, tree: 9)))
        #expect(free.state == .notShaped)
        #expect(free.status == "Not shaped yet this season.")
        #expect(free.canToggle)
    }

    @Test func theTreeCardListsNotesNewestFirst() throws {
        let f = TreeMapFixture(role: .worker)
        let tree = f.tree(f.block1, row: 4, tree: 2)
        let older = f.note(on: tree, by: f.sam, body: "Leaning after the storm", flag: .attention, daysAgo: 3)
        let newer = f.note(on: tree, by: f.me, body: "Staked it", daysAgo: 1)
        f.snapshot.apply(.treeNote(older))
        f.snapshot.apply(.treeNote(newer))
        f.sync()
        let info = try #require(f.model.treeInfo(tree))
        #expect(info.notes.map(\.body) == ["Staked it", "Leaning after the storm"])
        #expect(info.notes[0].author == "You")
        #expect(info.notes[0].canEdit)
        #expect(info.notes[1].author == "Sam Ortiz")
        #expect(info.notes[1].flag == .attention)
        #expect(info.notes[1].when == "Oct 16, 9:00 AM")
        #expect(!info.notes[1].canEdit, "a worker can't change someone else's note")
        #expect(f.model.rowSummary(tree.rowRef)?.notes == 2)
    }

    @Test func adminsCanEditAnyNote() throws {
        let f = TreeMapFixture(role: .admin)
        let tree = f.tree(f.block1, row: 4, tree: 2)
        f.snapshot.apply(.treeNote(f.note(on: tree, by: f.sam, body: "Dead")))
        f.sync()
        #expect(try #require(f.model.treeInfo(tree)).notes[0].canEdit)
    }

    @Test func aNewNoteGoesThroughFieldActions() {
        let f = TreeMapFixture()
        let tree = f.tree(f.block2, row: 3, tree: 5)
        let reply = f.model.addNote(tree, body: "Needs a stake", flag: .attention)
        #expect(reply.succeeded)
        #expect(f.commands == [.addTreeNote(tree, body: "Needs a stake", flag: .attention)])
    }

    @Test func editingANoteSavesTheNewText() throws {
        let f = TreeMapFixture(role: .worker)
        let tree = f.tree(f.block1, row: 4, tree: 2)
        let note = f.note(on: tree, by: f.me, body: "Staked it")
        f.snapshot.apply(.treeNote(note))
        f.sync()
        #expect(f.model.editNote(note.id, body: "   ", flag: .none) == Speech.emptyNote)
        #expect(f.model.editNote(note.id, body: "  Staked it twice ", flag: .replant) == nil)
        let saved = try #require(f.saved.last?.first)
        guard case .treeNote(let edited) = saved else { Issue.record("not a note"); return }
        #expect(edited.body == "Staked it twice")
        #expect(edited.flag == .replant)
        #expect(edited.updatedAt == f.now.roundedToMillisecond)
        #expect(edited.createdAt == note.createdAt)
        #expect(try #require(f.model.treeInfo(tree)).notes[0].when.hasSuffix("· edited"))
    }

    @Test func deletingANoteMarksItDeleted() throws {
        let f = TreeMapFixture(role: .worker)
        let tree = f.tree(f.block1, row: 4, tree: 2)
        let mine = f.note(on: tree, by: f.me, body: "Staked it")
        let theirs = f.note(on: tree, by: f.sam, body: "Leaning")
        f.snapshot.apply(.treeNote(mine))
        f.snapshot.apply(.treeNote(theirs))
        f.sync()
        #expect(f.model.deleteNote(theirs.id) != nil, "workers delete only their own notes")
        #expect(f.model.deleteNote(mine.id) == nil)
        guard case .treeNote(let gone)? = f.saved.last?.first else { Issue.record("no note saved"); return }
        #expect(gone.deletedAt == f.now.roundedToMillisecond)
        #expect(try #require(f.model.treeInfo(tree)).notes.map(\.body) == ["Leaning"])
    }

    @Test func aNoteDeletedElsewhereSaysSo() {
        let f = TreeMapFixture(role: .worker)
        let tree = f.tree(f.block1, row: 4, tree: 2)
        var note = f.note(on: tree, by: f.me, body: "Staked it")
        f.snapshot.apply(.treeNote(note))
        f.sync()
        note.deletedAt = f.now
        f.snapshot.apply(.treeNote(note))
        f.sync()
        #expect(f.model.editNote(note.id, body: "Staked it twice", flag: .none) == MarkMessages.noteGone)
        #expect(f.model.deleteNote(note.id) == MarkMessages.noteGone)
        #expect(f.saved.isEmpty)
    }

    // MARK: Typed numbers

    @Test func typedNumbersMarkAndUnmark() {
        let f = TreeMapFixture()
        #expect(f.model.typeRange(blockId: f.block1.id, fromRow: 6, toRow: 7, fromTree: nil, toTree: nil, add: true))
        #expect(f.model.message?.text == "Marked 24 trees in Block 1, rows 6–7.")
        #expect(f.model.typeRange(blockId: f.block1.id, fromRow: 7, toRow: nil, fromTree: 12, toTree: 3, add: false))
        #expect(f.model.message?.text == "Unmarked 10 trees in Block 1, row 7.")
        #expect(!f.model.typeRange(blockId: f.block1.id, fromRow: 1, toRow: 2, fromTree: nil, toTree: nil, add: true))
        #expect(f.model.message?.text == "Those trees were already marked.")
    }

    @Test func typedNumbersOutsideTheBlockSayWhatFits() {
        let f = TreeMapFixture()
        #expect(!f.model.typeRange(blockId: f.block1.id, fromRow: 21, toRow: nil, fromTree: nil, toTree: nil, add: true))
        #expect(f.model.message?.text == "Rows in Block 1 go from 1 to 20.")
        #expect(!f.model.typeRange(blockId: f.block1.id, fromRow: 2, toRow: nil, fromTree: 1, toTree: 13, add: true))
        #expect(f.model.message?.text == "Trees go from 1 to 12 in each row of Block 1.")
        #expect(f.saved.isEmpty)
    }

    @Test func typedNumbersStartOnTheBlockInUse() {
        let f = TreeMapFixture()
        #expect(f.model.typingBlock?.id == f.block1.id)
        f.model.workingBlockId = f.block3.id
        #expect(f.model.typingBlock?.id == f.block3.id, "where Siri says you’re working")
        f.model.mapSettled(on: f.block2.id)
        #expect(f.model.typingBlock?.id == f.block2.id, "the block in the middle of the map")
        f.model.typeRange(blockId: f.block3.id, fromRow: 1, toRow: nil, fromTree: nil, toTree: nil, add: true)
        #expect(f.model.typingBlock?.id == f.block3.id, "the last block typed into")
        f.model.chosenFieldId = f.creek.id
        #expect(f.model.typingBlock?.id == f.model.blocks.first?.id, "another field starts on its first block")
    }

    @Test func zoomingIntoABlockTypesThere() {
        let f = TreeMapFixture()
        f.model.setZoom(.all)
        f.model.zoomInto(f.block2.id)
        #expect(f.model.typingBlock?.id == f.block2.id)
    }

    // MARK: Progress

    @Test func progressCountsTheFieldAndUsesMyPace() throws {
        let f = TreeMapFixture()
        let p = try #require(f.model.progress)
        // North: 240 + 240 + 24 trees; 36 shaped.
        #expect(p.total == 504)
        #expect(p.shaped == 36)
        #expect(p.percent == 7)
        #expect(p.summary == "36 of 504 trees shaped.")
        // My only shift with trees: 12 trees in 2 hours, so 468 trees left take 78 hours.
        #expect(p.timeLeft == "At 6.0 trees an hour, the rest takes about 78 hours.")
    }

    @Test func aMinutesOldPaceIsNotAnEstimate() throws {
        let f = TreeMapFixture(clockedIn: false)
        var gone = f.earlier
        gone.deletedAt = f.now
        f.snapshot.apply(.shift(gone))
        let fresh = Shift(userId: f.me.userId, farmId: f.farm.id, start: f.now.addingTimeInterval(-90), rateCents: 2000)
        f.snapshot.apply(.shift(fresh))
        f.sync()
        _ = f.model.typeRange(blockId: f.block2.id, fromRow: 1, toRow: 2, fromTree: nil, toTree: nil, add: true)
        let p = try #require(f.model.progress)
        #expect(p.summary == "60 of 504 trees shaped.")
        #expect(p.timeLeft == nil, "24 trees in 90 seconds isn't a pace yet")
    }

    @Test func aDoneFieldSaysSo() throws {
        let f = TreeMapFixture()
        f.model.chosenFieldId = f.creek.id
        _ = f.model.typeRange(blockId: f.model.blocks[0].id, fromRow: 1, toRow: 10, fromTree: nil, toTree: nil, add: true)
        let p = try #require(f.model.progress)
        #expect(p.percent == 100)
        #expect(p.summary == "Every row in Creek Field is shaped.")
        #expect(p.timeLeft == nil)
    }

    // MARK: VoiceOver rows

    @Test func rowSummariesReadWell() {
        let f = TreeMapFixture()
        let row1 = RowRef(blockId: f.block1.id, row: 0)
        #expect(f.model.rowSummary(row1)?.value == "12 of 12 shaped")
        #expect(f.model.rowSummary(RowRef(blockId: f.block1.id, row: 9))?.value == "Not shaped")
        f.model.toggle(f.tree(f.block1, row: 10, tree: 1))
        #expect(f.model.rowSummary(RowRef(blockId: f.block1.id, row: 9))?.value == "1 of 12 shaped, 1 on this shift")
        #expect(f.model.rowSummary(RowRef(blockId: f.block1.id, row: 9))?.title == "Row 10")
    }

    @Test func adjustingARowMarksOrUnmarksOneTree() {
        let f = TreeMapFixture()
        let row = RowRef(blockId: f.block1.id, row: 9)
        f.model.adjust(row, up: true)
        f.model.adjust(row, up: true)
        #expect(f.model.message?.text == "Marked Block 1, row 10, tree 2.")
        f.model.adjust(row, up: false)
        #expect(f.model.message?.text == "Unmarked Block 1, row 10, tree 2.")
        f.model.adjust(row, up: false)
        f.model.adjust(row, up: false)
        #expect(f.model.message?.text == "Nothing in Block 1, row 10 is marked on this shift.")
        f.model.adjust(RowRef(blockId: f.block1.id, row: 0), up: true)
        #expect(f.model.message?.text == "Block 1, row 1: 12 of 12 shaped.")
    }

    @Test func treeLinesForTheRowDetail() {
        let f = TreeMapFixture()
        let tree = f.tree(f.block1, row: 1, tree: 1)
        #expect(f.model.treeLine(tree) == "Tree 1: shaped earlier")
        #expect(f.model.trees(in: tree.rowRef).count == 12)
    }

    // MARK: A whole farm

    @Test func aWholeFarmOfMarksStaysQuick() {
        let f = TreeMapFixture()
        let big = Field(farmId: f.farm.id, name: "Big Field", sortOrder: 2)
        f.snapshot.apply(.field(big))
        var blocks: [Block] = []
        for i in 0..<14 {
            let block = Block(fieldId: big.id, name: "\(i + 1)", gridRow: 0, gridColumn: i, rowCount: 61, treesPerRow: 10)
            blocks.append(block)
            f.snapshot.apply(.block(block))
        }
        for block in blocks {
            for row in 0..<61 {
                for position in 0..<10 {
                    f.snapshot.apply(.treeMark(TreeMark(seasonId: f.season.id, tree: TreeRef(blockId: block.id, row: row, position: position),
                                                        shiftId: f.samShift.id, userId: f.sam.userId, markedAt: f.now)))
                }
            }
        }
        let clock = ContinuousClock()
        let load = clock.measure { f.sync() }
        f.model.chosenFieldId = big.id
        #expect(f.model.progress?.shaped == 8_540)
        let tap = clock.measure {
            f.model.pickShift(f.open?.id)
            f.model.tap(at: f.rowNumber(blocks[13], row: 61))
        }
        #expect(f.model.message?.text == "Every tree in Block 14, row 61 was shaped on another day.")
        #expect(load < .seconds(2))
        #expect(tap < .seconds(1))
    }
}
