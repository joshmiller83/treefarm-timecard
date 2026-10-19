import Foundation
import PDFKit
import Testing
import TimeCardCore
@testable import TimeCard

/// The paper card, the CSV and the PDF, all from TreeFarmKit's `Report`.
@Suite("Report outputs")
struct ReportOutputTests {
    typealias F = LogReportFixture
    let cal = LogReportFixture.calendar
    let now = LogReportFixture.at(10, 19, 16, 31) // Mon, Oct 19, 4:31 PM

    /// Alex's last week: four shifts, one past midnight, breaks, notes and trees; Sam has one too.
    func lastWeek() -> (snapshot: FarmSnapshot, mon: Shift, thu: Shift) {
        let mon = F.shift(10, 12, from: (7, 2), to: (15, 31), breaks: [F.lunch(10, 12)])
        let tue = F.shift(10, 13, from: (6, 55), to: (15, 30),
                          breaks: [Break(kind: .break, start: F.at(10, 13, 9, 40), end: F.at(10, 13, 9, 52), reason: "Fuel run"), F.lunch(10, 13)],
                          notes: "Finished block 1, \"before\" the rain.")
        let thu = F.shift(10, 15, from: (18, 0), to: (1, 30), nextDay: true, notes: "=SUM(A1)")
        let fri = F.shift(10, 16, from: (7, 0), to: (12, 0))
        let sams = F.shift(F.sam, 10, 14, from: (7, 30), to: (16, 0), rate: 1800)
        let marks = F.marks(rows: 0...11, on: mon) + F.marks(rows: 12...12, on: mon, positions: 0..<4) + F.marks(rows: 13...15, on: tue)
            + F.marks(rows: 16...17, on: sams)
        return (F.snapshot(shifts: [mon, tue, thu, fri, sams], marks: marks), mon, thu)
    }

    func content(_ snapshot: FarmSnapshot, _ period: ReportPeriod = .lastWeek, user: UUID = LogReportFixture.me) -> ReportContent {
        ReportContent(snapshot: snapshot, farm: F.farm, request: ReportRequest(period: period, userId: user), now: now)
    }

    // MARK: Paper card

    @Test func theCardPrintsEachShiftAndTheTotals() {
        let card = content(lastWeek().snapshot).card
        #expect(card.farm == "Pine Hollow Tree Farm")
        #expect(card.whoLine == "Crew lead · Alex Rivera")
        #expect(card.range == "Oct 12 – Oct 18, 2026")
        #expect(card.rows.map(\.date) == ["Mon 10/12", "Tue 10/13", "Thu 10/15", "Fri 10/16"])
        #expect(card.rows.map(\.clockIn) == ["7:02 AM", "6:55 AM", "6:00 PM", "7:00 AM"])
        #expect(card.rows.map(\.clockOut) == ["3:31 PM", "3:30 PM", "1:30 AM", "12:00 PM"])
        #expect(card.rows.map(\.nextDay) == [false, false, true, false])
        #expect(card.rows.map(\.trees) == ["124", "30", "–", "–"])
        #expect(card.rows.map(\.hours) == ["7.98", "7.88", "7.50", "5.00"])
        #expect(card.rows[1].breaks == ["Break 12 min (Fuel run)", "Lunch 30 min"])
        #expect(card.rows[1].details.map(\.text) == ["Break 12 min (Fuel run) · Lunch 30 min", "Finished block 1, \"before\" the rain."])
        #expect(card.rows[1].details.map(\.label) == ["Breaks", "Notes"])
        #expect(card.totalHours == "28.37")
        #expect(card.totalTrees == "154")
        #expect(card.days == "4 days")
        #expect(card.totalsLine == "28.37 hours · 154 trees")
        #expect(card.prepared == "Prepared Mon, Oct 19 at 4:31 PM")
    }

    @Test func oneTreeIsATree() {
        let shift = F.shift(10, 16, from: (7, 0), to: (15, 30), breaks: [F.lunch(10, 16)])
        let card = content(F.snapshot(shifts: [shift], marks: F.marks(rows: 0...0, on: shift, positions: 0..<1))).card
        #expect(card.totalsLine == "8.00 hours · 1 tree")
        #expect(PaperTimeCard.treesText(card.rows[0].trees) == "1 tree")
        #expect(PaperTimeCard.treesText("–") == "no trees")
        #expect(PaperTimeCard.treesText("1,347") == "1,347 trees")
    }

    @Test func dateRangesWrapOnlyAtTheDash() {
        #expect("Oct 12 – Oct 18, 2026".wrappingOnlyAtDash == "Oct\u{00A0}12\u{00A0}– Oct\u{00A0}18,\u{00A0}2026")
        #expect("This week".wrappingOnlyAtDash == "This\u{00A0}week")
    }

    @MainActor
    @Test func theTreesCacheRebuildsOnlyWhenMarksChange() {
        let (snapshot, mon, _) = lastWeek()
        let cache = ShiftTreesCache()
        #expect(cache.trees(for: snapshot).count(mon.id) == 124)
        var more = snapshot
        for mark in F.marks(rows: 18...18, on: mon) { more.apply(.treeMark(mark)) }
        #expect(cache.trees(for: more).count(mon.id) == 134)
        #expect(cache.trees(for: snapshot).count(mon.id) == 124)
    }

    @Test func anOpenShiftSaysItsStillOnTheClock() {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 19, 7, 0), rateCents: 2000)
        let card = content(F.snapshot(shifts: [open]), .thisWeek).card
        #expect(card.rows[0].clockOut == "—")
        #expect(card.rows[0].stillOpen == "Still on the clock at 4:31 PM.")
        #expect(card.rows[0].details.last?.kind == .open)
        #expect(card.rows[0].hours == "9.52")
    }

    @Test func anAdminCanRunSomeoneElsesCard() {
        let report = content(lastWeek().snapshot, user: F.sam)
        #expect(report.card.whoLine == "Trimmer · Sam Ortiz")
        #expect(report.card.rows.count == 1)
        #expect(report.card.totalTrees == "20")
        #expect(report.days == 1)
    }

    @Test func anEmptyPeriodStillMakesACard() {
        let card = content(lastWeek().snapshot, .custom(from: F.day(2026, 9, 1), to: F.day(2026, 9, 7))).card
        #expect(card.rows.isEmpty)
        #expect(card.range == "Sep 1 – Sep 7, 2026")
        #expect(card.totalsLine == "0.00 hours · 0 trees")
        #expect(card.days == "0 days")
    }

    @Test func theFileNameIsSafeEverywhere() {
        var card = content(lastWeek().snapshot).card
        #expect(card.fileName == "Time Card – Alex Rivera – Oct 12 – Oct 18, 2026")
        card.worker = "A/B: \"C\""
        #expect(!card.fileName.contains("/"))
        #expect(!card.fileName.contains(":"))
        #expect(!card.fileName.contains("\""))
    }

    @Test func theCrewListPutsYouFirst() {
        var removed = Member(userId: UUID(), farmId: F.farmId, displayName: "Bea Lane", email: "bea@example.com", role: .worker)
        removed.removedAt = now
        let crew = ReportContent.crew(members: [F.samMember, removed, F.meMember], me: F.me)
        #expect(crew.map(\.name) == ["Alex Rivera (you)", "Bea Lane (removed)", "Sam Ortiz"])
    }

    // MARK: CSV

    @Test func theCSVHasOneRowPerShiftAndNoPay() {
        let csv = content(lastWeek().snapshot).csv
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "Name,Date,In,Out,Breaks,Hours,Trees,Notes")
        #expect(lines[1] == "Alex Rivera,2026-10-12,7:02 AM,3:31 PM,30,7.98,124,")
        #expect(lines[2] == "Alex Rivera,2026-10-13,6:55 AM,3:30 PM,42,7.88,30,\"Finished block 1, \"\"before\"\" the rain.\"")
        // A note that looks like a formula is defused.
        #expect(lines[3] == "Alex Rivera,2026-10-15,6:00 PM,1:30 AM,0,7.50,0,'=SUM(A1)")
        #expect(lines[4] == "Alex Rivera,2026-10-16,7:00 AM,12:00 PM,0,5.00,0,")
        #expect(lines.count == 6)
        #expect(lines[5].isEmpty)
        #expect(!csv.contains("$"))
        #expect(!csv.contains("Sam"))
    }

    @Test func csvQuotesLineBreaksOfEveryKind() {
        #expect(ReportCSV.row(["a\r\nb", "c\nd", "plain", "-5", "@x"]) == "\"a\r\nb\",\"c\nd\",plain,'-5,'@x\r\n")
    }

    @Test func theCSVLeavesOutForAnOpenShiftBlank() {
        let open = Shift(userId: F.me, farmId: F.farmId, start: F.at(10, 19, 7, 0), rateCents: 2000)
        let csv = content(F.snapshot(shifts: [open]), .thisWeek).csv
        #expect(csv.components(separatedBy: "\r\n")[1] == "Alex Rivera,2026-10-19,7:00 AM,,0,9.52,0,")
    }

    // MARK: PDF

    @Test func aWeekPrintsOnOneLetterPage() throws {
        let card = content(lastWeek().snapshot).card
        let data = ReportPDF.render(card)
        Artifacts.save(data, "week.pdf")
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        let page = try #require(pdf.page(at: 0))
        #expect(page.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        let text = try #require(pdf.string)
        for expected in ["TIME CARD", "Crew lead · Alex Rivera", "Oct 12 – Oct 18, 2026", "Pine Hollow Tree Farm",
                         "DATE", "IN", "OUT", "TREES", "HOURS", "Mon 10/12", "7:02 AM", "3:31 PM", "124", "7.98",
                         "Break 12 min (Fuel run) · Lunch 30 min", "+1 day", "28.37", "154", "4 days",
                         "Breaks are listed, not counted.", "Prepared Mon, Oct 19 at 4:31 PM", "Page 1 of 1"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        #expect(!text.contains("$"), "pay must never print")
    }

    @Test func aLongPeriodRunsOverSeveralNumberedPages() throws {
        // Every day for two months, each with a lunch and a long note: far more than a page.
        var shifts: [Shift] = []
        for offset in 0..<61 {
            let day = F.calendar.dayKey(F.calendar.addDays(F.at(8, 1, 12, 0), offset))
            let start = F.calendar.date(on: day, hour: 7, minute: 0)
            let lunch = Break(kind: .lunch, start: F.calendar.date(on: day, hour: 12, minute: 0), end: F.calendar.date(on: day, hour: 12, minute: 30))
            shifts.append(Shift(userId: F.me, farmId: F.farmId, start: start, end: start.addingTimeInterval(8.5 * 3600), breaks: [lunch],
                                notes: String(repeating: "Shaped the north rows and stacked brush by the lane. ", count: offset % 7 == 0 ? 20 : 1),
                                rateCents: 2000))
        }
        let card = content(F.snapshot(shifts: shifts), .custom(from: F.day(2026, 8, 1), to: F.day(2026, 9, 30))).card
        #expect(card.rows.count == 61)
        let layout = ReportPDF.Layout(card: card)
        let data = ReportPDF.render(card)
        Artifacts.save(data, "two-months.pdf")
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount > 2)
        #expect(pdf.pageCount == layout.pages.count)
        // Every shift prints exactly once, in order, and only the last page has the totals.
        #expect(layout.pages.flatMap(\.rows) == Array(0..<61))
        #expect(layout.pages.map(\.hasTotals) == Array(repeating: false, count: layout.pages.count - 1) + [true])
        let first = try #require(pdf.page(at: 0)?.string)
        #expect(first.contains("TIME CARD"))
        #expect(first.contains("Page 1 of \(pdf.pageCount)"))
        #expect(!first.contains("Breaks are listed, not counted."))
        let second = try #require(pdf.page(at: 1)?.string)
        #expect(second.contains("TIME CARD"))
        #expect(second.contains("HOURS"), "later pages repeat the column titles")
        #expect(second.contains("Page 2 of \(pdf.pageCount)"))
        let last = try #require(pdf.page(at: pdf.pageCount - 1)?.string)
        #expect(last.contains("Breaks are listed, not counted."))
        #expect(last.contains("488.00"))
        #expect(last.contains("61 days"))
    }

    @Test func rowsNeverSpillPastTheFooter() {
        let notes = String(repeating: "x", count: Limits.notes)
        let shifts = (0..<8).map { F.shift(10, 5 + $0, from: (7, 0), to: (15, 0), notes: notes) }
        let card = content(F.snapshot(shifts: shifts), .custom(from: F.day(2026, 10, 5), to: F.day(2026, 10, 12))).card
        let layout = ReportPDF.Layout(card: card)
        let bottom = ReportPDF.pageSize.height - ReportPDF.Layout.margin - ReportPDF.Layout.footerHeight
        for (n, page) in layout.pages.enumerated() {
            var y = n == 0
                ? ReportPDF.Layout.margin + ReportPDF.Layout.bandHeight + ReportPDF.Layout.bandGap + ReportPDF.Layout.columnHeaderHeight
                : ReportPDF.Layout.margin + ReportPDF.Layout.slimHeaderHeight + ReportPDF.Layout.columnHeaderHeight
            for i in page.rows { y += layout.rowHeights[i] }
            if page.hasTotals { y += ReportPDF.Layout.totalsHeight }
            #expect(y <= bottom, "page \(n + 1) runs to \(y)")
        }
        #expect(layout.pages.count >= 2)
    }

    @Test func anEmptyCardIsOnePageThatSaysSo() throws {
        let card = content(F.snapshot(shifts: []), .thisWeek).card
        let data = ReportPDF.render(card)
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.pageCount == 1)
        let text = try #require(pdf.string)
        #expect(text.contains("No shifts in these dates."))
        #expect(text.contains("0.00"))
    }

    @Test func exportFilesAreNamedForTheCard() throws {
        let report = content(lastWeek().snapshot)
        let pdfURL = try report.pdfFile.write()
        #expect(pdfURL.lastPathComponent == "Time Card – Alex Rivera – Oct 12 – Oct 18, 2026.pdf")
        #expect(PDFDocument(url: pdfURL)?.pageCount == 1)
        let csvURL = try report.csvFile.write()
        #expect(csvURL.pathExtension == "csv")
        #expect(try String(contentsOf: csvURL, encoding: .utf8) == report.csv)
    }
}

/// Saves generated files for a person to look at when `LOGREPORT_ARTIFACTS` names a folder
/// (pass it to xcodebuild as `TEST_RUNNER_LOGREPORT_ARTIFACTS`).
enum Artifacts {
    static func save(_ data: Data, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["LOGREPORT_ARTIFACTS"], !folder.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }
}
