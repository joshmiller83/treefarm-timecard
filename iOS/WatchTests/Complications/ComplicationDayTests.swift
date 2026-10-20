import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// Off the clock, "6.5 h today" belongs to the day the phone counted it. The complication's
/// timeline never expires and the phone only sends a new state on an event, so after an
/// evening clock-out the hours must turn back to "IN" at the farm's midnight by themselves.
@Suite("Complication day")
struct ComplicationDayTests {
    typealias F = ComplicationFixtures

    /// Monday's state: clocked out with 6.5 h, sent at 10:42.
    static let monday = F.offClock(todayWorked: 6.5 * 3600)

    // MARK: The state as of a moment

    @Test func yesterdaysHoursReadZeroTheNextMorning() throws {
        let tuesday = try #require(ComplicationDay.asOf(Self.monday, at: F.at(7, 0, day: 20)))
        #expect(tuesday.todayWorked == 0)
        // Nothing else changes.
        var expected = Self.monday
        expected.todayWorked = 0
        #expect(tuesday == expected)
    }

    @Test func theSameDayIsUnchanged() {
        #expect(ComplicationDay.asOf(Self.monday, at: F.at(10, 42)) == Self.monday)
        #expect(ComplicationDay.asOf(Self.monday, at: F.at(23, 59)) == Self.monday)
    }

    @Test func theDayTurnsAtTheFarmsMidnight() {
        // Midnight in Indiana, whatever zone the watch is set to.
        let midnight = F.at(0, 0, day: 20)
        #expect(ComplicationDay.asOf(Self.monday, at: midnight.addingTimeInterval(-1))?.todayWorked == 6.5 * 3600)
        #expect(ComplicationDay.asOf(Self.monday, at: midnight)?.todayWorked == 0)
    }

    @Test func onTheClockTheStateIsAsSent() {
        // The timers count from their own moments; there's nothing to roll over.
        for state in [F.working(), F.onBreak(.lunch), F.onBreak(.onBreak)] {
            #expect(ComplicationDay.asOf(state, at: F.at(7, 0, day: 20)) == state)
        }
        #expect(ComplicationDay.asOf(nil, at: F.at(7, 0, day: 20)) == nil)
    }

    @Test func aClockOutTheWatchMadeCountsOnItsOwnDay() {
        // The phone's last word was Monday evening. On Tuesday the watch clocked in and out with
        // the phone away, so its displayed state has Tuesday's hours and Monday's `updatedAt`.
        var state = F.offClock(todayWorked: 4 * 3600)
        state.updatedAt = F.at(21, 0)
        state.lastClosedShift = ClosedShift(shiftId: F.shift, start: F.at(7, 0, day: 20), end: F.at(11, 0, day: 20),
                                            worked: 4 * 3600, trees: 120)
        #expect(ComplicationDay.asOf(state, at: F.at(12, 0, day: 20)) == state)
        #expect(ComplicationDay.asOf(state, at: F.at(7, 0, day: 21))?.todayWorked == 0)
    }

    // MARK: Timeline entries

    @Test func offTheClockWithHoursASecondEntryAtTheFarmsMidnight() {
        let now = F.at(18, 5)
        let dates = ComplicationDay.entryDates(for: Self.monday, now: now)
        #expect(dates == [now, F.at(0, 0, day: 20)])
        // The farm's midnight: 9 PM on Monday in California.
        let pacific = FarmCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!, weekStart: .monday)
        #expect(dates.last == pacific.date(on: DayKey(year: 2026, month: 10, day: 19), hour: 21, minute: 0))
    }

    @Test func theMidnightEntryKeepsToTheCalendarAcrossTheClockChange() {
        // Daylight saving ends on Sunday, Nov 1 2026: Saturday's day is 25 hours long.
        var saturday = Self.monday
        saturday.updatedAt = F.at(17, 0, day: 31)
        let now = F.at(18, 0, day: 31)
        #expect(ComplicationDay.entryDates(for: saturday, now: now)
                == [now, F.calendar.startOfDay(DayKey(year: 2026, month: 11, day: 1))])
    }

    @Test func noSecondEntryWhileClockedInOrAtZeroHours() {
        let now = F.at(10, 42)
        let signedOut = WatchState.signedOut(epoch: F.epoch, revision: 1, now: now)
        let states: [WatchState?] = [F.working(), F.onBreak(.lunch), F.onBreak(.onBreak), F.offClock(todayWorked: 0),
                                     F.offClock(todayWorked: 59), signedOut, nil]
        for state in states {
            #expect(ComplicationDay.entryDates(for: state, now: now) == [now])
        }
    }

    @Test func yesterdaysHoursNeedNoMidnightEntry() {
        // A timeline built after midnight from Monday's state already reads 0.
        let now = F.at(5, 0, day: 20)
        #expect(ComplicationDay.entryDates(for: Self.monday, now: now) == [now])
    }
}
