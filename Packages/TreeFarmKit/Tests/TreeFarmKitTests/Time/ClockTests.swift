import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Clock")
struct ClockTests {
    typealias F = TimeFixture

    @Test func openShiftIsTheLatestLiveOpenOne() {
        let old = F.shift("2026-10-17 07:00", nil)
        let newer = F.shift("2026-10-18 07:00", nil)
        let gone = F.shift("2026-10-18 08:00", nil, deleted: true)
        let closed = F.shift("2026-10-18 09:00", "2026-10-18 09:30")
        #expect(Clock.openShift(in: [old, newer, gone, closed]) == newer)
        #expect(Clock.openShift(in: [gone, closed]) == nil)
        #expect(Clock.openShift(in: []) == nil)
    }

    @Test func clockInStartsAShiftNow() throws {
        let now = F.wall("2026-10-18 07:02")
        let s = try Clock.clockIn(userId: F.userId, farmId: F.farmId, rateCents: 1575, at: now, shifts: [])
        #expect(s.userId == F.userId && s.farmId == F.farmId)
        #expect(s.start == now && s.end == nil)
        #expect(s.breaks.isEmpty && s.notes.isEmpty)
        #expect(s.rateCents == 1575)
        #expect(s.updatedAt == now)
        #expect(s.isLive)
        #expect(ShiftRules.validate(s, others: [], now: now, calendar: F.indy) == nil)
    }

    @Test func clockInTwiceIsRefused() {
        let open = F.shift("2026-10-18 07:00", nil)
        #expect(throws: ClockError.alreadyClockedIn(open)) {
            try Clock.clockIn(userId: F.userId, farmId: F.farmId, rateCents: 1500, at: F.wall("2026-10-18 08:00"), shifts: [open])
        }
        #expect(ClockError.alreadyClockedIn(open).message == "You’re already clocked in.")
    }

    @Test func otherPeoplesAndDeletedShiftsDontBlockClockIn() throws {
        let sams = F.shift("2026-10-18 07:00", nil, user: F.otherUserId)
        let gone = F.shift("2026-10-18 07:00", nil, deleted: true)
        let s = try Clock.clockIn(userId: F.userId, farmId: F.farmId, rateCents: 1500, at: F.wall("2026-10-18 08:00"), shifts: [sams, gone])
        #expect(s.isOpen)
    }

    @Test func startAndEndABreak() throws {
        let shift = F.shift("2026-10-18 07:00", nil)
        let t1 = F.wall("2026-10-18 12:01")
        let onLunch = try Clock.startBreak(.lunch, reason: "  ", at: t1, in: shift)
        #expect(onLunch.breaks.count == 1)
        #expect(onLunch.openBreak?.kind == .lunch)
        #expect(onLunch.openBreak?.start == t1)
        #expect(onLunch.openBreak?.reason == "")
        #expect(onLunch.updatedAt == t1)
        let t2 = F.wall("2026-10-18 12:31")
        let back = try Clock.endBreak(at: t2, in: onLunch)
        #expect(back.openBreak == nil)
        #expect(back.breaks[0].end == t2)
        #expect(back.updatedAt == t2)
        #expect(back.workedTime(at: F.wall("2026-10-18 13:00")) == F.hours(5.5))
    }

    @Test func breakReasonsAreTrimmedAndClamped() throws {
        let shift = F.shift("2026-10-18 07:00", nil)
        let s = try Clock.startBreak(.break, reason: " Fuel run " + String(repeating: "x", count: 100), at: F.wall("2026-10-18 09:00"), in: shift)
        #expect(s.breaks[0].reason.hasPrefix("Fuel run"))
        #expect(s.breaks[0].reason.count == Limits.reason)
    }

    @Test func breaksNeedAnOpenShift() {
        let closed = F.shift("2026-10-18 07:00", "2026-10-18 09:00")
        #expect(throws: ClockError.notClockedIn) { try Clock.startBreak(.lunch, reason: "", at: F.wall("2026-10-18 09:30"), in: closed) }
        #expect(throws: ClockError.notClockedIn) { try Clock.endBreak(at: F.wall("2026-10-18 09:30"), in: closed) }
        let gone = F.shift("2026-10-18 07:00", nil, deleted: true)
        #expect(throws: ClockError.notClockedIn) { try Clock.startBreak(.lunch, reason: "", at: F.wall("2026-10-18 09:30"), in: gone) }
        #expect(ClockError.notClockedIn.message == "You’re not clocked in.")
    }

    @Test func oneBreakAtATime() throws {
        let lunch = F.lunch("2026-10-18 12:00", nil)
        let shift = F.shift("2026-10-18 07:00", nil, breaks: [lunch])
        #expect(throws: ClockError.alreadyOnBreak(lunch)) { try Clock.startBreak(.break, reason: "", at: F.wall("2026-10-18 12:10"), in: shift) }
        #expect(ClockError.alreadyOnBreak(lunch).message == "You’re already on lunch.")
        #expect(ClockError.alreadyOnBreak(F.rest("2026-10-18 12:00", nil)).message == "You’re already on a break.")
    }

    @Test func endBreakNeedsABreak() {
        let shift = F.shift("2026-10-18 07:00", nil, breaks: [F.lunch("2026-10-18 12:00", "2026-10-18 12:30")])
        #expect(throws: ClockError.notOnBreak) { try Clock.endBreak(at: F.wall("2026-10-18 13:00"), in: shift) }
        #expect(ClockError.notOnBreak.message == "You’re not on a break.")
    }

    @Test func clockOutEndsTheShift() throws {
        let shift = F.shift("2026-10-18 07:00", nil, breaks: [F.lunch("2026-10-18 12:00", "2026-10-18 12:30")])
        let t = F.wall("2026-10-18 16:31")
        let out = try Clock.clockOut(at: t, shift: shift)
        #expect(out.end == t)
        #expect(out.updatedAt == t)
        #expect(out.workedTime(at: F.wall("2026-10-19 09:00")) == F.hours(9) + F.minutes(1))
        #expect(ShiftRules.validate(out, others: [], now: t, calendar: F.indy) == nil)
    }

    @Test func clockOutClosesAnOpenBreakAtTheSameInstant() throws {
        let shift = F.shift("2026-10-18 07:00", nil, breaks: [F.rest("2026-10-18 15:50", nil, reason: "Rain")])
        let t = F.wall("2026-10-18 16:00")
        let out = try Clock.clockOut(at: t, shift: shift)
        #expect(out.breaks[0].end == t)
        #expect(out.end == t)
        #expect(out.openBreak == nil)
        #expect(ShiftRules.validate(out, others: [], now: t, calendar: F.indy) == nil)
    }

    @Test func clockOutNeedsAnOpenShift() {
        let closed = F.shift("2026-10-18 07:00", "2026-10-18 09:00")
        #expect(throws: ClockError.notClockedIn) { try Clock.clockOut(at: F.wall("2026-10-18 10:00"), shift: closed) }
    }

    @Test func breakLinesDescribeEachBreak() {
        let closed = F.shift("2026-10-16 07:00", "2026-10-16 15:30", breaks: [
            F.lunch("2026-10-16 12:00", "2026-10-16 12:30"),
            F.rest("2026-10-16 14:00", "2026-10-16 14:12", reason: "Fuel run"),
            F.rest("2026-10-16 08:00", "2026-10-16 09:05"),
        ])
        #expect(Clock.breakLines(closed, now: F.wall("2026-10-18 09:00")) == ["Lunch 30 min", "Break 12 min (Fuel run)", "Break 1 h 5 min"])
    }

    @Test func anOpenBreakSaysSoFar() {
        let open = F.shift("2026-10-18 07:00", nil, breaks: [F.rest("2026-10-18 09:00", nil, reason: "Sharpening")])
        #expect(Clock.breakLines(open, now: F.wall("2026-10-18 09:05")) == ["Break 5 min (Sharpening) so far"])
        // On a closed shift an open break runs to the shift end and isn't "so far".
        let closed = F.shift("2026-10-16 07:00", "2026-10-16 12:20", breaks: [F.lunch("2026-10-16 12:00", nil)])
        #expect(Clock.breakLines(closed, now: F.wall("2026-10-18 09:00")) == ["Lunch 20 min"])
    }
}
