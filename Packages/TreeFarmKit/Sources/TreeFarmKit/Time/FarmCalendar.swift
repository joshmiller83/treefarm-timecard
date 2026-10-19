import Foundation

/// Days and weeks as the farm sees them: in the farm's time zone, with the farm's first
/// day of the week. Every "today", "this week" and "which day" question goes through here,
/// so the app and the server agree even when a phone is set to another zone.
/// Days are calendar days, so DST days are 23 or 25 hours long.
public struct FarmCalendar: Sendable {
    /// Gregorian, in the farm's zone, `firstWeekday` set to the farm's week start.
    public var calendar: Calendar

    public var timeZone: TimeZone {
        get { calendar.timeZone }
        set { calendar.timeZone = newValue }
    }

    public init(timeZone: TimeZone, weekStart: Weekday) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.firstWeekday = weekStart.rawValue
        calendar = cal
    }

    public init(farm: Farm) {
        self.init(timeZone: farm.timeZone, weekStart: farm.weekStart)
    }

    /// The first moment of the farm-local day `date` falls on.
    public func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public func dayKey(_ date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: c.year ?? 0, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// The first moment of that day on the farm.
    public func startOfDay(_ key: DayKey) -> Date {
        // Noon always exists, so go there first and walk back to the day's real start.
        startOfDay(date(on: key, hour: 12, minute: 0))
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool {
        dayKey(a) == dayKey(b)
    }

    /// Moves by calendar days, keeping the wall-clock time, so midnight plus one day is the next midnight even across DST.
    public func addDays(_ date: Date, _ n: Int) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date.addingTimeInterval(TimeInterval(n) * 86_400)
    }

    /// That wall-clock time on that day. A time that doesn't exist (2:30 on spring-forward
    /// day) comes back as whatever Foundation picks, which stays on the same day.
    public func date(on key: DayKey, hour: Int, minute: Int) -> Date {
        let comps = DateComponents(year: key.year, month: key.month, day: key.day, hour: hour, minute: minute)
        return calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }
}
