import Foundation

/// The span a time card covers.
public enum ReportPeriod: Hashable, Sendable {
    case thisWeek
    case lastWeek
    case thisMonth
    /// Both days included.
    case custom(from: DayKey, to: DayKey)

    /// Start and exclusive end, at farm-local midnights. A custom range that ends before it
    /// starts becomes just its first day, as in the artifact.
    public func bounds(now: Date, calendar: FarmCalendar) -> (start: Date, end: Date) {
        switch self {
        case .thisWeek:
            let w = calendar.startOfWeek(containing: now)
            return (w, calendar.addDays(w, 7))
        case .lastWeek:
            let w = calendar.startOfWeek(containing: now)
            return (calendar.addDays(w, -7), w)
        case .thisMonth:
            return calendar.monthBounds(containing: now)
        case .custom(let from, let to):
            let start = calendar.startOfDay(from)
            let end = calendar.addDays(calendar.startOfDay(max(from, to)), 1)
            return (start, end)
        }
    }
}

/// One shift on the time card.
public struct ReportRow: Equatable, Sendable {
    public var shift: Shift
    public var worked: TimeInterval
    public var trees: Int
    /// From `Clock.breakLines`. Breaks are listed but not counted.
    public var breakLines: [String]

    public init(shift: Shift, worked: TimeInterval, trees: Int, breakLines: [String]) {
        self.shift = shift
        self.worked = worked
        self.trees = trees
        self.breakLines = breakLines
    }
}

/// The paper time card: every shift that started in the period, oldest first, with totals.
/// Pay is never on it.
public struct Report: Equatable, Sendable {
    public var start: Date
    /// Exclusive.
    public var end: Date
    public var rows: [ReportRow]
    public var totalWorked: TimeInterval
    /// Distinct days a shift started on.
    public var daysWorked: Int
    public var totalTrees: Int

    public init(start: Date, end: Date, rows: [ReportRow], totalWorked: TimeInterval, daysWorked: Int, totalTrees: Int) {
        self.start = start
        self.end = end
        self.rows = rows
        self.totalWorked = totalWorked
        self.daysWorked = daysWorked
        self.totalTrees = totalTrees
    }

    /// Port of reportData. A shift belongs to the period it started in; deleted shifts are left out.
    /// `treeCount` says how many trees each shift shaped.
    public static func build(shifts: [Shift], period: ReportPeriod, now: Date, calendar: FarmCalendar, treeCount: (Shift) -> Int) -> Report {
        let (start, end) = period.bounds(now: now, calendar: calendar)
        let rows = shifts
            .filter { $0.isLive && $0.start >= start && $0.start < end }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
            .map { ReportRow(shift: $0, worked: $0.workedTime(at: now), trees: treeCount($0), breakLines: Clock.breakLines($0, now: now)) }
        return Report(start: start, end: end, rows: rows,
                      totalWorked: rows.reduce(0) { $0 + $1.worked },
                      daysWorked: Set(rows.map { calendar.dayKey($0.shift.start) }).count,
                      totalTrees: rows.reduce(0) { $0 + $1.trees })
    }
}
