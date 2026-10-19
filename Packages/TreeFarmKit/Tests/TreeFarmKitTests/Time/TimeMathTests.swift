import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Worked and break time")
struct TimeMathTests {
    typealias F = TimeFixture

    @Test func closedShiftWithoutBreaks() {
        let s = F.shift("2026-10-16 07:00", "2026-10-16 15:30")
        #expect(s.breakTime(at: F.wall("2026-10-18 12:00")) == 0)
        #expect(s.workedTime(at: F.wall("2026-10-18 12:00")) == F.hours(8.5))
    }

    @Test func closedBreaksAreNotWorked() {
        let s = F.shift("2026-10-16 07:00", "2026-10-16 15:30", breaks: [
            F.lunch("2026-10-16 12:00", "2026-10-16 12:30"),
            F.rest("2026-10-16 14:00", "2026-10-16 14:10", reason: "Fuel run"),
        ])
        #expect(s.breakTime(at: F.wall("2026-10-18 12:00")) == F.minutes(40))
        #expect(s.workedTime(at: F.wall("2026-10-18 12:00")) == F.hours(8.5) - F.minutes(40))
    }

    @Test func openShiftRunsToNow() {
        let s = F.shift("2026-10-18 07:00", nil)
        #expect(s.workedTime(at: F.wall("2026-10-18 09:15:30")) == F.hours(2) + F.minutes(15) + 30)
    }

    @Test func openBreakOnAnOpenShiftRunsToNow() {
        let lunch = F.lunch("2026-10-18 12:00", nil)
        let s = F.shift("2026-10-18 07:00", nil, breaks: [lunch])
        let now = F.wall("2026-10-18 12:20")
        #expect(lunch.duration(shiftEnd: nil, now: now) == F.minutes(20))
        #expect(s.breakTime(at: now) == F.minutes(20))
        #expect(s.workedTime(at: now) == F.hours(5))
        // Worked time is frozen while on break.
        #expect(s.workedTime(at: F.wall("2026-10-18 12:50")) == F.hours(5))
    }

    @Test func openBreakOnAClosedShiftRunsToTheShiftEnd() {
        let lunch = F.lunch("2026-10-16 12:00", nil)
        let s = F.shift("2026-10-16 07:00", "2026-10-16 12:30", breaks: [lunch])
        let now = F.wall("2026-10-18 09:00")
        #expect(lunch.duration(shiftEnd: s.end, now: now) == F.minutes(30))
        #expect(s.workedTime(at: now) == F.hours(5))
    }

    @Test func breakIsClampedToTheShift() {
        let late = F.rest("2026-10-16 15:00", "2026-10-16 17:00")
        let s = F.shift("2026-10-16 07:00", "2026-10-16 16:00", breaks: [late])
        #expect(late.duration(shiftEnd: s.end, now: F.wall("2026-10-18 09:00")) == F.hours(1))
        #expect(s.workedTime(at: F.wall("2026-10-18 09:00")) == F.hours(8))
        let early = F.shift("2026-10-16 07:00", "2026-10-16 16:00", breaks: [F.rest("2026-10-16 06:00", "2026-10-16 07:30")])
        #expect(early.breakTime(at: F.wall("2026-10-18 09:00")) == F.minutes(30))
    }

    @Test func closedBreakOnAnOpenShiftStopsAtNow() {
        let s = F.shift("2026-10-18 07:00", nil, breaks: [F.rest("2026-10-18 09:00", "2026-10-18 10:00")])
        #expect(s.breakTime(at: F.wall("2026-10-18 09:30")) == F.minutes(30))
        #expect(s.workedTime(at: F.wall("2026-10-18 09:30")) == F.hours(2))
    }

    @Test func workedTimeIsNeverNegative() {
        let overlapping = F.shift("2026-10-16 07:00", "2026-10-16 08:00", breaks: [
            F.rest("2026-10-16 07:00", "2026-10-16 08:00"),
            F.rest("2026-10-16 07:10", "2026-10-16 07:50"),
        ])
        #expect(overlapping.workedTime(at: F.wall("2026-10-18 09:00")) == 0)
        let backwards = F.shift("2026-10-16 09:00", "2026-10-16 08:00")
        #expect(backwards.workedTime(at: F.wall("2026-10-18 09:00")) == 0)
        let notYet = F.shift("2026-10-18 10:00", nil)
        #expect(notYet.workedTime(at: F.wall("2026-10-18 09:00")) == 0)
        let zero = F.shift("2026-10-16 09:00", "2026-10-16 09:00")
        #expect(zero.workedTime(at: F.wall("2026-10-18 09:00")) == 0)
    }

    @Test func shiftAcrossDSTCountsRealElapsedTime() {
        // 10 PM to 6 AM across fall-back is 9 real hours.
        let s = F.shift("2026-10-31 22:00", "2026-11-01 06:00")
        #expect(s.workedTime(at: F.wall("2026-11-02 12:00")) == F.hours(9))
    }
}
