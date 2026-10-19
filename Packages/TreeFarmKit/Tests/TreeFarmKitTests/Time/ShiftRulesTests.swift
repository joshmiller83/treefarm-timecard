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
