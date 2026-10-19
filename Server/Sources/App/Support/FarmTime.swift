import Foundation

/// Dates as people on the farm read them, in the farm's time zone.
enum FarmTime {
    static func isValidZone(_ id: String) -> Bool {
        !id.isEmpty && TimeZone(identifier: id) != nil
    }

    static func zone(_ id: String) -> TimeZone {
        TimeZone(identifier: id) ?? TimeZone(identifier: "UTC")!
    }

    static func calendar(_ id: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone(id)
        return cal
    }

    /// "2026"
    static func yearName(_ date: Date, timeZoneId: String) -> String {
        String(calendar(timeZoneId).component(.year, from: date))
    }

    static func format(_ date: Date, _ pattern: String, timeZoneId: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar(timeZoneId)
        f.timeZone = zone(timeZoneId)
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "Oct 16"
    static func day(_ date: Date, timeZoneId: String) -> String { format(date, "MMM d", timeZoneId: timeZoneId) }

    /// "7:02 AM"
    static func time(_ date: Date, timeZoneId: String) -> String { format(date, "h:mm a", timeZoneId: timeZoneId) }
}
