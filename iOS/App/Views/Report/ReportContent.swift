import Foundation
import TimeCardCore

/// The ranges the Report tab offers. Pick dates becomes `ReportPeriod.custom`.
enum ReportRange: String, CaseIterable, Hashable {
    case thisWeek, lastWeek, thisMonth, custom

    var title: String {
        switch self {
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .thisMonth: "This month"
        case .custom: "Pick dates"
        }
    }
}

/// Everything the Report tab shows for one person and period: the Kit report, the paper card,
/// and the CSV. Built fresh from the snapshot, so it follows every change.
struct ReportContent {
    var report: Report
    var card: PaperTimeCard
    var csv: String
    var workerName: String

    var hours: String { card.totalHours }
    var trees: String { card.totalTrees }
    var days: Int { report.daysWorked }

    init(snapshot: FarmSnapshot, farm: Farm, request: ReportRequest, now: Date) {
        let calendar = FarmCalendar(farm: farm)
        let trees = ShiftTrees(snapshot: snapshot)
        let worker = snapshot.members[request.userId]
        report = PaperTimeCard.report(for: request, shifts: snapshot.shifts.values, trees: trees, calendar: calendar, now: now)
        card = PaperTimeCard(report: report, farmName: farm.name, worker: worker, calendar: calendar, now: now)
        workerName = worker?.displayName ?? ""
        csv = ReportCSV.make(report: report, workerName: workerName, calendar: calendar, now: now)
    }

    var pdfFile: TimeCardPDFFile { TimeCardPDFFile(card: card) }
    var csvFile: TimeCardCSVFile { TimeCardCSVFile(csv: csv, fileName: card.fileName) }

    /// The people an admin can run a time card for: themself first, then the crew by name.
    /// Removed members stay (their hours still count) and say so.
    static func crew(members: some Sequence<Member>, me: UUID) -> [(id: UUID, name: String)] {
        let list = Array(members)
        let mine = list.filter { $0.userId == me }
        let others = list.filter { $0.userId != me }
            .sorted { ($0.displayName.lowercased(), $0.userId.uuidString) < ($1.displayName.lowercased(), $1.userId.uuidString) }
        return (mine + others).map { m in
            (m.userId, m.displayName + (m.userId == me ? " (you)" : m.removedAt != nil ? " (removed)" : ""))
        }
    }
}
