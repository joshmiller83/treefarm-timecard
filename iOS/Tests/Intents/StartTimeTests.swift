import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// "I started at 7:30": Siri hands over a time; the shift needs the moment it means.
@Suite("Spoken start times")
struct StartTimeTests {
    let farm = FarmCalendar(timeZone: TimeZone(identifier: "America/Indiana/Indianapolis")!, weekStart: .monday)

    func at(_ day: Int, _ hour: Int, _ minute: Int, _ cal: FarmCalendar? = nil) -> Date {
        let c = cal ?? farm
        return c.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func theLatestPastTimeOnTheDial() {
        let now = at(18, 9, 0)
        #expect(StartTime.latest(hour: 7, minute: 30, atOrBefore: now, calendar: farm) == at(18, 7, 30))
        // Siri may have heard "7:30" as the evening; it's still this morning.
        #expect(StartTime.latest(hour: 19, minute: 30, atOrBefore: now, calendar: farm) == at(18, 7, 30))
        // In the afternoon, "1:30" is today's 1:30 PM, and "7:30" this morning.
        let afternoon = at(18, 16, 0)
        #expect(StartTime.latest(hour: 1, minute: 30, atOrBefore: afternoon, calendar: farm) == at(18, 13, 30))
        #expect(StartTime.latest(hour: 7, minute: 30, atOrBefore: afternoon, calendar: farm) == at(18, 7, 30))
    }

    @Test func aFewMinutesAheadStillMeansToday() {
        // The phone's clock may run a little behind the person's watch.
        let now = at(18, 7, 28)
        #expect(StartTime.latest(hour: 7, minute: 30, atOrBefore: now, calendar: farm) == at(18, 7, 30))
    }

    @Test func justAfterMidnightReachesBackToYesterday() {
        let now = at(18, 0, 20)
        #expect(StartTime.latest(hour: 10, minute: 0, atOrBefore: now, calendar: farm) == at(17, 22, 0))
        #expect(StartTime.latest(hour: 12, minute: 0, atOrBefore: now, calendar: farm) == at(18, 0, 0))
    }

    /// At 8:15 PM, "I started at 7:30" for a shift open since 7:00 means this morning. The
    /// latest 7:30 would be 7:30 PM, and would cut twelve hours off the shift.
    @Test func anEveningFixIsNearTheShiftsStart() {
        let now = at(18, 20, 15)
        let open = at(18, 7, 0)
        #expect(StartTime.nearest(hour: 7, minute: 30, to: open, atOrBefore: now, calendar: farm) == at(18, 7, 30))
        #expect(StartTime.nearest(hour: 19, minute: 30, to: open, atOrBefore: now, calendar: farm) == at(18, 7, 30))
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = farm.calendar.timeZone
        let spoken = phone.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 19, minute: 30))!
        #expect(StartTime.resolve(spoken, now: now, near: open, phoneCalendar: phone, farm: farm) == at(18, 7, 30))
        // Without a shift to go by, it's the latest.
        #expect(StartTime.resolve(spoken, now: now, phoneCalendar: phone, farm: farm) == at(18, 19, 30))
    }

    @Test func aShiftStartedLastNightStaysLastNight() {
        // Clocked in at 10 PM, fixing it to 9:45 just after midnight.
        let now = at(18, 0, 30)
        #expect(StartTime.nearest(hour: 9, minute: 45, to: at(17, 22, 0), atOrBefore: now, calendar: farm) == at(17, 21, 45))
        // An earlier start the same morning.
        #expect(StartTime.nearest(hour: 6, minute: 30, to: at(18, 7, 2), atOrBefore: at(18, 9, 0), calendar: farm) == at(18, 6, 30))
    }

    @Test func thePhonesZoneIsReadAsTheFarmClock() {
        // Siri resolves "7:30" on the phone's clock; the farm keeps its own.
        var phone = Calendar(identifier: .gregorian)
        phone.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spoken = phone.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 7, minute: 30))!
        #expect(StartTime.resolve(spoken, now: at(18, 9, 0), phoneCalendar: phone, farm: farm) == at(18, 7, 30))
    }
}

@Suite("Voice log")
struct VoiceLogTests {
    /// The log names the command and never what was said.
    @Test func commandNamesLeaveOutWhatWasSaid() {
        #expect(VoiceCommands.name(of: .undo) == "undo")
        #expect(VoiceCommands.name(of: .addShiftNote("Fuel low")) == "addShiftNote")
        #expect(VoiceCommands.name(of: .markRow(RowRef(blockId: UUID(), row: 3))) == "markRow")
        #expect(VoiceCommands.name(of: .startBreak(.lunch, reason: "doctor")) == "startBreak")
    }
}
