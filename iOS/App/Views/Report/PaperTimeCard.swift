import Foundation
import TimeCardCore

/// The paper time card, as text ready to draw: the app's preview and the PDF both print
/// exactly this. Built from TreeFarmKit's `Report`, so a shift belongs to the period it
/// started in and breaks are listed but not counted. Pay is never on it.
struct PaperTimeCard: Equatable {
    struct Row: Equatable {
        /// "Mon 10/12"
        var date: String
        /// "7:02 AM"
        var clockIn: String
        /// "3:31 PM", or "—" while the shift is still open.
        var clockOut: String
        /// Clock-out fell on the next day.
        var nextDay: Bool
        /// "290", or "–" for none.
        var trees: String
        /// Decimal hours: "8.48".
        var hours: String
        /// From `Clock.breakLines`.
        var breaks: [String]
        var notes: String
        /// "Still on the clock at 4:31 PM." for an open shift.
        var stillOpen: String?

        /// Lines printed under the row: breaks, then notes, then the open-shift note.
        var details: [Detail] {
            var lines: [Detail] = []
            if !breaks.isEmpty { lines.append(Detail(kind: .breaks, text: breaks.joined(separator: " · "))) }
            if !notes.isEmpty { lines.append(Detail(kind: .notes, text: notes)) }
            if let stillOpen { lines.append(Detail(kind: .open, text: stillOpen)) }
            return lines
        }
    }

    /// A line under a row. Breaks and notes get a label ("Breaks", "Notes") when printed.
    struct Detail: Equatable, Hashable {
        enum Kind: Equatable, Hashable { case breaks, notes, open }
        var kind: Kind
        var text: String

        var label: String? {
            switch kind {
            case .breaks: "Breaks"
            case .notes: "Notes"
            case .open: nil
            }
        }
    }

    static let title = "TIME CARD"
    static let footnote = "Breaks are listed, not counted."
    static let empty = "No shifts in these dates."
    static let columns = ["Date", "In", "Out", "Trees", "Hours"]

    var farm: String
    var worker: String
    /// "Crew lead", or "".
    var job: String
    /// "Oct 12 – Oct 18, 2026"
    var range: String
    var rows: [Row]
    /// Decimal hours: "39.92".
    var totalHours: String
    /// "1,347"
    var totalTrees: String
    /// "5 days"
    var days: String
    /// "Prepared Mon, Oct 19 at 4:31 PM"
    var prepared: String

    /// "Crew lead · Alex Rivera", or just the name.
    var whoLine: String { job.isEmpty ? worker : "\(job) · \(worker)" }
    /// "39.92 hours · 1,347 trees"
    var totalsLine: String { "\(totalHours) hours · \(totalTrees) trees" }

    init(farm: String, worker: String, job: String, range: String, rows: [Row], totalHours: String, totalTrees: String, days: String, prepared: String) {
        self.farm = farm
        self.worker = worker
        self.job = job
        self.range = range
        self.rows = rows
        self.totalHours = totalHours
        self.totalTrees = totalTrees
        self.days = days
        self.prepared = prepared
    }

    init(report: Report, farmName: String, worker: Member?, calendar: FarmCalendar, now: Date) {
        let preparedAt = Fmt.time(now, calendar)
        self.init(
            farm: farmName,
            worker: worker?.displayName ?? "",
            job: worker?.jobTitle.trimmingCharacters(in: .whitespaces) ?? "",
            range: Fmt.rangeLabel(start: report.start, endExclusive: report.end, calendar),
            rows: report.rows.map { r in
                let s = r.shift
                return Row(
                    date: Fmt.shortDay(s.start, calendar),
                    clockIn: Fmt.time(s.start, calendar),
                    clockOut: s.end.map { Fmt.time($0, calendar) } ?? "—",
                    nextDay: s.end.map { calendar.dayKey($0) > calendar.dayKey(s.start) } ?? false,
                    trees: r.trees > 0 ? Fmt.count(r.trees) : "–",
                    hours: Fmt.decimalHours(r.worked),
                    breaks: r.breakLines,
                    notes: s.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    stillOpen: s.isOpen ? "Still on the clock at \(preparedAt)." : nil)
            },
            totalHours: Fmt.decimalHours(report.totalWorked),
            totalTrees: Fmt.count(report.totalTrees),
            days: Fmt.plural(report.daysWorked, "day"),
            prepared: "Prepared \(Fmt.day(now, calendar)) at \(preparedAt)")
    }

    /// A file name for the export: "Time Card – Alex Rivera – Oct 12 – Oct 18, 2026".
    var fileName: String {
        let raw = ["Time Card", worker, range].filter { !$0.isEmpty }.joined(separator: " – ")
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        return raw.components(separatedBy: unsafe).joined(separator: "-")
    }
}

/// Which time card the Report tab shows.
struct ReportRequest: Equatable {
    var period: ReportPeriod
    /// Whose shifts: the signed-in person, or a crew member an admin picked.
    var userId: UUID
}

extension PaperTimeCard {
    /// The Kit report for one person and period.
    static func report(for request: ReportRequest, shifts: some Sequence<Shift>, trees: ShiftTrees, calendar: FarmCalendar, now: Date) -> Report {
        Report.build(shifts: shifts.filter { $0.userId == request.userId }, period: request.period, now: now, calendar: calendar,
                     treeCount: { trees.count($0.id) })
    }
}
