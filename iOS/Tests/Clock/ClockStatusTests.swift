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

    @Test func aBreakOfAFewSecondsIsNotZeroMinutes() {
        let open = f.shift(f.today(7, 0), breaks: [Break(kind: .lunch, start: f.today(8, 0), end: f.today(8, 0, 10))])
        let s = ClockStatus(state: f.state(shifts: [open]), now: f.today(9, 0))
        #expect(s.meta == ["Clocked in 7:00 AM · Breaks under 1 min"])
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
        // 7:00 AM alone would read as later today.
        #expect(s.meta == ["Clocked in Tue, Oct 13 at 7:00 AM · No breaks yet"])
    }

    @Test func theBigClockTicksOnFromOneReading() {
        let open = f.shift(f.today(7, 0))
        let state = f.state(shifts: [open])
        let read: Date = f.today(9, 0).addingTimeInterval(0.25)
        let later: Date = f.today(9, 1)
        let s = ClockStatus(state: state, now: read)
        let full: TimeInterval = ClockStatus.worked(state: state, now: later)
        #expect(s.bigClock(at: later) == full)
        let tick: Date = f.today(9, 0).addingTimeInterval(1)
        #expect(s.nextWholeSecond == tick)
    }

    @Test func tapAgainWaitsLongerForAssistiveTech() {
        #expect(ClockOutTap.timeout(assistiveTech: false) == 5)
        #expect(ClockOutTap.timeout(assistiveTech: true) == 30)
    }

    @Test func aShiftOpenPastADayNeedsItsClockOutFixed() {
        let open = f.shift(f.at(f.day(-1), 7, 0))
        #expect(!ClockStatus(state: f.state(shifts: [open]), now: f.today(6, 59)).needsClockOutFix)
        let s = ClockStatus(state: f.state(shifts: [open]), now: f.today(7, 1))
        #expect(s.needsClockOutFix)
        #expect(s.stale != nil)
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
struct PickedStartTimeTests {
    let f = ClockFixture()

    func newStart(_ picked: Date, from original: Date) -> Date {
        PickedStartTime.newStart(picked: picked, original: original, calendar: f.calendar)
    }

    @Test func anUnchangedTimeKeepsTheExactStart() {
        let original = f.today(7, 2, 41)
        #expect(newStart(f.today(7, 2), from: original) == original)
    }

    @Test func aNewTimeLandsOnTheShiftsDayInTheFarmsZone() {
        let original = f.at(f.day(-1), 7, 2, 41)
        #expect(newStart(f.today(6, 30, 15), from: original) == f.at(f.day(-1), 6, 30))
    }

    @Test func flippingAmToPmStaysOnTheSameDay() {
        // One flick of the AM/PM wheel is 12 hours either way; it never means yesterday evening.
        #expect(newStart(f.today(19, 0), from: f.today(7, 0)) == f.today(19, 0))
        #expect(newStart(f.today(7, 0), from: f.today(19, 0)) == f.today(7, 0))
        #expect(newStart(f.today(23, 0), from: f.today(11, 0)) == f.today(23, 0))
        #expect(newStart(f.today(1, 0), from: f.today(13, 0)) == f.today(1, 0))
    }

    @Test func justAfterMidnightAnEveningTimeMeansTheNightBefore() {
        let original = f.today(0, 5)
        #expect(newStart(f.today(23, 50), from: original) == f.at(f.day(-1), 23, 50))
        #expect(newStart(f.today(21, 0), from: original) == f.at(f.day(-1), 21, 0))
        #expect(newStart(f.today(0, 1), from: original) == f.today(0, 1))
        // Outside the three hours around midnight it's the same day.
        #expect(newStart(f.today(20, 59), from: original) == f.today(20, 59))
        #expect(newStart(f.today(23, 50), from: f.today(3, 0)) == f.today(23, 50))
    }

    @Test func justBeforeMidnightAnEarlyTimeMeansTheNextMorning() {
        let original = f.today(23, 58)
        #expect(newStart(f.today(0, 3), from: original) == f.at(f.day(1), 0, 3))
        #expect(newStart(f.today(22, 0), from: original) == f.today(22, 0))
        #expect(newStart(f.today(3, 0), from: original) == f.today(3, 0))
    }

    @Test func theSheetSaysWhichDayAndHowFar() {
        let original = f.today(7, 0)
        #expect(PickedStartTime.preview(start: f.today(19, 0), original: original, calendar: f.calendar)
                == "Wed, Oct 14 at 7:00 PM · 12 h later")
        #expect(PickedStartTime.preview(start: f.today(6, 45), original: original, calendar: f.calendar)
                == "Wed, Oct 14 at 6:45 AM · 15 min earlier")
        #expect(PickedStartTime.preview(start: f.at(f.day(-1), 23, 50), original: f.today(0, 5), calendar: f.calendar)
                == "Tue, Oct 13 at 11:50 PM · 15 min earlier")
        #expect(PickedStartTime.preview(start: original, original: original, calendar: f.calendar)
                == "Wed, Oct 14 at 7:00 AM · no change")
        // Clocked in at 7:12:40; five minutes on the wheel reads as five minutes.
        let withSeconds = f.today(7, 12, 40)
        #expect(PickedStartTime.preview(start: f.today(7, 17), original: withSeconds, calendar: f.calendar)
                == "Wed, Oct 14 at 7:17 AM · 5 min later")
        #expect(PickedStartTime.preview(start: withSeconds, original: withSeconds, calendar: f.calendar)
                == "Wed, Oct 14 at 7:12 AM · no change")
    }
}

@Suite("Clock out asks twice")
struct ClockOutTapTests {
    let t = Date(timeIntervalSince1970: 1_792_000_000)

    @Test func theFirstTapAsks() {
        #expect(ClockOutTap.decide(armedAt: nil, now: t) == .arm)
    }

    @Test func aBouncyDoubleTapDoesntEndTheShift() {
        #expect(ClockOutTap.decide(armedAt: t, now: t.addingTimeInterval(0.15)) == .ignore)
        #expect(ClockOutTap.decide(armedAt: t, now: t.addingTimeInterval(0.59)) == .ignore)
    }

    @Test func aDeliberateSecondTapClocksOut() {
        #expect(ClockOutTap.decide(armedAt: t, now: t.addingTimeInterval(0.6)) == .confirm)
        #expect(ClockOutTap.decide(armedAt: t, now: t.addingTimeInterval(3)) == .confirm)
    }
}
