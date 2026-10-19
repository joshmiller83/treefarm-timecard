import Foundation
import Testing
@testable import TreeFarmKit

/// A whole day on the clock through the public API, the way the app and Siri will drive it.
@Suite("A day on the clock")
struct TimeScenarioTests {
    typealias F = TimeFixture

    @Test func clockInLunchBreakClockOut() throws {
        let farm = Farm(id: F.farmId, name: "Dull's Tree Farm", timeZoneId: "America/Indiana/Indianapolis", weekStart: .monday)
        let cal = FarmCalendar(farm: farm)
        let earlier = F.shift("2026-10-16 07:00", "2026-10-16 15:00")
        var mine = [earlier]

        let tIn = F.wall("2026-10-18 07:02")
        var shift = try Clock.clockIn(userId: F.userId, farmId: farm.id, rateCents: 1500, at: tIn, shifts: mine)
        #expect("Clocked in at \(Fmt.spokenTime(tIn, cal))." == "Clocked in at 7:02.")
        #expect(ShiftRules.validate(shift, others: mine, now: tIn, calendar: cal, skew: Limits.clockSkew) == nil)

        shift = try Clock.startBreak(.lunch, reason: "", at: F.wall("2026-10-18 12:01"), in: shift)
        #expect(Hours.bigClock(shifts: mine + [shift], now: F.wall("2026-10-18 12:20"), calendar: cal) == F.hours(5) - 60)
        let tBack = F.wall("2026-10-18 12:31")
        shift = try Clock.endBreak(at: tBack, in: shift)
        #expect("Back at \(Fmt.spokenTime(tBack, cal)). Lunch was \(Fmt.spokenDuration(shift.breaks[0].duration(shiftEnd: nil, now: tBack)))." == "Back at 12:31. Lunch was 30 minutes.")

        shift = try Clock.startBreak(.break, reason: "Fuel run", at: F.wall("2026-10-18 14:00"), in: shift)
        #expect(Clock.breakLines(shift, now: F.wall("2026-10-18 14:05")) == ["Lunch 30 min", "Break 5 min (Fuel run) so far"])
        shift = try Clock.endBreak(at: F.wall("2026-10-18 14:12"), in: shift)

        let tOut = F.wall("2026-10-18 16:31")
        shift = try Clock.clockOut(at: tOut, shift: shift)
        mine.append(shift)
        let worked = shift.workedTime(at: tOut)
        #expect(worked == F.hours(8) + F.minutes(47))
        #expect(Fmt.decimalHours(worked) == "8.78")
        #expect(Fmt.spokenDuration(worked) == "8 hours 47 minutes")
        #expect(Fmt.usd(cents: Hours.payCents(for: worked, rateCents: shift.rateCents)) == "$131.75")
        #expect(ShiftRules.validate(shift, others: mine, now: tOut, calendar: cal, skew: Limits.clockSkew) == nil)

        let hours = Hours.summary(shifts: mine, now: tOut, calendar: cal)
        #expect(hours.today == worked)
        #expect(hours.week == worked + F.hours(8))
        #expect(Fmt.rangeLabel(start: hours.weekBounds[0], endExclusive: hours.weekBounds[7], cal) == "Oct 12 – Oct 18, 2026")

        let report = Report.build(shifts: mine, period: .thisWeek, now: tOut, calendar: cal) { _ in 0 }
        #expect(report.rows.count == 2)
        #expect(report.daysWorked == 2)
        #expect(Fmt.hmWords(report.totalWorked) == "16 h 47 min")

        #expect(throws: ClockError.notClockedIn) { try Clock.clockOut(at: F.wall("2026-10-18 17:00"), shift: shift) }
        let next = try Clock.clockIn(userId: F.userId, farmId: farm.id, rateCents: 1500, at: F.wall("2026-10-18 17:00"), shifts: mine)
        #expect(next.isOpen)
    }
}
