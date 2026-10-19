import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Clock status card")
struct ClockStatusTests {
    let f = ClockFixture()

    @Test func offTheClockWithNothingToday() {
        let s = ClockStatus(state: f.state(), now: f.today(6, 45))
        #expect(s.phase == .off)
        #expect(s.pill == "Off the clock")
        #expect(s.dateText == "Wednesday, Oct 14")
        #expect(s.worked == 0)
        #expect(s.workedLabel == "worked today")
        #expect(s.meta == ["Not clocked in yet today."])
        #expect(s.shiftId == nil)
        #expect(s.stale == nil)
    }

    @Test func offTheClockAfterAShiftSaysWhenYouLeft() {
        let done = f.shift(f.today(7, 0), f.today(15, 30), breaks: [Break(kind: .lunch, start: f.today(12, 0), end: f.today(12, 30))])
        let s = ClockStatus(state: f.state(shifts: [done]), now: f.today(17, 0))
        #expect(s.phase == .off)
        #expect(s.worked == 8 * 3600)
        #expect(s.meta == ["Last clocked out at 3:30 PM."])
    }

    @Test func yesterdaysShiftDoesNotCountToday() {
        let yesterday = f.shift(f.at(f.day(-1), 7, 0), f.at(f.day(-1), 15, 0))
        let s = ClockStatus(state: f.state(shifts: [yesterday]), now: f.today(8, 0))
        #expect(s.worked == 0)
        #expect(s.meta == ["Not clocked in yet today."])
    }

    @Test func workingShowsWhenYouStartedAndYourBreaks() {
        let open = f.shift(f.today(7, 2))
        var s = ClockStatus(state: f.state(shifts: [open]), now: f.today(9, 2, 30))
        #expect(s.phase == .working)
        #expect(s.pill == "On the clock")
        #expect(s.shiftId == open.id)
        #expect(s.worked == 2 * 3600 + 30)
        #expect(s.workedLabel == "worked today")
        #expect(s.meta == ["Clocked in 7:02 AM · No breaks yet"])

        let withBreak = f.shift(f.today(7, 2), breaks: [Break(kind: .break, start: f.today(8, 0), end: f.today(8, 12), reason: "Fuel run")], id: open.id)
        s = ClockStatus(state: f.state(shifts: [withBreak]), now: f.today(9, 2))
        #expect(s.meta == ["Clocked in 7:02 AM · Breaks 12 min"])
        #expect(s.worked == 2 * 3600 - 12 * 60)
    }

    @Test func onLunchTheClockStopsAndTheBreakIsNamed() {
        let open = f.shift(f.today(7, 0), breaks: [Break(kind: .lunch, start: f.today(12, 1))])
        let s = ClockStatus(state: f.state(shifts: [open]), now: f.today(12, 20))
        #expect(s.phase == .onBreak(.lunch))
        #expect(s.pill == "On lunch")
        #expect(s.workedLabel == "worked today · paused while you’re on lunch")
        #expect(s.breakLine == "Lunch started 12:01 PM")
        #expect(s.breakStart == f.today(12, 1))
        #expect(s.meta == ["Clocked in 7:00 AM"])
        #expect(s.worked == 5 * 3600 + 60)
        #expect(ClockStatus.worked(state: f.state(shifts: [open]), now: f.today(12, 50)) == s.worked)
    }

    @Test func onABreakTheReasonShows() {
        let open = f.shift(f.today(7, 0), breaks: [Break(kind: .break, start: f.today(10, 0), reason: "Fuel run")])
        let s = ClockStatus(state: f.state(shifts: [open]), now: f.today(10, 5))
        #expect(s.phase == .onBreak(.break))
        #expect(s.pill == "On break")
        #expect(s.workedLabel == "worked today · paused while you’re on break")
        #expect(s.breakLine == "Break started 10:00 AM · Fuel run")
    }

    @Test func aShiftLeftOpenFromYesterdayIsFlagged() {
        let open = f.shift(f.at(f.day(-1), 7, 0))
        let s = ClockStatus(state: f.state(shifts: [open]), now: f.today(6, 30))
        #expect(s.phase == .working)
        #expect(s.workedLabel == "worked this shift")
        #expect(s.worked == 23.5 * 3600)
        #expect(s.stale == "You’ve been clocked in since Tue, Oct 13 at 7:00 AM.")
    }

    @Test func aShiftOpenMoreThanSixteenHoursIsFlaggedToo() {
        let open = f.shift(f.today(0, 30))
        let fine = ClockStatus(state: f.state(shifts: [open]), now: f.today(16, 0))
        #expect(fine.stale == nil)
        let s = ClockStatus(state: f.state(shifts: [open]), now: f.today(16, 45))
        #expect(s.workedLabel == "worked today")
        #expect(s.stale == "You’ve been clocked in since Wed, Oct 14 at 12:30 AM.")
    }

    @Test func otherPeoplesAndDeletedShiftsDontCount() {
        var gone = f.shift(f.today(7, 0))
        gone.deletedAt = f.today(8, 0)
        let s = ClockStatus(state: f.state(shifts: [gone]), now: f.today(9, 0))
        #expect(s.phase == .off)
        #expect(s.worked == 0)
    }
}

@Suite("Changing the start time")
struct StartTimeTests {
    let f = ClockFixture()

    @Test func anUnchangedTimeKeepsTheExactStart() {
        let original = f.today(7, 2, 41)
        #expect(StartTime.newStart(picked: f.today(7, 2), original: original, calendar: f.calendar) == original)
    }

    @Test func aNewTimeLandsOnTheShiftsDayInTheFarmsZone() {
        let original = f.at(f.day(-1), 7, 2, 41)
        let picked = f.today(6, 30, 15)
        #expect(StartTime.newStart(picked: picked, original: original, calendar: f.calendar) == f.at(f.day(-1), 6, 30))
    }
}
