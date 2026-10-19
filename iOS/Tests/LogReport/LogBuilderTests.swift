import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Log weeks")
struct LogBuilderTests {
    typealias F = LogReportFixture
    let cal = LogReportFixture.calendar
    let now = LogReportFixture.at(10, 21, 16, 0) // Wed, Oct 21

    @Test func shiftsGroupIntoFarmWeeksNewestFirst() {
        let shifts = [
            F.shift(10, 5, from: (7, 0), to: (15, 0)),
            F.shift(10, 12, from: (7, 0), to: (15, 0)),
            F.shift(10, 18, from: (7, 0), to: (11, 0)), // Sunday ends the Monday week
            F.shift(10, 19, from: (7, 0), to: (15, 0)),
            F.shift(10, 20, from: (6, 30), to: (14, 30)),
        ]
        let weeks = LogBuilder.weeks(shifts: shifts, trees: ShiftTrees(marks: [], blocks: []), calendar: cal, now: now)
        #expect(weeks.map(\.title) == ["This week", "Last week", "Oct 5 – Oct 11, 2026"])
        #expect(weeks.map(\.range) == ["Oct 19 – Oct 25, 2026", "Oct 12 – Oct 18, 2026", "Oct 5 – Oct 11, 2026"])
        #expect(weeks[0].shifts.map(\.day) == ["Tue, Oct 20", "Mon, Oct 19"])
        #expect(weeks[1].shifts.map(\.day) == ["Sun, Oct 18", "Mon, Oct 12"])
        #expect(weeks[1].days == 2)
    }

    @Test func aSundayWeekGroupsDifferently() {
        var farm = F.farm
        farm.weekStart = .sunday
        let sunday = FarmCalendar(farm: farm)
        let shifts = [F.shift(10, 17, from: (7, 0), to: (15, 0)), F.shift(10, 18, from: (7, 0), to: (11, 0))]
        let weeks = LogBuilder.weeks(shifts: shifts, trees: ShiftTrees(marks: [], blocks: []), calendar: sunday, now: now)
        #expect(weeks.map(\.title) == ["This week", "Last week"])
        #expect(weeks[0].range == "Oct 18 – Oct 24, 2026")
        #expect(weeks[1].range == "Oct 11 – Oct 17, 2026")
    }

    @Test func aShiftPastMidnightCountsForTheDayItStarted() {
        // Sunday night into Monday stays in last week.
        let night = F.shift(10, 18, from: (20, 0), to: (2, 0), nextDay: true)
        let weeks = LogBuilder.weeks(shifts: [night], trees: ShiftTrees(marks: [], blocks: []), calendar: cal, now: now)
        #expect(weeks.count == 1)
        #expect(weeks[0].title == "Last week")
        let row = weeks[0].shifts[0]
        #expect(row.clockIn == "8:00 PM")
        #expect(row.clockOut == "2:00 AM")
        #expect(row.endsNextDay)
        #expect(row.hours == "6.00")
    }

    @Test func weekTotalsAddHoursAndEachShiftsOwnPay() {
        let shifts = [
            F.shift(10, 19, from: (7, 0), to: (15, 30), breaks: [F.lunch(10, 19)], rate: 2000), // 8 h at $20
            F.shift(10, 20, from: (7, 0), to: (11, 15), rate: 2200), // 4.25 h at $22, after a raise
        ]
        let week = LogBuilder.weeks(shifts: shifts, trees: ShiftTrees(marks: [], blocks: []), calendar: cal, now: now)[0]
        #expect(week.hours == "12.25")
        #expect(week.pay == "$253.50")
        #expect(week.shifts.map(\.pay) == ["$93.50", "$160.00"])
        #expect(week.shifts.map(\.hours) == ["4.25", "8.00"])
    }

    @Test func rowsCarryTreesBreaksAndNotes() {
        let breaks = [Break(kind: .break, start: F.at(10, 19, 9, 40), end: F.at(10, 19, 9, 52), reason: "Fuel run"), F.lunch(10, 19)]
        let shift = F.shift(10, 19, from: (7, 2), to: (15, 31), breaks: breaks, notes: "  Rain after lunch.\n")
        let marks = F.marks(rows: 0...11, on: shift) + F.marks(rows: 12...12, on: shift, positions: 0..<4)
        let trees = ShiftTrees(marks: marks, blocks: [F.block1, F.block2])
        let row = LogBuilder.weeks(shifts: [shift], trees: trees, calendar: cal, now: now)[0].shifts[0]
        #expect(row.day == "Mon, Oct 19")
        #expect(row.clockIn == "7:02 AM")
        #expect(row.clockOut == "3:31 PM")
        #expect(!row.endsNextDay)
        #expect(row.trees == 124)
        #expect(row.treeSummary == "Block 1: rows 1–12, row 13 (trees 1–4)")
        #expect(row.breakLines == ["Break 12 min (Fuel run)", "Lunch 30 min"])
        #expect(row.notes == "Rain after lunch.")
        #expect(row.hours == "7.78")
        #expect(row.spoken(showPay: false) == "Mon, Oct 19, 7:02 AM to 3:31 PM. 7.78 hours. 124 trees. Block 1: rows 1–12, row 13 (trees 1–4). Break 12 min (Fuel run). Lunch 30 min. Notes: Rain after lunch.")
        #expect(row.spoken(showPay: true).contains("$155.67"))
    }

    @Test func anOpenShiftRunsToNow() {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 21, 7, 0),
                         breaks: [Break(kind: .lunch, start: F.at(10, 21, 12, 0), end: F.at(10, 21, 12, 30))], rateCents: 2000)
        let row = LogBuilder.weeks(shifts: [open], trees: ShiftTrees(marks: [], blocks: []), calendar: cal, now: now)[0].shifts[0]
        #expect(row.isOpen)
        #expect(row.clockOut == nil)
        #expect(row.hours == "8.50")
        #expect(row.spoken(showPay: false).hasPrefix("Wed, Oct 21, 7:00 AM to now, still on the clock."))
    }

    @Test func deletedShiftsStayOff() {
        var gone = F.shift(10, 19, from: (7, 0), to: (15, 0))
        gone.deletedAt = now
        #expect(LogBuilder.weeks(shifts: [gone], trees: ShiftTrees(marks: [], blocks: []), calendar: cal, now: now).isEmpty)
    }
}

@Suite("Trees per shift")
struct ShiftTreesTests {
    typealias F = LogReportFixture

    @Test func lastSeasonsTreesStillCount() {
        let old = F.shift(10, 5, from: (7, 0), to: (15, 0))
        let marks = F.marks(rows: 0...1, on: old, season: F.oldSeasonId)
        let trees = ShiftTrees(marks: marks, blocks: [F.block1])
        #expect(trees.count(old.id) == 20)
        #expect(trees.summary(old.id) == "Block 1: rows 1–2")
    }

    @Test func aTreeTwoPhonesClaimedCountsOnceForTheWinner() {
        let a = F.shift(10, 12, from: (7, 0), to: (15, 0))
        let b = F.shift(F.sam, 10, 12, from: (7, 0), to: (15, 0))
        let tree = TreeRef(blockId: F.block1.id, row: 0, position: 0)
        let first = TreeMark(seasonId: F.seasonId, tree: tree, shiftId: a.id, userId: F.me, markedAt: F.at(10, 12, 8, 0))
        let second = TreeMark(seasonId: F.seasonId, tree: tree, shiftId: b.id, userId: F.sam, markedAt: F.at(10, 12, 9, 0))
        let trees = ShiftTrees(marks: [first, second], blocks: [F.block1])
        #expect(trees.count(a.id) == 1)
        #expect(trees.count(b.id) == 0)
        // Deleting the loser's shift still clears its stray record.
        let snap = F.snapshot(shifts: [a, b], marks: [first, second])
        #expect(ShiftTrees.marksToDelete(onShift: b.id, in: snap).map(\.id) == [second.id])
    }

    @Test func blocksListInFieldAndWalkOrder() {
        let s = F.shift(10, 12, from: (7, 0), to: (15, 0))
        let marks = F.marks(rows: 0...0, in: F.block2, on: s) + F.marks(rows: 4...5, in: F.block1, on: s)
        let trees = ShiftTrees(marks: marks, blocks: [F.block1, F.block2])
        let lines = trees.byBlock(s.id, fields: [Field(id: F.fieldId, farmId: F.farmId, name: "North Field")])
        #expect(lines.map(\.block.id) == [F.block1.id, F.block2.id])
        #expect(lines.map(\.count) == [20, 10])
        #expect(lines.map(\.text) == ["Block 1: rows 5–6", "Block 2: row 1"])
        #expect(trees.summary(s.id) == "Block 1: rows 5–6 · Block 2: row 1")
    }
}
