import Foundation
import TimeCardCore

/// One shift on the Log, ready to show.
struct LogShiftRow: Identifiable, Equatable {
    var id: UUID
    /// "Mon, Oct 12"
    var day: String
    /// "7:02 AM"
    var clockIn: String
    /// "3:31 PM", or nil while still on the clock.
    var clockOut: String?
    /// Clock-out fell on the next day.
    var endsNextDay: Bool
    var isOpen: Bool
    /// Decimal hours worked: "8.48".
    var hours: String
    /// "$169.60"
    var pay: String
    var trees: Int
    /// "Block 1: rows 1–12, row 13 (trees 1–4)", or "".
    var treeSummary: String
    /// From `Clock.breakLines`: "Lunch 30 min", "Break 12 min (Fuel run)".
    var breakLines: [String]
    var notes: String

    /// What VoiceOver reads for the row (pay only when shown).
    func spoken(showPay: Bool) -> String {
        var parts = ["\(day), \(clockIn) to \(clockOut.map { $0 + (endsNextDay ? " the next day" : "") } ?? "now, still on the clock")"]
        parts.append("\(hours) hours")
        if showPay { parts.append(pay) }
        parts.append(Fmt.plural(trees, "tree"))
        if !treeSummary.isEmpty { parts.append(treeSummary) }
        parts += breakLines
        if !notes.isEmpty { parts.append("Notes: \(notes)") }
        return parts.joined(separator: ". ")
    }
}

/// A farm week on the Log: its shifts, newest first, and its totals.
struct LogWeek: Identifiable, Equatable {
    /// The week's first moment.
    var id: Date
    /// "This week", "Last week", or the range for older weeks.
    var title: String
    /// "Oct 12 – Oct 18, 2026"
    var range: String
    /// Decimal hours: "38.25".
    var hours: String
    /// Each shift at its own rate: "$765.00".
    var pay: String
    var trees: Int
    /// Days with a shift starting on them.
    var days: Int
    var shifts: [LogShiftRow]
}

enum LogBuilder {
    /// The person's shifts grouped into the farm's weeks (its time zone and first weekday),
    /// newest week first. A shift belongs to the week and day it started, as on the time card.
    static func weeks(shifts: [Shift], trees: ShiftTrees, calendar: FarmCalendar, now: Date) -> [LogWeek] {
        let thisWeek = calendar.startOfWeek(containing: now)
        let lastWeek = calendar.addDays(thisWeek, -7)
        let grouped = Dictionary(grouping: shifts.filter(\.isLive)) { calendar.startOfWeek(containing: $0.start) }
        return grouped.keys.sorted(by: >).map { weekStart in
            let list = grouped[weekStart]!.sorted { ($0.start, $0.id.uuidString) > ($1.start, $1.id.uuidString) }
            let rows = list.map { row($0, trees: trees, calendar: calendar, now: now) }
            let worked = list.reduce(0) { $0 + $1.workedTime(at: now) }
            let payCents = list.reduce(0) { $0 + Hours.payCents(for: $1.workedTime(at: now), rateCents: $1.rateCents) }
            let end = calendar.addDays(weekStart, 7)
            let range = Fmt.rangeLabel(start: weekStart, endExclusive: end, calendar)
            let title = weekStart == thisWeek ? "This week" : weekStart == lastWeek ? "Last week" : range
            return LogWeek(id: weekStart, title: title, range: range,
                           hours: Fmt.decimalHours(worked), pay: Fmt.usd(cents: payCents),
                           trees: rows.reduce(0) { $0 + $1.trees },
                           days: Set(list.map { calendar.dayKey($0.start) }).count,
                           shifts: rows)
        }
    }

    static func row(_ shift: Shift, trees: ShiftTrees, calendar: FarmCalendar, now: Date) -> LogShiftRow {
        let worked = shift.workedTime(at: now)
        return LogShiftRow(
            id: shift.id,
            day: Fmt.day(shift.start, calendar),
            clockIn: Fmt.time(shift.start, calendar),
            clockOut: shift.end.map { Fmt.time($0, calendar) },
            endsNextDay: shift.end.map { calendar.dayKey($0) > calendar.dayKey(shift.start) } ?? false,
            isOpen: shift.isOpen,
            hours: Fmt.decimalHours(worked),
            pay: Fmt.usd(cents: Hours.payCents(for: worked, rateCents: shift.rateCents)),
            trees: trees.count(shift.id),
            treeSummary: trees.summary(shift.id),
            breakLines: TreeFarmKit.Clock.breakLines(shift, now: now),
            notes: shift.notes.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
