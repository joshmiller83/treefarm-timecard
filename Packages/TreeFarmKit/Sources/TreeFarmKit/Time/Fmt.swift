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

    // MARK: Helpers

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
