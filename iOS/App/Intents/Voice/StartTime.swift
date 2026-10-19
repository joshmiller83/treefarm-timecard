import Foundation
import TimeCardCore

/// Turns a spoken start time ("I started at 7:30") into the moment it means.
///
/// Siri resolves a bare time on the phone's clock and may pick the morning or the evening, or
/// even tomorrow. Someone fixing their start always means a time that has already passed, so
/// this takes the wall-clock hour and minute and finds the latest moment at or before now (with
/// the same few minutes of clock-skew room ShiftRules allows) that shows that time on a 12-hour
/// dial in the farm's time zone. ShiftRules then checks the result like any other edit.
enum StartTime {
    static func resolve(_ spoken: Date, now: Date, phoneCalendar: Calendar = .current, farm: FarmCalendar) -> Date {
        let c = phoneCalendar.dateComponents([.hour, .minute], from: spoken)
        return latest(hour: c.hour ?? 0, minute: c.minute ?? 0, atOrBefore: now, calendar: farm)
    }

    static func latest(hour: Int, minute: Int, atOrBefore now: Date, calendar: FarmCalendar) -> Date {
        let limit = now.addingTimeInterval(Limits.clockSkew)
        let today = calendar.startOfDay(now)
        var best: Date?
        for dayOffset in [0, -1] {
            let day = calendar.addDays(today, dayOffset)
            for h in [hour % 12, hour % 12 + 12] {
                guard let candidate = calendar.calendar.date(bySettingHour: h, minute: minute, second: 0, of: day),
                      candidate <= limit else { continue }
                if best.map({ candidate > $0 }) ?? true { best = candidate }
            }
        }
        return best ?? now
    }
}
