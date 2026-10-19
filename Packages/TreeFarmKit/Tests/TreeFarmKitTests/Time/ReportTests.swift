import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Report periods")
struct ReportPeriodTests {
    typealias F = TimeFixture
    let now = F.wall("2026-10-18 10:00") // Sunday

    @Test func thisWeekAndLastWeek() {
        let this = ReportPeriod.thisWeek.bounds(now: now, calendar: F.indy)
        #expect(this.start == F.wall("2026-10-12 00:00") && this.end == F.wall("2026-10-19 00:00"))
        let last = ReportPeriod.lastWeek.bounds(now: now, calendar: F.indy)
        #expect(last.start == F.wall("2026-10-05 00:00") && last.end == F.wall("2026-10-12 00:00"))
        let sundayLast = ReportPeriod.lastWeek.bounds(now: now, calendar: F.indySunday)
        #expect(sundayLast.start == F.wall("2026-10-11 00:00") && sundayLast.end == F.wall("2026-10-18 00:00"))
    }

    @Test func lastWeekAcrossFallBack() {
        let last = ReportPeriod.lastWeek.bounds(now: F.wall("2026-11-04 10:00"), calendar: F.indy)
        #expect(last.start == F.at("2026-10-26T00:00:00-04:00"))
        #expect(last.end == F.at("2026-11-02T00:00:00-05:00"))
    }

    @Test func thisMonth() {
        let m = ReportPeriod.thisMonth.bounds(now: now, calendar: F.indy)
        #expect(m.start == F.wall("2026-10-01 00:00") && m.end == F.wall("2026-11-01 00:00"))
    }

    @Test func customDatesIncludeTheLastDay() {
        let p = ReportPeriod.custom(from: DayKey(year: 2026, month: 10, day: 1), to: DayKey(year: 2026, month: 10, day: 3))
        let b = p.bounds(now: now, calendar: F.indy)
        #expect(b.start == F.wall("2026-10-01 00:00") && b.end == F.wall("2026-10-04 00:00"))
        let one = ReportPeriod.custom(from: DayKey(year: 2026, month: 10, day: 1), to: DayKey(year: 2026, month: 10, day: 1)).bounds(now: now, calendar: F.indy)
        #expect(one.end == F.wall("2026-10-02 00:00"))
        let dst = ReportPeriod.custom(from: DayKey(year: 2026, month: 10, day: 31), to: DayKey(year: 2026, month: 11, day: 1)).bounds(now: now, calendar: F.indy)
        #expect(dst.end.timeIntervalSince(dst.start) == 49 * 3600)
    }

    @Test func backwardsCustomDatesBecomeOneDay() {
        let p = ReportPeriod.custom(from: DayKey(year: 2026, month: 10, day: 5), to: DayKey(year: 2026, month: 10, day: 3))
        let b = p.bounds(now: now, calendar: F.indy)
        #expect(b.start == F.wall("2026-10-05 00:00") && b.end == F.wall("2026-10-06 00:00"))
    }
}

@Suite("Report")
struct ReportTests {
    typealias F = TimeFixture
    let now = F.wall("2026-10-18 10:00")

    @Test func rowsAndTotalsForThePeriod() {
        let mon = F.shift("2026-10-12 07:00", "2026-10-12 15:30", breaks: [F.lunch("2026-10-12 12:00", "2026-10-12 12:30")], notes: "Rows 1–12")
        let monEvening = F.shift("2026-10-12 18:00", "2026-10-12 19:00")
        let sat = F.shift("2026-10-17 20:00", "2026-10-18 02:00") // past midnight, counts Saturday
        let open = F.shift("2026-10-18 07:00", nil)
        let lastWeek = F.shift("2026-10-11 07:00", "2026-10-11 09:00")
        let deleted = F.shift("2026-10-14 07:00", "2026-10-14 15:00", deleted: true)
        let trees: [UUID: Int] = [mon.id: 120, sat.id: 40, deleted.id: 99]
        let r = Report.build(shifts: [open, sat, lastWeek, deleted, mon, monEvening], period: .thisWeek, now: now, calendar: F.indy) { trees[$0.id] ?? 0 }
        #expect(r.start == F.wall("2026-10-12 00:00") && r.end == F.wall("2026-10-19 00:00"))
        #expect(r.rows.map(\.shift.id) == [mon.id, monEvening.id, sat.id, open.id])
        #expect(r.rows.map(\.worked) == [F.hours(8), F.hours(1), F.hours(6), F.hours(3)])
        #expect(r.rows.map(\.trees) == [120, 0, 40, 0])
        #expect(r.rows[0].breakLines == ["Lunch 30 min"])
        #expect(r.totalWorked == F.hours(18))
        #expect(r.daysWorked == 3)
        #expect(r.totalTrees == 160)
    }

    @Test func anEmptyPeriod() {
        let r = Report.build(shifts: [F.shift("2026-10-12 07:00", "2026-10-12 15:30")], period: .lastWeek, now: now, calendar: F.indy) { _ in 5 }
        #expect(r.rows.isEmpty)
        #expect(r.totalWorked == 0 && r.daysWorked == 0 && r.totalTrees == 0)
        #expect(r.start == F.wall("2026-10-05 00:00"))
    }
}
