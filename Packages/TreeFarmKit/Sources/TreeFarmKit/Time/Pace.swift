import Foundation

/// How fast trees are getting shaped over some set of shifts.
public struct PaceStats: Equatable, Sendable {
    public var trees: Int
    /// Worked time on the shifts that had trees.
    public var worked: TimeInterval
    public var treesPerHour: Double
    public var minutesPerTree: Double
    public var payCentsPerTree: Int

    public init(trees: Int, worked: TimeInterval, treesPerHour: Double, minutesPerTree: Double, payCentsPerTree: Int) {
        self.trees = trees
        self.worked = worked
        self.treesPerHour = treesPerHour
        self.minutesPerTree = minutesPerTree
        self.payCentsPerTree = payCentsPerTree
    }
}

/// Ports of the artifact's paceOf, the best-day note, and its number wording.
public enum Pace {
    /// Only shifts with at least one tree count (an unmarked shift doesn't drag the pace down).
    /// Deleted shifts are skipped. Pay per tree uses each shift's own rate.
    public static func stats(_ shifts: [Shift], now: Date, treeCount: (Shift) -> Int) -> PaceStats {
        var trees = 0
        var worked: TimeInterval = 0
        var payCents: Double = 0
        for s in shifts where s.isLive {
            let c = treeCount(s)
            guard c > 0 else { continue }
            let w = s.workedTime(at: now)
            trees += c
            worked += w
            payCents += w * Double(s.rateCents) / 3600
        }
        guard trees > 0 else { return PaceStats(trees: 0, worked: 0, treesPerHour: 0, minutesPerTree: 0, payCentsPerTree: 0) }
        return PaceStats(trees: trees, worked: worked,
                         treesPerHour: worked > 0 ? Double(trees) / (worked / 3600) : 0,
                         minutesPerTree: worked / 60 / Double(trees),
                         payCentsPerTree: Int((payCents / Double(trees)).rounded()))
    }

    /// The fastest day, counting shifts with trees by the day they started. Days with less than
    /// 30 minutes of such work are skipped; a tie goes to the later day. The artifact shows this
    /// only when trees were marked on more than one day.
    public static func bestDay(_ shifts: [Shift], now: Date, calendar: FarmCalendar, treeCount: (Shift) -> Int) -> (day: DayKey, treesPerHour: Double, trees: Int)? {
        var days: [DayKey: (trees: Int, worked: TimeInterval)] = [:]
        for s in shifts where s.isLive {
            let c = treeCount(s)
            guard c > 0 else { continue }
            let key = calendar.dayKey(s.start)
            let d = days[key] ?? (0, 0)
            days[key] = (d.trees + c, d.worked + s.workedTime(at: now))
        }
        return days
            .filter { $0.value.worked >= 30 * 60 }
            .map { (day: $0.key, treesPerHour: Double($0.value.trees) / ($0.value.worked / 3600), trees: $0.value.trees) }
            .max { ($0.treesPerHour, $0.day) < ($1.treesPerHour, $1.day) }
    }

    /// Hours to shape the trees left at this pace. Nil without a pace to go on.
    public static func hoursLeft(treesLeft: Int, treesPerHour: Double) -> Double? {
        guard treesPerHour.isFinite, treesPerHour > 0 else { return nil }
        return Double(max(0, treesLeft)) / treesPerHour
    }

    /// Trees an hour: "26.7", or a whole number from 100 up ("153").
    public static func rateText(_ x: Double) -> String {
        guard x.isFinite else { return "–" }
        let x = max(0, x)
        if x >= 100 { return String(Int(x.rounded())) }
        let tenths = Int((x * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// Time per tree: "2:15" (minutes and seconds), "45 sec" under a minute, "–" for none.
    public static func eachText(minutes m: Double) -> String {
        guard m.isFinite, m > 0 else { return "–" }
        if m < 1 {
            let s = Int((m * 60).rounded())
            if s < 60 { return "\(s) sec" }
        }
        var mm = Int(m.rounded(.down))
        var ss = Int(((m - Double(mm)) * 60).rounded())
        if ss == 60 { mm += 1; ss = 0 }
        return "\(mm):\(Fmt.pad2(ss))"
    }

    /// Roughly how long: "30 minutes", "1 hour", "3.5 hours" (to the half hour). The artifact's
    /// sentence adds the "about": "At your season pace that’s about 3.5 hours of work."
    public static func hoursWords(_ h: Double) -> String {
        guard h.isFinite else { return "–" }
        let h = max(0, h)
        if h < 1 {
            let m = max(1, Int((h * 60).rounded()))
            if m < 60 { return "\(m) minute" + (m == 1 ? "" : "s") }
        }
        let halves = Int((max(1, h) * 2).rounded())
        let number = halves % 2 == 0 ? "\(halves / 2)" : "\(halves / 2).5"
        return number + (halves == 2 ? " hour" : " hours")
    }
}
