import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Hours")
struct HoursTests {
    typealias F = TimeFixture

    @Test func todayWeekAndDays() {
        let now = F.wall("2026-10-18 10:00") // Sunday
        let shifts = [
            F.shift("2026-10-11 08:00", "2026-10-11 10:00"), // last week
            F.shift("2026-10-12 08:00", "2026-10-12 12:00"),
            F.shift("2026-10-13 08:00", "2026-10-13 16:00", breaks: [F.lunch("2026-10-13 12:00", "2026-10-13 12:30")]),
            F.shift("2026-10-14 08:00", "2026-10-14 17:00", deleted: true),
            F.shift("2026-10-18 07:00", nil, breaks: [F.rest("2026-10-18 09:30", nil)]),
        ]
        let h = Hours.summary(shifts: shifts, now: now, calendar: F.indy)
        #expect(h.today == F.hours(2.5))
        #expect(h.week == F.hours(14))
        #expect(h.days == [F.hours(4), F.hours(7.5), 0, 0, 0, 0, F.hours(2.5)])
        #expect(h.weekBounds == F.indy.weekBounds(containing: now))
        #expect(h.chartMax == F.hours(8))
    }

    @Test func chartMaxGrowsWithTheBiggestDay() {
        let now = F.wall("2026-10-18 10:00")
        let h = Hours.summary(shifts: [F.shift("2026-10-15 06:00", "2026-10-15 17:00")], now: now, calendar: F.indy)
        #expect(h.chartMax == F.hours(11))
        #expect(Hours.summary(shifts: [], now: now, calendar: F.indy).chartMax == F.hours(8))
    }

    @Test func shiftAcrossMidnightCountsToItsStartDay() {
        let now = F.wall("2026-10-18 10:00")
        let h = Hours.summary(shifts: [F.shift("2026-10-17 20:00", "2026-10-18 02:00")], now: now, calendar: F.indy)
        #expect(h.today == 0)
        #expect(h.days[5] == F.hours(6))
        #expect(h.days[6] == 0)
        #expect(h.week == F.hours(6))
    }

    @Test func shiftAcrossTheWeekBoundaryCountsToTheWeekItStarted() {
        let now = F.wall("2026-10-19 10:00") // Monday
        let shifts = [F.shift("2026-10-18 22:00", "2026-10-19 02:00")]
        let monday = Hours.summary(shifts: shifts, now: now, calendar: F.indy)
        #expect(monday.week == 0)
        #expect(monday.today == 0)
        #expect(monday.days == [0, 0, 0, 0, 0, 0, 0])
        let sunday = Hours.summary(shifts: shifts, now: now, calendar: F.indySunday)
        #expect(sunday.weekBounds[0] == F.wall("2026-10-18 00:00"))
        #expect(sunday.week == F.hours(4))
        #expect(sunday.days[0] == F.hours(4))
        #expect(sunday.today == 0)
    }

    @Test func daysFollowTheWeekStart() {
        let now = F.wall("2026-10-18 10:00")
        let shifts = [F.shift("2026-10-18 06:00", "2026-10-18 09:00"), F.shift("2026-10-17 06:00", "2026-10-17 07:00")]
        #expect(Hours.summary(shifts: shifts, now: now, calendar: F.indy).days == [0, 0, 0, 0, 0, F.hours(1), F.hours(3)])
        #expect(Hours.summary(shifts: shifts, now: now, calendar: F.indySunday).days == [F.hours(3), 0, 0, 0, 0, 0, 0])
    }

    @Test func springForwardWeek() {
        let now = F.wall("2026-03-10 12:00")
        let shifts = [
            F.shift("2026-03-08 08:00", "2026-03-08 12:00"),
            F.shift("2026-03-09 00:30", "2026-03-09 01:30"),
            F.shift("2026-03-07 23:00", "2026-03-08 04:00"), // 4 real hours, the night the clocks jumped
        ]
        let h = Hours.summary(shifts: shifts, now: now, calendar: F.indySunday)
        #expect(h.days[0] == F.hours(4))
        #expect(h.days[1] == F.hours(1))
        #expect(h.week == F.hours(5))
        let mon = Hours.summary(shifts: shifts, now: F.wall("2026-03-08 23:00"), calendar: F.indy)
        #expect(mon.days[5] == F.hours(4))
        #expect(mon.days[6] == F.hours(4))
        #expect(mon.today == F.hours(4))
    }

    @Test func fallBackWeek() {
        let now = F.at("2026-11-01T23:00:00-05:00")
        let shifts = [
            Shift(userId: F.userId, farmId: F.farmId, start: F.at("2026-11-01T00:30:00-04:00"), end: F.at("2026-11-01T01:30:00-05:00"), rateCents: 1500),
            F.shift("2026-10-31 23:00", "2026-10-31 23:59"),
        ]
        let h = Hours.summary(shifts: shifts, now: now, calendar: F.indy)
        #expect(h.today == F.hours(2))
        #expect(h.days[6] == F.hours(2))
        #expect(h.days[5] == F.minutes(59))
    }

    @Test func bigClockShowsTodayOrTheStaleShift() {
        let now = F.wall("2026-10-18 09:00")
        let closedToday = F.shift("2026-10-18 05:00", "2026-10-18 06:00")
        let openToday = F.shift("2026-10-18 07:00", nil)
        #expect(Hours.bigClock(shifts: [closedToday], now: now, calendar: F.indy) == F.hours(1))
        #expect(Hours.bigClock(shifts: [closedToday, openToday], now: now, calendar: F.indy) == F.hours(3))
        let stale = F.shift("2026-10-17 07:00", nil)
        #expect(Hours.bigClock(shifts: [stale], now: now, calendar: F.indy) == F.hours(26))
        #expect(Hours.bigClock(shifts: [], now: now, calendar: F.indy) == 0)
    }

    @Test(arguments: [
        (3600.0, 1500, 1500),
        (1200.0, 1550, 517),
        (60.0, 1530, 26),     // 25.5 cents rounds up
        (0.0, 1500, 0),
        (22680.0, 1500, 9450), // 6 h 18 min at $15 = $94.50
        (1.0, 1500, 0),
    ])
    func payRoundsToTheNearestCent(worked: Double, rate: Int, cents: Int) {
        #expect(Hours.payCents(for: worked, rateCents: rate) == cents)
    }

    @Test func staleMeansOpenFromAnEarlierDay() {
        let now = F.wall("2026-10-18 00:30")
        #expect(Hours.isStale(F.shift("2026-10-17 23:00", nil), now: now, calendar: F.indy))
        #expect(!Hours.isStale(F.shift("2026-10-18 00:10", nil), now: now, calendar: F.indy))
        #expect(!Hours.isStale(F.shift("2026-10-17 08:00", "2026-10-17 16:00"), now: now, calendar: F.indy))
        #expect(!Hours.isStale(F.shift("2026-10-17 23:00", nil, deleted: true), now: now, calendar: F.indy))
        // In UTC it is already the 18th at 04:30, and 23:00 Indy on the 17th is 03:00 UTC on the 18th.
        #expect(!Hours.isStale(F.shift("2026-10-17 23:00", nil), now: now, calendar: F.utc))
    }

    @Test func forgotToClockOutAfterSixteenHours() {
        let open = F.shift("2026-10-17 07:00", nil)
        #expect(!Hours.forgotToClockOut(open, now: F.wall("2026-10-17 23:00")))
        #expect(Hours.forgotToClockOut(open, now: F.wall("2026-10-17 23:00:01")))
        #expect(!Hours.forgotToClockOut(F.shift("2026-10-17 07:00", "2026-10-18 07:00"), now: F.wall("2026-10-18 09:00")))
        #expect(!Hours.forgotToClockOut(F.shift("2026-10-17 07:00", nil, deleted: true), now: F.wall("2026-10-18 09:00")))
    }
}
