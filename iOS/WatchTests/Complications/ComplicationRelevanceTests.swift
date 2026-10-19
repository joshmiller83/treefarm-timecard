import Foundation
import Testing
import TreeFarmKit
@testable import TimeCardWatch

/// When the Smart Stack should raise the shift widget (docs/watch.md 4.3): all shift long while
/// clocked in, and around the usual clock-in time in the morning.
@Suite("Complication relevance")
struct ComplicationRelevanceTests {
    typealias F = ComplicationFixtures
    typealias Window = ComplicationRelevance.Window

    @Test func clockedInItMattersForTenHoursFromTheShiftsStart() {
        let expected = [Window(interval: DateInterval(start: F.at(7, 1), end: F.at(17, 1)), kind: .shift)]
        #expect(ComplicationRelevance.windows(for: F.working(), now: F.at(10, 42)) == expected)
        #expect(ComplicationRelevance.windows(for: F.onBreak(.lunch), now: F.at(10, 42)) == expected)
        #expect(ComplicationRelevance.windows(for: F.onBreak(.onBreak), now: F.at(16, 0)) == expected)
    }

    @Test func aShiftWithoutAKnownStartCountsFromItsTimer() {
        var state = F.working()
        state.shiftStart = nil
        let start = state.snapshot!.timerStart
        #expect(ComplicationRelevance.windows(for: state, now: F.at(10, 42))
                == [Window(interval: DateInterval(start: start, end: start.addingTimeInterval(10 * 3600)), kind: .shift)])
    }

    @Test func offTheClockItRisesAroundTheUsualStart() {
        // Half an hour before 7:00 to an hour after, today and tomorrow.
        let early = ComplicationRelevance.windows(for: F.offClock(), now: F.at(5, 0))
        #expect(early == [Window(interval: DateInterval(start: F.at(6, 30), end: F.at(8, 0)), kind: .usualStart),
                          Window(interval: DateInterval(start: F.at(6, 30, day: 20), end: F.at(8, 0, day: 20)), kind: .usualStart)])
        // Today's window is over: only tomorrow's.
        let late = ComplicationRelevance.windows(for: F.offClock(todayWorked: 3 * 3600), now: F.at(18, 0))
        #expect(late == [Window(interval: DateInterval(start: F.at(6, 30, day: 20), end: F.at(8, 0, day: 20)), kind: .usualStart)])
        // During it, it's still today's.
        #expect(ComplicationRelevance.windows(for: F.offClock(), now: F.at(7, 10)).first?.interval.start == F.at(6, 30))
    }

    @Test func theUsualStartIsReadInTheFarmsTimeZone() {
        // 7:00 in Indiana is 4:00 in California, wherever the watch thinks it is.
        let windows = ComplicationRelevance.windows(for: F.offClock(), now: F.at(5, 0))
        let pacific = FarmCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!, weekStart: .monday)
        #expect(windows.first?.interval.start == pacific.date(on: DayKey(year: 2026, month: 10, day: 19), hour: 3, minute: 30))
    }

    @Test func theWindowKeepsItsWallClockTimeAcrossTheClockChange() {
        // Daylight saving ends on Sunday, Nov 1 2026: 7:00 is still 7:00.
        let saturday = F.calendar.date(on: DayKey(year: 2026, month: 10, day: 31), hour: 20, minute: 0)
        let windows = ComplicationRelevance.windows(for: F.offClock(), now: saturday)
        let sunday = DayKey(year: 2026, month: 11, day: 1)
        #expect(windows == [Window(interval: DateInterval(start: F.calendar.date(on: sunday, hour: 6, minute: 30),
                                                          end: F.calendar.date(on: sunday, hour: 8, minute: 0)), kind: .usualStart)])
    }

    @Test func noUsualStartNoMorningWindow() {
        // Fewer than 3 shifts so far: the phone sends no usual start.
        #expect(ComplicationRelevance.windows(for: F.offClock(usualStart: nil), now: F.at(5, 0)).isEmpty)
        #expect(ComplicationRelevance.windows(for: F.offClock(usualStart: DateComponents(hour: 7)), now: F.at(5, 0)).count == 2)
    }

    @Test func signedOutOrNeverConnectedNeverRises() {
        #expect(ComplicationRelevance.windows(for: nil, now: F.at(5, 0)).isEmpty)
        var signedOut = WatchState.signedOut(epoch: F.epoch, revision: 1, now: F.at(5, 0))
        signedOut.usualStart = DateComponents(hour: 7, minute: 0)
        #expect(ComplicationRelevance.windows(for: signedOut, now: F.at(5, 0)).isEmpty)
    }
}
