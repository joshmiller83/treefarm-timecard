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
