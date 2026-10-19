import Foundation

/// Fixed US-English text for times, durations and money. Built by hand rather than with
/// formatters, so the app, the server and Linux all print exactly the same thing.
/// Dates and times read in the farm's time zone.
public enum Fmt {
    // MARK: Durations

    /// "6:05:09". Seconds are cut, not rounded, like a stopwatch.
    public static func hms(_ t: TimeInterval) -> String {
        let s = wholeSeconds(t)
        return "\(s / 3600):\(pad2(s % 3600 / 60)):\(pad2(s % 60))"
    }

    /// "6:05". Minutes are cut, not rounded.
    public static func hm(_ t: TimeInterval) -> String {
        let m = wholeSeconds(t) / 60
        return "\(m / 60):\(pad2(m % 60))"
    }

    /// "6:05", rounded to the nearest minute the way `spokenDuration` is, for a card shown
    /// beside what Siri says (1 min 45 s is "0:02" and "2 minutes", never "0:01").
    public static func hmRounded(_ t: TimeInterval) -> String {
        let m = roundedMinutes(t)
        return "\(m / 60):\(pad2(m % 60))"
    }

    /// Hours to two places, as on the report: "6.08".
    public static func decimalHours(_ t: TimeInterval) -> String {
        let hundredths = Int((clean(t) / 36).rounded())
        return "\(hundredths / 100).\(pad2(hundredths % 100))"
    }

    /// Rounded to the minute: "45 min", "1 h 5 min", "2 h".
    public static func minutesText(_ t: TimeInterval) -> String {
        let m = roundedMinutes(t)
        if m < 60 { return "\(m) min" }
        return "\(m / 60) h" + (m % 60 == 0 ? "" : " \(m % 60) min")
    }

    /// Rounded to the minute, always both parts: "6 h 5 min", "0 h 0 min".
    public static func hmWords(_ t: TimeInterval) -> String {
        let m = roundedMinutes(t)
        return "\(m / 60) h \(m % 60) min"
    }

    /// For Siri to say: "6 hours 5 minutes", "1 hour", "45 minutes", "less than a minute".
    public static func spokenDuration(_ t: TimeInterval) -> String {
        let m = roundedMinutes(t)
        if m == 0 { return "less than a minute" }
        var parts: [String] = []
        if m >= 60 { parts.append(plain(m / 60, "hour")) }
        if m % 60 > 0 { parts.append(plain(m % 60, "minute")) }
        return parts.joined(separator: " ")
    }

    // MARK: Money and counts

    /// "$94.50", "$1,234.00", "-$5.00".
    public static func usd(cents: Int) -> String {
        let a = cents.magnitude
        return (cents < 0 ? "-" : "") + "$" + grouped(a / 100) + "." + pad2(Int(a % 100))
    }

    /// "1 tree", "3 trees", "8,540 trees".
    public static func plural(_ n: Int, _ word: String) -> String {
        count(n) + " " + word + (n == 1 ? "" : "s")
    }

    /// A count with thousands separators: "8,540".
    public static func count(_ n: Int) -> String {
        (n < 0 ? "-" : "") + grouped(n.magnitude)
    }

    // MARK: Dates and times

    /// "7:02 AM".
    public static func time(_ d: Date, _ cal: FarmCalendar) -> String {
        let c = parts(d, cal)
        return clock(c.hour, c.minute) + (c.hour < 12 ? " AM" : " PM")
    }

    /// For Siri to say. Inside the workday, 6:00 AM to 5:59 PM, it's just "7:02" or "4:31":
    /// each hour on the dial means one time there (6–11 morning, 12 noon, 1–5 afternoon).
    /// Outside it, AM or PM is added so "5:45 AM" and "6:10 PM" can't be mistaken.
    public static func spokenTime(_ d: Date, _ cal: FarmCalendar) -> String {
        let c = parts(d, cal)
        if (6..<18).contains(c.hour) { return clock(c.hour, c.minute) }
        return time(d, cal)
    }

    /// "Sun, Oct 18".
    public static func day(_ d: Date, _ cal: FarmCalendar) -> String {
        let c = parts(d, cal)
        return "\(weekdays[c.weekday - 1].prefix(3)), \(months[c.month - 1]) \(c.day)"
    }

    /// "Sunday, Oct 18".
    public static func dayLong(_ d: Date, _ cal: FarmCalendar) -> String {
        let c = parts(d, cal)
        return "\(weekdays[c.weekday - 1]), \(months[c.month - 1]) \(c.day)"
    }

    /// "Oct 18".
    public static func monthDay(_ d: Date, _ cal: FarmCalendar) -> String {
        let c = parts(d, cal)
        return "\(months[c.month - 1]) \(c.day)"
    }

    /// "Sun 10/18", for the report's date column.
    public static func shortDay(_ d: Date, _ cal: FarmCalendar) -> String {
        let c = parts(d, cal)
        return "\(weekdays[c.weekday - 1].prefix(3)) \(c.month)/\(c.day)"
    }

    /// A period's label: "Oct 18, 2026" for one day, "Oct 12 – Oct 18, 2026" for a range,
    /// and "Dec 28, 2026 – Jan 3, 2027" when it crosses into a new year. `endExclusive` is the
    /// first moment after the period, as from `weekBounds` or `monthBounds`.
    public static func rangeLabel(start: Date, endExclusive: Date, _ cal: FarmCalendar) -> String {
        let first = cal.dayKey(start)
        let last = max(first, cal.dayKey(cal.addDays(endExclusive, -1)))
        if first == last { return monthDay(start, cal) + ", \(first.year)" }
        let lastDate = cal.date(on: last, hour: 12, minute: 0)
        if first.year != last.year {
            return monthDay(start, cal) + ", \(first.year) – " + monthDay(lastDate, cal) + ", \(last.year)"
        }
        return monthDay(start, cal) + " – " + monthDay(lastDate, cal) + ", \(last.year)"
    }

    // MARK: Helpers

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private static func parts(_ d: Date, _ cal: FarmCalendar) -> (month: Int, day: Int, weekday: Int, hour: Int, minute: Int) {
        let c = cal.calendar.dateComponents([.month, .day, .weekday, .hour, .minute], from: d)
        return (c.month ?? 1, c.day ?? 1, c.weekday ?? 1, c.hour ?? 0, c.minute ?? 0)
    }

    /// "7:02" on a 12-hour dial.
    private static func clock(_ hour: Int, _ minute: Int) -> String {
        "\(hour % 12 == 0 ? 12 : hour % 12):\(pad2(minute))"
    }

    static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    private static func clean(_ t: TimeInterval) -> TimeInterval { t.isFinite ? max(0, t) : 0 }
    private static func wholeSeconds(_ t: TimeInterval) -> Int { Int(clean(t).rounded(.down)) }
    private static func roundedMinutes(_ t: TimeInterval) -> Int { Int((clean(t) / 60).rounded()) }
    private static func plain(_ n: Int, _ word: String) -> String { "\(n) \(word)" + (n == 1 ? "" : "s") }

    private static func grouped(_ n: UInt) -> String {
        let digits = String(n)
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }
}
