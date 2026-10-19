import Foundation
import TimeCardCore

/// Turns a spoken start time ("I started at 7:30") into the moment it means.
///
/// Siri resolves a bare time on the phone's clock and may pick the morning or the evening, or
/// even tomorrow, and it never says which it heard. Someone fixing their start means a time that
/// has already passed (with the same few minutes of clock-skew room ShiftRules allows) and is
/// close to when the shift says it started: it's a correction, not a new shift. So this takes
/// the wall-clock hour and minute and, of the moments that show that time on a 12-hour dial in
/// the farm's time zone today or yesterday, picks the one nearest the shift's current start.
/// At 8:15 PM, "7:30" for a shift open since 7:00 AM is 7:30 AM, not 7:30 PM. With no open
/// shift to go by, it's the latest one. ShiftRules then checks the result like any other edit.
enum StartTime {
    static func resolve(_ spoken: Date, now: Date, near start: Date? = nil, phoneCalendar: Calendar = .current, farm: FarmCalendar) -> Date {
        let c = phoneCalendar.dateComponents([.hour, .minute], from: spoken)
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        if let start { return nearest(hour: hour, minute: minute, to: start, atOrBefore: now, calendar: farm) }
        return latest(hour: hour, minute: minute, atOrBefore: now, calendar: farm)
    }

    /// The latest moment at or before now showing hour:minute on a 12-hour dial.
    static func latest(hour: Int, minute: Int, atOrBefore now: Date, calendar: FarmCalendar) -> Date {
        candidates(hour: hour, minute: minute, atOrBefore: now, calendar: calendar).max() ?? now
    }

    /// The moment at or before now showing hour:minute on a 12-hour dial that's nearest `start`.
    /// On a tie the later one wins.
    static func nearest(hour: Int, minute: Int, to start: Date, atOrBefore now: Date, calendar: FarmCalendar) -> Date {
        let all = candidates(hour: hour, minute: minute, atOrBefore: now, calendar: calendar).sorted(by: >)
        return all.min { abs($0.timeIntervalSince(start)) < abs($1.timeIntervalSince(start)) } ?? now
    }

    private static func candidates(hour: Int, minute: Int, atOrBefore now: Date, calendar: FarmCalendar) -> [Date] {
        let limit = now.addingTimeInterval(Limits.clockSkew)
        let today = calendar.startOfDay(now)
        return [0, -1].flatMap { dayOffset -> [Date] in
            let day = calendar.addDays(today, dayOffset)
            return [hour % 12, hour % 12 + 12].compactMap { h in
                calendar.calendar.date(bySettingHour: h, minute: minute, second: 0, of: day)
            }
        }
        .filter { $0 <= limit }
    }
}
