import SwiftUI
import TimeCardCore
import UIKit

/// One person's time card for this week, last week or this month: every shift with its
/// hours, breaks and trees, and the totals. Pay is never on it. The CSV comes from the
/// server, so it matches the farm's export exactly.
struct MemberReportView: View {
    enum Period: String, Hashable {
        case thisWeek, lastWeek, thisMonth

        var report: ReportPeriod {
            switch self {
            case .thisWeek: .thisWeek
            case .lastWeek: .lastWeek
            case .thisMonth: .thisMonth
            }
        }
    }

    var userId: UUID
    @Environment(TimeCardSession.self) private var session
    @State private var period: Period = .thisWeek
    @State private var sharing: SharedFile?
    @State private var exporting = false
    @State private var exportError: String?

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            ScrollView {
                if let farm = session.farm, let member = session.snapshot.members[userId] {
                    content(member: member, farm: farm, now: timeline.date).teamPage()
                }
            }
        }
        .screenBackground()
        .navigationTitle("Time Card")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharing) { file in
            ActivitySheet(items: [file.url]).ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func content(member: Member, farm: Farm, now: Date) -> some View {
        let calendar = FarmCalendar(farm: farm)
        let shifts = session.snapshot.shifts.values.filter { $0.userId == userId }
        let ids = Set(shifts.map(\.id))
        let trees = session.snapshot.marks.values.reduce(into: [UUID: Int]()) { counts, mark in
            if mark.isLive && ids.contains(mark.shiftId) { counts[mark.shiftId, default: 0] += 1 }
        }
        let report = Report.build(shifts: Array(shifts), period: period.report, now: now, calendar: calendar) { trees[$0.id] ?? 0 }

        VStack(alignment: .leading, spacing: 16) {
            GloveSegmented(options: [
                (.thisWeek, "This week", "report-this-week"),
                (.lastWeek, "Last week", "report-last-week"),
                (.thisMonth, "Month", "report-month"),
            ], selection: $period)
            PaperCard(member: member, farm: farm, report: report, calendar: calendar)
            Button {
                Task { await exportCSV(member: member, report: report, calendar: calendar) }
            } label: {
                if exporting {
                    ProgressView()
                } else {
                    Label("Share as CSV", systemImage: "tablecells")
                }
            }
            .buttonStyle(.gloveSecondary)
            .disabled(exporting || report.rows.isEmpty)
            .accessibilityIdentifier("report-csv")
            if let exportError {
                ErrorMessage(text: exportError)
            }
        }
    }

    private func exportCSV(member: Member, report: Report, calendar: FarmCalendar) async {
        exporting = true
        defer { exporting = false }
        do {
            let data = try await session.exportCSV(from: report.start, to: report.end, userId: member.userId)
            let label = Fmt.rangeLabel(start: report.start, endExclusive: report.end, calendar)
            let name = "\(member.displayName) \(label)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ",", with: "")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).csv")
            try data.write(to: url, options: .atomic)
            exportError = nil
            sharing = SharedFile(url: url)
        } catch {
            exportError = TeamErrors.message(error, needs: "The CSV")
        }
    }
}

/// The time card on paper: white in both modes, like the printed one.
private struct PaperCard: View {
    var member: Member
    var farm: Farm
    var report: Report
    var calendar: FarmCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TIME CARD").font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Palette.paperInk.opacity(0.6))
                Text(member.displayName).font(.tcTitle2).foregroundStyle(Palette.paperInk)
                Text("\(farm.name) · \(Fmt.rangeLabel(start: report.start, endExclusive: report.end, calendar))")
                    .font(.subheadline)
                    .foregroundStyle(Palette.paperInk.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Palette.paperInk.opacity(0.8)).frame(height: 1.5)
            if report.rows.isEmpty {
                Text("No shifts in these dates.")
                    .font(.body)
                    .foregroundStyle(Palette.paperInk.opacity(0.7))
                    .padding(.vertical, 8)
            }
            ForEach(Array(report.rows.enumerated()), id: \.element.shift.id) { index, row in
                if index > 0 { Rectangle().fill(Palette.paperInk.opacity(0.15)).frame(height: 1) }
                ReportLine(row: row, calendar: calendar)
            }
            Rectangle().fill(Palette.paperInk.opacity(0.8)).frame(height: 1.5)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total").font(.headline).foregroundStyle(Palette.paperInk)
                    Text("\(Fmt.plural(report.daysWorked, "day")) · \(Fmt.plural(report.totalTrees, "tree"))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.paperInk.opacity(0.7))
                }
                Spacer()
                Text.numberPhrase("\(Fmt.decimalHours(report.totalWorked)) hrs", .stat).foregroundStyle(Palette.paperInk)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("report-total")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

private struct ReportLine: View {
    var row: ReportRow
    var calendar: FarmCalendar

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.shortDay(row.shift.start, calendar)).font(.headline).foregroundStyle(Palette.paperInk)
                Spacer()
                Text.numberPhrase("\(Fmt.decimalHours(row.worked)) hrs").foregroundStyle(Palette.paperInk)
            }
            Text("\(Fmt.time(row.shift.start, calendar)) – \(row.shift.end.map { Fmt.time($0, calendar) } ?? "still on the clock") · \(Fmt.plural(row.trees, "tree"))")
                .font(.subheadline)
                .foregroundStyle(Palette.paperInk.opacity(0.75))
            ForEach(row.breakLines, id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(Palette.paperInk.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SharedFile: Identifiable {
    var url: URL
    var id: URL { url }
}

/// The share sheet for a file.
private struct ActivitySheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
