import Foundation

/// Hours for the Clock tab: today, this week and each day of the week.
public struct HoursSummary: Equatable, Sendable {
    public var today: TimeInterval
    public var week: TimeInterval
    /// Worked time per day, 7 entries in week order.
    public var days: [TimeInterval]
    /// The week's 8 day boundaries (see `FarmCalendar.weekBounds`).
    public var weekBounds: [Date]
    /// The top of the week chart: 8 hours, or the biggest day if longer.
    public var chartMax: TimeInterval

    public init(today: TimeInterval, week: TimeInterval, days: [TimeInterval], weekBounds: [Date], chartMax: TimeInterval) {
        self.today = today
        self.week = week
        self.days = days
        self.weekBounds = weekBounds
        self.chartMax = chartMax
    }
}

public enum Hours {
    /// Today's and this week's hours. A shift counts toward the day and week it started in,
    /// so a shift past midnight belongs to the day it began. Deleted shifts are skipped.
    public static func summary(shifts: [Shift], now: Date, calendar: FarmCalendar) -> HoursSummary {
        let today = calendar.dayKey(now)
        let bounds = calendar.weekBounds(containing: now)
        var todayTotal: TimeInterval = 0
        var weekTotal: TimeInterval = 0
        var days = [TimeInterval](repeating: 0, count: 7)
        for s in shifts where s.isLive {
            let w = s.workedTime(at: now)
            if calendar.dayKey(s.start) == today { todayTotal += w }
            if s.start >= bounds[0] && s.start < bounds[7] {
                weekTotal += w
                if let j = (0..<7).last(where: { s.start >= bounds[$0] }) { days[j] += w }
            }
        }
        return HoursSummary(today: todayTotal, week: weekTotal, days: days, weekBounds: bounds,
                            chartMax: max(8 * 3600, days.max() ?? 0))
    }

    /// The big timer on the Clock tab: today's worked time, unless the open shift started on
    /// an earlier day, in which case it's that shift's worked time ("worked this shift").
    public static func bigClock(shifts: [Shift], now: Date, calendar: FarmCalendar) -> TimeInterval {
        if let open = latestOpen(shifts), !calendar.isSameDay(open.start, now) {
            return open.workedTime(at: now)
        }
        return summary(shifts: shifts, now: now, calendar: calendar).today
    }

    /// Pay for that much worked time at an hourly rate, rounded to the nearest cent.
    public static func payCents(for worked: TimeInterval, rateCents: Int) -> Int {
        Int((worked * Double(rateCents) / 3600).rounded())
    }

    /// Still on the clock from an earlier day: "You've been clocked in since Sat, Oct 17 at 7:00 AM."
    public static func isStale(_ shift: Shift, now: Date, calendar: FarmCalendar) -> Bool {
        shift.isLive && shift.isOpen && calendar.dayKey(shift.start) < calendar.dayKey(now)
    }

    /// Open longer than `Limits.forgotToClockOut` (16 hours).
    public static func forgotToClockOut(_ shift: Shift, now: Date) -> Bool {
        shift.isLive && shift.isOpen && now.timeIntervalSince(shift.start) > Limits.forgotToClockOut
    }

    /// The live open shift with the latest start.
    static func latestOpen(_ shifts: [Shift]) -> Shift? {
        shifts.filter { $0.isLive && $0.isOpen }.max { $0.start < $1.start }
    }
}
