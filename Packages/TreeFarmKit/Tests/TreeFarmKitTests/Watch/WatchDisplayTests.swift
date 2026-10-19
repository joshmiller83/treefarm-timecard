import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Watch display")
struct WatchDisplayTests {
    static let zone = "America/Indiana/Indianapolis"
    let block = UUID()
    /// Monday, Oct 19 2026 in Indiana.
    let cal = FarmCalendar(timeZone: TimeZone(identifier: WatchDisplayTests.zone)!, weekStart: .monday)
    func at(_ h: Int, _ m: Int) -> Date { cal.date(on: DayKey(year: 2026, month: 10, day: 19), hour: h, minute: m) }

    func chips(_ rows: [Int], name: String = "Block 2") -> [RowChip] {
        rows.map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: name) }
    }

    func snapshot(_ phase: LiveSnapshot.Phase, rows: [Int] = [14, 15, 16], trees: Int = 38, shaped: Int = 120, total: Int = 400,
                  reason: String = "") -> LiveSnapshot {
        LiveSnapshot(phase: phase, timerStart: at(7, 1), workedSoFar: 3 * 3600 + 41 * 60, workedLabel: "worked today",
                     breakStart: phase == .working ? nil : at(12, 1), breakReason: reason, fieldName: "North",
                     nextRows: Array(chips(rows).prefix(3)), shiftTrees: trees, fieldShaped: shaped, fieldTotal: total,
                     lastAction: nil, canUndo: false)
    }

    func state(_ snapshot: LiveSnapshot?, rows: [Int] = [14, 15, 16], signedIn: Bool = true, todayWorked: TimeInterval = 0) -> WatchState {
        WatchState(signedIn: signedIn, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: snapshot, nextRows: chips(rows),
                   todayWorked: todayWorked, todayTrees: 212, canUndo: false, recordWorkouts: true, updatedAt: at(10, 42),
                   farmTimeZone: Self.zone)
    }

    // MARK: Phase

    @Test func everyPhaseHasAWordAndAGlyph() {
        #expect(WatchDisplay.phase(nil) == .noData)
        #expect(WatchDisplay.phase(state(nil, signedIn: false)) == .signedOut)
        #expect(WatchDisplay.phase(state(nil)) == .offClock)
        #expect(WatchDisplay.phase(state(snapshot(.working))) == .working)
        #expect(WatchDisplay.phase(state(snapshot(.lunch))) == .lunch)
        #expect(WatchDisplay.phase(state(snapshot(.onBreak))) == .onBreak)

        #expect(WatchDisplay.phaseTitle(.working) == "Working")
        #expect(WatchDisplay.phaseTitle(.lunch) == "Lunch")
        #expect(WatchDisplay.phaseTitle(.onBreak) == "Break")
        #expect(WatchDisplay.phaseGlyph(.working) == "leaf.fill")
        #expect(WatchDisplay.phaseGlyph(.lunch) == "cup.and.saucer.fill")
        #expect(WatchDisplay.phaseGlyph(.onBreak) == "pause.fill")
        #expect(WatchDisplay.phaseGlyph(.offClock) == "leaf")
        #expect(WatchDisplay.phaseGlyph(.signedOut) == "iphone")
        #expect(WatchDisplay.phaseGlyph(.noData) == "iphone")
        for phase in WatchPhase.allCases {
            #expect(!WatchDisplay.phaseTitle(phase).isEmpty)
            #expect(!WatchDisplay.phaseGlyph(phase).isEmpty)
        }
    }

    // MARK: Primary

    @Test func workingTheButtonMarksTheShownRow() {
        let s = state(snapshot(.working))
        let primary = WatchDisplay.primary(s)
        #expect(primary == .markRow(chips([14])[0]))
        #expect(WatchDisplay.primaryLabel(primary) == "Row 14 done")
        #expect(WatchDisplay.primaryLabelSteps(primary) == ["Row 14 done", "Row 14", "14"])
        #expect(WatchDisplay.primaryAccessibilityLabel(primary) == "Mark row 14 in block 2 shaped")
        #expect(WatchDisplay.primaryGlyph(primary) == "checkmark")
        #expect(WatchDisplay.isPrimaryEnabled(primary))
        #expect(WatchDisplay.command(for: primary) == .markRow(RowRef(blockId: block, row: 13)))
    }

    @Test func theCrownPicksAnotherChip() {
        let s = state(snapshot(.working))
        #expect(WatchDisplay.primaryLabel(WatchDisplay.primary(s, chipIndex: 1)) == "Row 15 done")
        #expect(WatchDisplay.primaryLabel(WatchDisplay.primary(s, chipIndex: 2)) == "Row 16 done")
        #expect(WatchDisplay.primaryLabel(WatchDisplay.primary(s, chipIndex: 9)) == "Row 16 done")
        #expect(WatchDisplay.chips(s).count == 3)
        #expect(WatchDisplay.chipValue(WatchDisplay.chips(s)[1]) == "Row 15 in block 2")
        let many = state(snapshot(.working), rows: Array(14...30))
        #expect(WatchDisplay.chips(many).count == 3)
    }

    @Test func offTheClockTheButtonClocksIn() {
        let primary = WatchDisplay.primary(state(nil))
        #expect(primary == .clockIn)
        #expect(WatchDisplay.primaryLabel(primary) == "Clock in")
        #expect(WatchDisplay.primaryGlyph(primary) == "play.fill")
        #expect(WatchDisplay.command(for: primary) == .clockIn(fieldId: nil))
    }

    @Test func onABreakTheButtonGoesBackToWork() {
        for phase in [LiveSnapshot.Phase.lunch, .onBreak] {
            let primary = WatchDisplay.primary(state(snapshot(phase)))
            #expect(primary == .backToWork)
            #expect(WatchDisplay.primaryLabel(primary) == "Back to work")
            #expect(WatchDisplay.command(for: primary) == .endBreak)
        }
    }

    @Test func signedOutOrNeverConnectedThereIsNoButton() {
        #expect(WatchDisplay.primary(nil) == .none)
        #expect(WatchDisplay.primary(state(nil, signedIn: false)) == .none)
        #expect(!WatchDisplay.isPrimaryEnabled(.none))
        #expect(WatchDisplay.command(for: .none) == nil)
    }

    @Test func aShapedFieldSaysFieldDone() {
        let s = state(snapshot(.working, rows: [], shaped: 400, total: 400), rows: [])
        #expect(WatchDisplay.isFieldDone(s))
        #expect(WatchDisplay.primary(s) == .fieldDone)
        #expect(WatchDisplay.primaryLabel(.fieldDone) == "Field done")
        #expect(!WatchDisplay.isPrimaryEnabled(.fieldDone))
        #expect(WatchDisplay.noChipLine(s) == "Every row in North is shaped.")
    }

    @Test func runningOutOfChipsAwayFromThePhoneIsNotFieldDone() {
        let s = state(snapshot(.working, rows: [], shaped: 300, total: 400), rows: [])
        #expect(!WatchDisplay.isFieldDone(s))
        #expect(WatchDisplay.primary(s) == .outOfKnownRows)
        #expect(WatchDisplay.primaryLabel(.outOfKnownRows) == "Out of rows the watch knows")
        #expect(!WatchDisplay.isPrimaryEnabled(.outOfKnownRows))
        #expect(WatchDisplay.noChipLine(s) == "Out of rows the watch knows. Bring your phone closer.")
        // An empty field (no total) is never "done" either.
        let empty = state(snapshot(.working, rows: [], shaped: 0, total: 0), rows: [])
        #expect(WatchDisplay.primary(empty) == .outOfKnownRows)
        #expect(WatchDisplay.noChipLine(nil) == WatchDisplay.outOfKnownRows)
    }

    // MARK: Lines

    @Test func placeLines() {
        #expect(WatchDisplay.placeLine(state(snapshot(.working))) == "Block 2 · 38 trees")
        #expect(WatchDisplay.placeLine(state(snapshot(.working, trees: 1))) == "Block 2 · 1 tree")
        #expect(WatchDisplay.placeLine(state(nil)) == "Starts: Block 2 · Row 14")
        #expect(WatchDisplay.placeLine(state(nil, rows: [])) == nil)
        #expect(WatchDisplay.farmLine(state(nil)) == "Dull’s Tree Farm · North")
    }

    @Test func breakLines() {
        #expect(WatchDisplay.breakLine(state(snapshot(.lunch))) == "Lunch · since 12:01")
        #expect(WatchDisplay.breakLine(state(snapshot(.onBreak))) == "Break · since 12:01")
        #expect(WatchDisplay.breakLine(state(snapshot(.onBreak, reason: "Fuel run"))) == "Break · Fuel run")
        #expect(WatchDisplay.breakLine(state(snapshot(.working))) == nil)
        #expect(WatchDisplay.workedLine(snapshot(.lunch)) == "3:41 worked today")
    }

    @Test func todayAndLastShiftLines() {
        let closed = ClosedShift(shiftId: UUID(), start: at(6, 0), end: at(14, 30), worked: 8 * 3600 + 12 * 60, trees: 412)
        #expect(WatchDisplay.lastShiftSteps(closed) == ["Last shift 8:12 · 412 trees", "Last shift 8:12", "8:12"])
        #expect(WatchDisplay.hoursTodayLine(6.5 * 3600) == "6.5 h today")
        #expect(WatchDisplay.hoursTodayLine(8 * 3600) == "8 h today")
        #expect(WatchDisplay.todayLine(worked: 6 * 3600 + 40 * 60, trees: 212) == "6:40 worked · 212 trees")
        #expect(WatchDisplay.paceLine(34.4) == "34 trees an hour")
        #expect(WatchDisplay.paceLine(nil) == nil)
        let progress = WatchDisplay.fieldProgress(snapshot(.working, shaped: 248, total: 400))
        #expect(progress?.line == "North 62%")
        #expect(progress?.fraction == 0.62)
        #expect(WatchDisplay.fieldProgress(snapshot(.working, total: 0)) == nil)
        #expect(WatchDisplay.heartLine(bpm: 104.4, kcal: 612.2) == "104 bpm · 612 kcal")
        #expect(WatchDisplay.heartLine(bpm: nil, kcal: nil) == nil)
    }

    // MARK: Queue

    @Test func queueLines() {
        let s = state(nil)
        let mark = WatchRequest(body: .command(.markRow(RowRef(blockId: block, row: 13))), issuedAt: at(10, 31))
        let lunch = WatchRequest(body: .command(.startBreak(.lunch, reason: "")), issuedAt: at(10, 35))
        #expect(WatchDisplay.queueItemLine(mark, state: s) == "10:31 · Row 14 done")
        #expect(WatchDisplay.queueItemLine(lunch, state: s) == "10:35 · Lunch")
        #expect(WatchDisplay.refusedItemLine(lunch, speech: "You’re already on lunch since 10:34.", state: s)
                == "10:35 Lunch: You’re already on lunch since 10:34.")
        #expect(WatchDisplay.savedOnWatch(waiting: 2) == "Saved on watch · 2 waiting")
        #expect(WatchDisplay.waitingLine(count: 2) == "2 taps waiting for iPhone")
        #expect(WatchDisplay.waitingLine(count: 1) == "1 tap waiting for iPhone")
        #expect(WatchDisplay.waitingSince(count: 2, oldest: at(10, 31), state: s) == "2 taps waiting · 10:31")
        #expect(WatchDisplay.droppedLine(3) == "3 older row taps couldn’t be kept.")
        #expect(WatchDisplay.droppedLine(1) == "1 older row tap couldn’t be kept.")
        #expect(WatchDisplay.tookBack(mark) == "Took back row 14. It wasn’t sent yet.")
        #expect(WatchDisplay.queueFootnote == "These will count at the time you tapped once your iPhone is back.")
        #expect(WatchDisplay.queueGlyph == "iphone.slash")
    }

    @Test func phoneLines() {
        #expect(WatchDisplay.phoneLine(.reachable, waiting: 0) == "iPhone: in reach")
        #expect(WatchDisplay.phoneLine(.outOfReach, waiting: 2) == "iPhone: out of reach · 2 waiting")
        #expect(WatchDisplay.phoneLine(.needsUnlock, waiting: 0) == "iPhone: unlock once")
    }

    @Test func everyCommandHasALabel() {
        for command in WatchLinkTests.commands {
            #expect(!WatchDisplay.label(for: command).isEmpty)
        }
        #expect(WatchDisplay.label(for: .cancelShift(UUID())) == "Undo clock-in")
        #expect(WatchDisplay.label(for: .clockOut) == "Clock out")
        #expect(WatchDisplay.label(for: .endBreak) == "Back to work")
    }

    @Test func fixedSentences() {
        #expect(WatchDisplay.neverConnected == "Open Time Card on your iPhone once.")
        #expect(WatchDisplay.signedOut == "Open Time Card on your iPhone to sign in.")
        #expect(WatchDisplay.unlockPhone == "Unlock your phone once.")
        #expect(WatchDisplay.undoNeedsPhone == "Undo needs your phone nearby.")
        #expect(WatchDisplay.waitingForPhone == "Waiting for phone…")
        #expect(WatchDisplay.clockOutWaiting == "Clock-out waiting for iPhone")
        #expect(WatchDisplay.stuckClockOut == "Open Time Card near your iPhone to finish clocking out.")
        #expect(WatchDisplay.savedForSiri == "Saved on your watch. It’ll reach your phone when it’s back in range.")
        #expect(WatchDisplay.updatePhone == "Update Time Card on your iPhone.")
        #expect(WatchDisplay.workoutsOff == "Workouts off · Allow Time Card in the Health app on your iPhone.")
        #expect(WatchDisplay.recordingFrom(at(7, 14), state: state(nil)) == "Recording from 7:14")
        #expect(WatchDisplay.batteryWarning(level: 0.42) == "Battery 42%. Charge at lunch to last the shift.")
        #expect(WatchDisplay.batteryWarning(level: 0.5) == nil)
        #expect(WatchDisplay.batteryWarning(level: -1) == nil)
        #expect(WatchDisplay.asOf(at(10, 42), state: state(nil)) == "as of 10:42")
        #expect(WatchDisplay.timerAccessibility(3 * 3600 + 41 * 60) == "Worked 3 hours 41 minutes")
    }

    @Test func summaryLinesNeverShowPay() {
        #expect(WatchDisplay.summaryWorkedLine(trees: 412) == "worked · 412 trees")
        #expect(WatchDisplay.summaryWaitingLine(trees: 380) == "380 trees · waiting for iPhone")
        #expect(WatchDisplay.summaryHeartLine(avg: 104.2, max: 151) == "avg 104 · max 151")
        #expect(WatchDisplay.summaryHeartLine(avg: nil, max: nil) == nil)
        #expect(WatchDisplay.summaryEnergyLine(kcal: 1120.4, active: 7 * 3600 + 41 * 60) == "1,120 kcal · 7:41 act.")
        #expect(WatchDisplay.summaryEnergyLine(kcal: nil, active: 600) == "0:10 act.")
    }

    // MARK: Complications

    @Test func circularComplication() {
        let chip = chips([14])[0]
        #expect(WatchDisplay.rowNumber(chip) == "14")
        #expect(WatchDisplay.cornerRow(chip) == "R14")
        #expect(WatchDisplay.circularHours(6.5 * 3600) == "6.5h")
        #expect(WatchDisplay.circularHours(0) == "IN")
        #expect(WatchDisplay.noDataMark == "—")
    }

    @Test func rectangularComplication() {
        let working = state(snapshot(.working))
        #expect(WatchDisplay.rectangularTitle(working) == "Working · Block 2")
        #expect(WatchDisplay.rectangularDetail(working) == "Row 14 next · 38 trees")
        let lunch = state(snapshot(.lunch))
        #expect(WatchDisplay.rectangularTitle(lunch) == "Lunch since 12:01")
        #expect(WatchDisplay.rectangularDetail(lunch) == "3:41 worked today")
        let off = state(nil, todayWorked: 6.5 * 3600)
        #expect(WatchDisplay.rectangularTitle(off) == "Time Card")
        #expect(WatchDisplay.rectangularDetail(off) == "6.5 h today · Row 14 next")
        #expect(WatchDisplay.rectangularDetail(state(nil)) == "Row 14 next")
        #expect(WatchDisplay.rectangularTitle(nil) == "Time Card")
        #expect(WatchDisplay.rectangularDetail(nil) == nil)
        #expect(WatchDisplay.openOnPhone == "Open on iPhone")
        // Waiting taps take over line 3.
        #expect(WatchDisplay.rectangularDetail(working, waitingCount: 2) == "2 taps waiting for iPhone")
        #expect(WatchDisplay.rectangularDetail(working, waitingCount: 2, clockOutWaiting: true) == "Clock-out waiting for iPhone")
    }

    @Test func inlineComplication() {
        #expect(WatchDisplay.inlineDetail(state(snapshot(.working))) == "Row 14")
        #expect(WatchDisplay.inlineDetail(state(snapshot(.lunch))) == "3:41 worked")
        #expect(WatchDisplay.inlineDetail(state(nil, todayWorked: 6.5 * 3600)) == "6.5 h today")
        #expect(WatchDisplay.inlineDetail(nil) == "Time Card")
    }

    @Test func liveActivitySmallLayout() {
        #expect(WatchDisplay.smallTitle(snapshot(.working)) == "Working · Block 2")
        #expect(WatchDisplay.smallDetail(snapshot(.working), calendar: cal) == "Next Row 14 · 38 trees")
        #expect(WatchDisplay.smallTitle(snapshot(.lunch)) == "Lunch · 3:41 worked")
        #expect(WatchDisplay.smallDetail(snapshot(.lunch), calendar: cal) == "Since 12:01")
    }

    @Test func blockPhrasesMatchSpeech() {
        let short = Block(fieldId: UUID(), name: "2", gridRow: 0, gridColumn: 0, rowCount: 1, treesPerRow: 1)
        let long = Block(fieldId: UUID(), name: "North 3", gridRow: 0, gridColumn: 0, rowCount: 1, treesPerRow: 1)
        for b in [short, long] {
            #expect(WatchDisplay.blockPhrase(Speech.blockTitle(b)) == Speech.blockPhrase(b))
        }
    }
}
