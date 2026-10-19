import Foundation
import Testing
@testable import TreeFarmKit

@Suite("ShiftRules: shift times")
struct ShiftRulesTimeTests {
    typealias F = TimeFixture
    let now = F.wall("2026-10-18 10:00")

    func check(_ s: Shift, others: [Shift] = [], skew: TimeInterval = 0) -> ShiftRuleError? {
        ShiftRules.validate(s, others: others, now: now, calendar: F.indy, skew: skew)
    }

    @Test func aNormalShiftPasses() {
        #expect(check(F.shift("2026-10-16 07:00", "2026-10-16 15:30", breaks: [F.lunch("2026-10-16 12:00", "2026-10-16 12:30")])) == nil)
        #expect(check(F.shift("2026-10-18 07:00", nil)) == nil)
    }

    @Test func clockOutMustBeAfterClockIn() {
        #expect(check(F.shift("2026-10-16 15:00", "2026-10-16 07:00")) == .endNotAfterStart)
        #expect(check(F.shift("2026-10-16 07:00", "2026-10-16 07:00")) == .endNotAfterStart)
        #expect(ShiftRuleError.endNotAfterStart.message == "Clock out has to be after clock in.")
    }

    @Test func aShiftPastMidnightIsFine() {
        #expect(check(F.shift("2026-10-16 20:00", "2026-10-17 02:00")) == nil)
    }

    @Test func startCantBeInTheFuture() {
        #expect(check(F.shift("2026-10-18 10:00:01", nil)) == .startInFuture)
        #expect(check(F.shift("2026-10-18 10:04", nil), skew: Limits.clockSkew) == nil)
        #expect(check(F.shift("2026-10-18 10:06", nil), skew: Limits.clockSkew) == .startInFuture)
        #expect(check(F.shift("2026-10-19 07:00", "2026-10-19 15:00")) == .startInFuture)
        #expect(ShiftRuleError.startInFuture.message == "Clock in can’t be later than right now.")
    }

    @Test func endCantBeInTheFuture() {
        #expect(check(F.shift("2026-10-18 07:00", "2026-10-18 11:00")) == .endInFuture)
        #expect(check(F.shift("2026-10-18 07:00", "2026-10-18 10:03"), skew: Limits.clockSkew) == nil)
        #expect(ShiftRuleError.endInFuture.message == "Clock out can’t be later than right now.")
    }

    @Test func aClosedShiftCantRunPast24Hours() {
        #expect(check(F.shift("2026-10-15 07:00", "2026-10-16 07:00")) == nil)
        #expect(check(F.shift("2026-10-15 07:00", "2026-10-16 07:01")) == .tooLong)
        #expect(ShiftRuleError.tooLong.message == "A shift can’t be longer than 24 hours. Check the clock-in and clock-out times.")
        // An open shift can be on the clock for days; that's a stale-shift warning, not an error.
        #expect(check(F.shift("2026-10-15 07:00", nil)) == nil)
    }

    @Test func onlyOneOpenShift() {
        let open = F.shift("2026-10-18 07:00", nil)
        #expect(check(F.shift("2026-10-18 09:00", nil), others: [open]) == .alreadyClockedIn)
        #expect(ShiftRuleError.alreadyClockedIn.message == "You’re already clocked in on another shift. Add a clock-out time to this one.")
        // The same shift being edited isn't "another" shift.
        #expect(check(F.shift("2026-10-18 06:30", nil, id: open.id), others: [open]) == nil)
        #expect(check(F.shift("2026-10-18 09:00", nil), others: [F.shift("2026-10-18 07:00", nil, deleted: true)]) == nil)
        #expect(check(F.shift("2026-10-18 09:00", nil), others: [F.shift("2026-10-18 07:00", nil, user: F.otherUserId)]) == nil)
    }

    @Test func shiftsCantOverlap() {
        let mon = F.shift("2026-10-12 07:00", "2026-10-12 15:30")
        let error = check(F.shift("2026-10-12 15:00", "2026-10-12 18:00"), others: [mon])
        #expect(error == .overlaps(day: "Mon, Oct 12", from: "7:00 AM", to: "3:30 PM"))
        #expect(error?.message == "This overlaps your shift on Mon, Oct 12 from 7:00 AM to 3:30 PM. Change the times or edit that shift.")
        #expect(check(F.shift("2026-10-12 06:00", "2026-10-12 16:00"), others: [mon]) != nil)
        #expect(check(F.shift("2026-10-12 08:00", "2026-10-12 09:00"), others: [mon]) != nil)
    }

    @Test func touchingShiftsDontOverlap() {
        let mon = F.shift("2026-10-12 07:00", "2026-10-12 15:30")
        #expect(check(F.shift("2026-10-12 15:30", "2026-10-12 18:00"), others: [mon]) == nil)
        #expect(check(F.shift("2026-10-12 05:00", "2026-10-12 07:00"), others: [mon]) == nil)
    }

    @Test func overlapWithTheOpenShiftRunsToNow() {
        let open = F.shift("2026-10-18 07:00", nil)
        let error = check(F.shift("2026-10-18 08:00", "2026-10-18 09:00"), others: [open])
        #expect(error == .overlaps(day: "Sun, Oct 18", from: "7:00 AM", to: "now"))
        #expect(check(F.shift("2026-10-18 05:00", "2026-10-18 07:00"), others: [open]) == nil)
        // An open shift starting inside a closed one overlaps it.
        let closed = F.shift("2026-10-18 06:00", "2026-10-18 09:00")
        #expect(check(F.shift("2026-10-18 08:00", nil), others: [closed]) == .overlaps(day: "Sun, Oct 18", from: "6:00 AM", to: "9:00 AM"))
    }

    @Test func deletedAndOtherPeoplesShiftsDontOverlap() {
        let gone = F.shift("2026-10-12 07:00", "2026-10-12 15:30", deleted: true)
        let sams = F.shift("2026-10-12 07:00", "2026-10-12 15:30", user: F.otherUserId)
        #expect(check(F.shift("2026-10-12 08:00", "2026-10-12 12:00"), others: [gone, sams]) == nil)
    }

    @Test func aDeletedShiftIsAlwaysValid() {
        #expect(check(F.shift("2026-10-16 15:00", "2026-10-16 07:00", deleted: true)) == nil)
    }
}

@Suite("ShiftRules: breaks")
struct ShiftRulesBreakTests {
    typealias F = TimeFixture
    let now = F.wall("2026-10-18 10:00")

    func check(_ s: Shift, skew: TimeInterval = 0) -> ShiftRuleError? {
        ShiftRules.validate(s, others: [], now: now, calendar: F.indy, skew: skew)
    }

    func friday(_ breaks: [Break]) -> Shift {
        F.shift("2026-10-16 07:00", "2026-10-16 15:30", breaks: breaks)
    }

    @Test func aBreakMustEndAfterItStarts() {
        #expect(check(friday([F.lunch("2026-10-16 12:30", "2026-10-16 12:00")])) == .breakEndNotAfterStart(1))
        #expect(check(friday([F.lunch("2026-10-16 12:00", "2026-10-16 12:00")])) == .breakEndNotAfterStart(1))
        #expect(ShiftRuleError.breakEndNotAfterStart(1).message == "Break 1 has to end after it starts.")
    }

    @Test func aClosedShiftNeedsClosedBreaks() {
        let s = friday([F.lunch("2026-10-16 12:00", "2026-10-16 12:30"), F.rest("2026-10-16 14:00", nil)])
        #expect(check(s) == .breakNeedsEnd(2))
        #expect(ShiftRuleError.breakNeedsEnd(2).message == "Break 2 needs an end time.")
    }

    @Test func breaksStayInsideTheShift() {
        #expect(check(friday([F.rest("2026-10-16 06:30", "2026-10-16 07:15")])) == .breakOutsideShift(1))
        #expect(check(friday([F.rest("2026-10-16 15:00", "2026-10-16 15:45")])) == .breakOutsideShift(1))
        #expect(check(friday([F.rest("2026-10-16 07:00", "2026-10-16 07:15"), F.rest("2026-10-16 15:15", "2026-10-16 15:30")])) == nil)
        #expect(ShiftRuleError.breakOutsideShift(1).message == "Break 1 has to fall inside the shift.")
    }

    @Test func anOpenShiftsBreaksCantBeInTheFuture() {
        let future = F.shift("2026-10-18 07:00", nil, breaks: [F.lunch("2026-10-18 10:01", nil)])
        #expect(check(future) == .breakOutsideShift(1))
        #expect(check(future, skew: Limits.clockSkew) == nil)
        let endsLater = F.shift("2026-10-18 07:00", nil, breaks: [F.lunch("2026-10-18 09:30", "2026-10-18 10:10")])
        #expect(check(endsLater, skew: Limits.clockSkew) == .breakOutsideShift(1))
        #expect(check(F.shift("2026-10-18 07:00", nil, breaks: [F.lunch("2026-10-18 09:30", nil)])) == nil)
    }

    @Test func onlyTheLatestBreakCanBeOpen() {
        let s = F.shift("2026-10-18 07:00", nil, breaks: [F.rest("2026-10-18 08:00", nil), F.rest("2026-10-18 09:00", "2026-10-18 09:10")])
        #expect(check(s) == .onlyLatestBreakOpen)
        #expect(ShiftRuleError.onlyLatestBreakOpen.message == "Only the latest break can be left open.")
        let two = F.shift("2026-10-18 07:00", nil, breaks: [F.rest("2026-10-18 08:00", nil), F.rest("2026-10-18 09:00", nil)])
        #expect(check(two) == .onlyLatestBreakOpen)
    }

    @Test func breaksCantOverlap() {
        let s = friday([F.lunch("2026-10-16 12:00", "2026-10-16 12:30"), F.rest("2026-10-16 12:15", "2026-10-16 12:45")])
        #expect(check(s) == .breaksOverlap)
        #expect(ShiftRuleError.breaksOverlap.message == "Two breaks overlap. Fix their times.")
        #expect(check(friday([F.lunch("2026-10-16 12:00", "2026-10-16 12:30"), F.rest("2026-10-16 12:30", "2026-10-16 12:40")])) == nil)
    }

    @Test func breaksAreCheckedInTimeOrderButNumberedAsGiven() {
        #expect(check(friday([F.rest("2026-10-16 14:00", "2026-10-16 14:10"), F.lunch("2026-10-16 12:00", "2026-10-16 12:30")])) == nil)
        #expect(check(friday([F.lunch("2026-10-16 12:00", "2026-10-16 12:30"), F.rest("2026-10-16 16:00", "2026-10-16 16:10")])) == .breakOutsideShift(2))
    }

    @Test func shiftProblemsComeBeforeBreakProblems() {
        let s = F.shift("2026-10-16 15:00", "2026-10-16 07:00", breaks: [F.lunch("2026-10-16 12:30", "2026-10-16 12:00")])
        #expect(check(s) == .endNotAfterStart)
    }
}

@Suite("ShiftRules: normalized")
struct ShiftRulesNormalizeTests {
    typealias F = TimeFixture

    @Test func sortsBreaksAndClampsText() {
        let long = String(repeating: "r", count: 100)
        let s = F.shift("2026-10-16 07:00", "2026-10-16 15:30", breaks: [
            F.rest("2026-10-16 14:00", "2026-10-16 14:10", reason: "  " + long),
            F.lunch("2026-10-16 12:00", "2026-10-16 12:30", reason: " Lunch "),
        ], notes: "  " + String(repeating: "n", count: 2500))
        let n = ShiftRules.normalized(s)
        #expect(n.breaks.map(\.start) == [F.wall("2026-10-16 12:00"), F.wall("2026-10-16 14:00")])
        #expect(n.breaks[0].reason == "Lunch")
        #expect(n.breaks[1].reason.count == Limits.reason)
        #expect(n.notes.count == Limits.notes)
        #expect(n.notes.first == "n")
        #expect(n.id == s.id && n.start == s.start && n.end == s.end && n.updatedAt == s.updatedAt)
        #expect(ShiftRules.normalized(n) == n)
    }
}
