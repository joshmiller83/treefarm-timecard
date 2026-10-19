import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Watch state builder")
struct WatchStateBuilderTests {
    var f = FieldFixture()
    var undo = UndoStack<UndoEntry>()
    let epoch = UUID()

    func build(_ state: FieldState, at now: Date, revision: Int = 3, recordWorkouts: Bool = true,
               applied: [UUID] = [], lastAction: String? = nil, canUndo: Bool = false) -> WatchState {
        WatchStateBuilder.build(state: state, now: now, epoch: epoch, revision: revision, recordWorkouts: recordWorkouts,
                                appliedRequestIds: applied, lastAction: lastAction, canUndo: canUndo)
    }

    func shift(start: Date, end: Date?, breaks: [Break] = []) -> Shift {
        Shift(userId: f.josh.userId, farmId: f.farm.id, start: start, end: end, breaks: breaks, rateCents: 1500, updatedAt: end ?? start)
    }

    @Test mutating func onTheClockItCarriesTheOpenShift() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(30))
        let open = try #require(f.state.openShift)
        let s = build(f.state, at: f.at(60), lastAction: "Row 1 marked", canUndo: true)
        #expect(s.signedIn)
        #expect(s.epoch == epoch && s.revision == 3)
        #expect(s.userId == f.josh.userId)
        #expect(s.shiftId == open.id)
        #expect(s.shiftStart == f.monday9)
        #expect(s.farmName == "Dull’s Tree Farm")
        #expect(s.fieldName == "North")
        #expect(s.farmTimeZone == "America/Indiana/Indianapolis")
        #expect(s.updatedAt == f.at(60))
        #expect(s.canUndo)
        #expect(s.recordWorkouts)
        #expect(s.snapshot == LiveSnapshot.build(state: f.state, now: f.at(60), lastAction: "Row 1 marked", canUndo: true))
        #expect(s.snapshot?.phase == .working)
        #expect(s.todayWorked == 3600)
        #expect(s.todayTrees == 4)
        #expect(s.nextRows.first?.title == "Row 2")
        #expect(s.nextRows.first?.blockName == "Block 1")
        #expect(s.snapshot?.nextRows == Array(s.nextRows.prefix(3)))
        #expect(s.lastClosedShift == nil)
    }

    @Test mutating func offTheClockItStillKnowsWhereYoudStart() {
        let s = build(f.state, at: f.monday9)
        #expect(s.snapshot == nil && s.shiftId == nil && s.shiftStart == nil)
        #expect(!s.isClockedIn)
        #expect(s.nextRows.map(\.title) == ["Row 1", "Row 2", "Row 3", "Row 4", "Row 5", "Row 1", "Row 2", "Row 3"])
        #expect(s.nextRows.map(\.blockName) == Array(repeating: "Block 1", count: 5) + Array(repeating: "Block 2", count: 3))
    }

    @Test mutating func itCarriesUpTo40Chips() {
        let big = Block(fieldId: f.field.id, name: "3", gridRow: 1, gridColumn: 0, rowCount: 60, treesPerRow: 10, updatedAt: f.monday9)
        f.state.blocks.append(big)
        let s = build(f.state, at: f.monday9)
        #expect(s.nextRows.count == WatchState.maxRows)
        #expect(WatchState.maxRows == 40)
        #expect(s.nextRows.last?.blockName == "Block 3")
        // Forty chips stay small enough for WatchConnectivity.
        let size = (try? JSONCoding.encoder().encode(s).count) ?? .max
        #expect(size < 10_000)
    }

    @Test mutating func theLastClosedShiftIsTheOneThatEndedLast() {
        let early = shift(start: f.at(-24 * 60), end: f.at(-16 * 60))
        let late = shift(start: f.at(-10 * 60), end: f.at(-6 * 60), breaks: [Break(kind: .lunch, start: f.at(-8 * 60), end: f.at(-7 * 60))])
        f.state.myShifts = [late, early]
        f.state.marks = f.samShaped(f.block1, rows: [1], on: f.at(-9 * 60)).map { var m = $0; m.shiftId = late.id; m.userId = f.josh.userId; return m }
        let s = build(f.state, at: f.monday9)
        #expect(s.lastClosedShift == ClosedShift(shiftId: late.id, start: f.at(-10 * 60), end: f.at(-6 * 60), worked: 3 * 3600, trees: 4))
    }

    @Test mutating func hadLunchTodayOnlyCountsToday() {
        f.state.myShifts = [shift(start: f.at(-24 * 60), end: f.at(-16 * 60), breaks: [Break(kind: .lunch, start: f.at(-20 * 60), end: f.at(-19 * 60))])]
        #expect(!build(f.state, at: f.at(60)).hadLunchToday)
        f.state.myShifts.append(shift(start: f.monday9, end: nil, breaks: [Break(kind: .break, start: f.at(20), end: f.at(30))]))
        #expect(!build(f.state, at: f.at(60)).hadLunchToday)
        f.state.myShifts[1].breaks.append(Break(kind: .lunch, start: f.at(40), end: f.at(50)))
        #expect(build(f.state, at: f.at(60)).hadLunchToday)
    }

    @Test mutating func appliedRequestIdsAreTheLast50() {
        let ids = (0..<60).map { _ in UUID() }
        let s = build(f.state, at: f.monday9, applied: ids)
        #expect(s.appliedRequestIds == Array(ids.suffix(50)))
    }

    @Test mutating func usualStartIsTheMedianOfTheLast10Starts() {
        let cal = FarmCalendar(farm: f.farm)
        func day(_ n: Int, _ h: Int, _ m: Int) -> Date {
            cal.date(on: cal.dayKey(f.monday9.addingTimeInterval(Double(-n) * 86_400)), hour: h, minute: m)
        }
        // Two shifts: too few to say.
        f.state.myShifts = [shift(start: day(1, 7, 0), end: day(1, 15, 0)), shift(start: day(2, 7, 10), end: day(2, 15, 0))]
        #expect(build(f.state, at: f.monday9).usualStart == nil)
        // Three: the middle one.
        f.state.myShifts.append(shift(start: day(3, 6, 50), end: day(3, 15, 0)))
        #expect(build(f.state, at: f.monday9).usualStart == DateComponents(hour: 7, minute: 0))
        // Four: halfway between the middle two (7:00 and 7:10).
        f.state.myShifts.append(shift(start: day(4, 8, 0), end: day(4, 15, 0)))
        #expect(build(f.state, at: f.monday9).usualStart == DateComponents(hour: 7, minute: 5))
        // Only the last 10 count: ten later 6:30 starts outvote the old ones.
        f.state.myShifts += (5..<15).map { shift(start: day(-$0 + 4, 6, 30), end: day(-$0 + 4, 7, 0)) }
        #expect(build(f.state, at: f.monday9).usualStart == DateComponents(hour: 6, minute: 30))
    }

    @Test mutating func usualStartReadsInTheFarmsTimeZone() {
        // 12:00 UTC is 8:00 in Indiana (EDT in October).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let starts = (1...3).map { utc.date(from: DateComponents(year: 2026, month: 10, day: 10 + $0, hour: 12))! }
        f.state.myShifts = starts.map { shift(start: $0, end: $0.addingTimeInterval(3600)) }
        #expect(build(f.state, at: f.monday9).usualStart == DateComponents(hour: 8, minute: 0))
    }

    @Test mutating func paceIsTodaysOnceThereIsEnough() {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        _ = FieldEngine.run(.markNextRow, &f.state, &undo, at: f.at(5))
        #expect(build(f.state, at: f.at(10)).pacePerHour == nil)
        let s = build(f.state, at: f.at(60))
        #expect(s.pacePerHour == 4)
    }

    @Test mutating func recordWorkoutsComesFromTheSetting() {
        #expect(!build(f.state, at: f.monday9, recordWorkouts: false).recordWorkouts)
    }

    @Test func signedOutCarriesNothing() {
        let s = WatchState.signedOut(epoch: epoch, revision: 9, now: f.monday9)
        #expect(!s.signedIn && s.userId == nil && s.nextRows.isEmpty && s.revision == 9)
    }

    @Test mutating func thereIsNoPayAnywhere() throws {
        _ = FieldEngine.run(.clockIn(fieldId: nil), &f.state, &undo, at: f.monday9)
        let json = String(decoding: try JSONCoding.encoder().encode(build(f.state, at: f.at(60))), as: UTF8.self)
        #expect(!json.localizedCaseInsensitiveContains("pay"))
        #expect(!json.localizedCaseInsensitiveContains("cents"))
        #expect(!json.contains("1500"))
    }
}
