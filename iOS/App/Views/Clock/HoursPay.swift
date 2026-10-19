import Foundation
import TimeCardCore

/// The "Hours and pay" card: today, this week, and a bar for each day of the farm's week.
/// Pay adds up each shift at its own rate, so a raise doesn't rewrite last week.
struct HoursPay: Equatable {
    struct Day: Equatable, Identifiable {
        var id: Int
        /// "Mon"
        var label: String
        /// Decimal hours for the chart.
        var hours: Double
        /// "6.50", or "–" for a day off.
        var hoursText: String
        var isToday: Bool
        /// "Monday, Oct 12: 6.50 hours", for VoiceOver.
        var spoken: String
    }

    var todayHours: String
    var weekHours: String
    var todayPay: String
    var weekPay: String
    var days: [Day]
    /// The top of the chart in hours: 8, or the longest day.
    var chartMax: Double
    /// "Week of Oct 12 – Oct 18, 2026"
    var period: String
    /// "$18.00", nil without a rate.
    var rate: String?
    /// No hourly rate yet, so pay would read $0.00.
    var needsRate: Bool

    init(state: FieldState, now: Date) {
        let cal = state.calendar
        let shifts = state.liveShifts
        let summary = Hours.summary(shifts: shifts, now: now, calendar: cal)
        let bounds = summary.weekBounds

        func pay(_ list: [Shift]) -> Int {
            list.reduce(0) { $0 + Hours.payCents(for: $1.workedTime(at: now), rateCents: $1.rateCents) }
        }
        let today = shifts.filter { cal.isSameDay($0.start, now) }
        let week = shifts.filter { $0.start >= bounds[0] && $0.start < bounds[7] }

        todayHours = Fmt.decimalHours(summary.today) + " hrs"
        weekHours = Fmt.decimalHours(summary.week) + " hrs"
        todayPay = Fmt.usd(cents: pay(today))
        weekPay = Fmt.usd(cents: pay(week))
        days = (0..<7).map { i in
            let worked = summary.days[i]
            let day = bounds[i]
            let text = worked > 0 ? Fmt.decimalHours(worked) : "–"
            return Day(id: i, label: String(Fmt.day(day, cal).prefix(3)), hours: worked / 3600, hoursText: text,
                       isToday: cal.isSameDay(day, now),
                       spoken: "\(Fmt.dayLong(day, cal)): " + (worked > 0 ? "\(text) hours" : "no hours"))
        }
        chartMax = summary.chartMax / 3600

        needsRate = state.me.rateCents <= 0
        rate = needsRate ? nil : Fmt.usd(cents: state.me.rateCents)
        period = "Week of \(Fmt.rangeLabel(start: bounds[0], endExclusive: bounds[7], cal))"
    }

    /// The line under the chart; the rate shows only with pay.
    func footnote(showPay: Bool) -> String {
        let at = showPay ? rate.map { " at \($0) an hour" } ?? "" : ""
        return period + at + ". Breaks don’t count toward hours. Pay never shows on the report."
    }
}
