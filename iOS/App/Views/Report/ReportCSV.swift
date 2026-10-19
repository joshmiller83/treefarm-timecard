import Foundation
import TimeCardCore

/// The time card as a spreadsheet, made on the phone so it works offline. Columns follow
/// the server's export (Name, Date, In, Out, Breaks, Hours, Notes) with Trees added:
/// dates are farm days ("2026-10-12"), times are the farm's clock, Breaks is minutes of
/// break (listed, not counted), and Hours is decimal hours worked. One row per shift, no
/// totals row, so a spreadsheet can sum the columns. Never pay.
enum ReportCSV {
    static let header = ["Name", "Date", "In", "Out", "Breaks", "Hours", "Trees", "Notes"]

    static func make(report: Report, workerName: String, calendar: FarmCalendar, now: Date) -> String {
        var csv = row(header)
        for r in report.rows {
            let s = r.shift
            csv += row([
                workerName,
                calendar.dayKey(s.start).description,
                Fmt.time(s.start, calendar),
                s.end.map { Fmt.time($0, calendar) } ?? "",
                String(Int((s.breakTime(at: now) / 60).rounded())),
                Fmt.decimalHours(r.worked),
                String(r.trees),
                s.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            ])
        }
        return csv
    }

    /// RFC 4180, as the server writes it: fields with commas, quotes or line breaks are
    /// quoted, and anything a spreadsheet would run as a formula gets a leading apostrophe.
    static func row(_ fields: [String]) -> String {
        fields.map { raw in
            var value = raw
            if let first = value.first, "=+-@\t\r".contains(first) { value = "'" + value }
            // `isNewline` also catches "\r\n", which Swift keeps as one Character.
            guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }.joined(separator: ",") + "\r\n"
    }
}
