import Foundation
import Testing
@testable import TreeFarmKit

@Suite("FarmCalendar days")
struct FarmCalendarDayTests {
    typealias F = TimeFixture

    @Test func usesTheFarmsZoneAndWeekStart() {
        let farm = Farm(name: "Dull's Tree Farm", timeZoneId: "America/Indiana/Indianapolis", weekStart: .sunday)
        let cal = FarmCalendar(farm: farm)
        #expect(cal.timeZone.identifier == "America/Indiana/Indianapolis")
        #expect(cal.calendar.timeZone.identifier == "America/Indiana/Indianapolis")
        #expect(cal.calendar.identifier == .gregorian)
        #expect(cal.calendar.firstWeekday == 1)
        #expect(F.indy.calendar.firstWeekday == 2)
    }

    @Test func dayKeyIsTheFarmsLocalDay() {
        let lateEvening = F.at("2026-10-18T23:30:00-04:00")
        #expect(F.indy.dayKey(lateEvening) == DayKey(year: 2026, month: 10, day: 18))
        #expect(F.utc.dayKey(lateEvening) == DayKey(year: 2026, month: 10, day: 19))
    }

    @Test func startOfDayIsLocalMidnight() {
        let afternoon = F.at("2026-10-18T15:00:00-04:00")
        #expect(F.indy.startOfDay(afternoon) == F.at("2026-10-18T00:00:00-04:00"))
        #expect(F.indy.startOfDay(DayKey(year: 2026, month: 10, day: 18)) == F.at("2026-10-18T00:00:00-04:00"))
        #expect(F.utc.startOfDay(afternoon) == F.at("2026-10-18T00:00:00Z"))
    }

    @Test func sameDayFollowsLocalMidnight() {
        let cal = F.indy
        #expect(cal.isSameDay(F.at("2026-10-18T00:00:00-04:00"), F.at("2026-10-18T23:59:59-04:00")))
        #expect(!cal.isSameDay(F.at("2026-10-18T23:59:00-04:00"), F.at("2026-10-19T00:01:00-04:00")))
    }

    @Test(arguments: [TimeFixture.indy, TimeFixture.newYork])
    func springForwardDayIs23Hours(cal: FarmCalendar) {
        let start = cal.startOfDay(DayKey(year: 2026, month: 3, day: 8))
        #expect(start == F.at("2026-03-08T00:00:00-05:00"))
        let next = cal.addDays(start, 1)
        #expect(next == F.at("2026-03-09T00:00:00-04:00"))
        #expect(next.timeIntervalSince(start) == 23 * 3600)
        #expect(cal.dayKey(next) == DayKey(year: 2026, month: 3, day: 9))
    }

    @Test(arguments: [TimeFixture.indy, TimeFixture.newYork])
    func fallBackDayIs25Hours(cal: FarmCalendar) {
        let start = cal.startOfDay(DayKey(year: 2026, month: 11, day: 1))
        #expect(start == F.at("2026-11-01T00:00:00-04:00"))
        let next = cal.addDays(start, 1)
        #expect(next == F.at("2026-11-02T00:00:00-05:00"))
        #expect(next.timeIntervalSince(start) == 25 * 3600)
        #expect(cal.startOfDay(F.at("2026-11-01T23:30:00-05:00")) == start)
    }

    @Test func addDaysKeepsTheWallClockAcrossDST() {
        let cal = F.indy
        let sat = F.at("2026-03-07T08:00:00-05:00")
        #expect(cal.addDays(sat, 1) == F.at("2026-03-08T08:00:00-04:00"))
        #expect(cal.addDays(sat, 2) == F.at("2026-03-09T08:00:00-04:00"))
        #expect(cal.addDays(F.at("2026-03-09T08:00:00-04:00"), -2) == sat)
        #expect(cal.addDays(sat, 0) == sat)
    }

    @Test func dateOnADayAtAWallTime() {
        let cal = F.indy
        #expect(cal.date(on: DayKey(year: 2026, month: 10, day: 18), hour: 7, minute: 2) == F.at("2026-10-18T07:02:00-04:00"))
        #expect(cal.date(on: DayKey(year: 2026, month: 3, day: 8), hour: 12, minute: 0) == F.at("2026-03-08T12:00:00-04:00"))
        #expect(cal.date(on: DayKey(year: 2026, month: 3, day: 7), hour: 23, minute: 59) == F.at("2026-03-07T23:59:00-05:00"))
        #expect(F.newYork.date(on: DayKey(year: 2026, month: 11, day: 1), hour: 16, minute: 30) == F.at("2026-11-01T16:30:00-05:00"))
    }

    @Test func aMissingWallTimeStillLandsOnThatDay() {
        // 2:30 AM doesn't exist on spring-forward day; whatever Foundation picks must stay on Mar 8.
        let d = F.indy.date(on: DayKey(year: 2026, month: 3, day: 8), hour: 2, minute: 30)
        #expect(F.indy.dayKey(d) == DayKey(year: 2026, month: 3, day: 8))
    }
}
