import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("CSV export")
struct ExportTests {
    /// 2025-10-15 07:02 in Indianapolis (EDT, UTC-4).
    let morning = Date(timeIntervalSince1970: 1_760_526_120)

    @Test func quotingFollowsRFC4180() {
        #expect(CSV.field("plain") == "plain")
        #expect(CSV.field("a, b") == "\"a, b\"")
        #expect(CSV.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSV.field("two\nlines") == "\"two\nlines\"")
        // Spreadsheet formulas don't run from a note.
        #expect(CSV.field("=SUM(A1)") == "'=SUM(A1)")
        #expect(CSV.field("+1") == "'+1")
        #expect(CSV.row(["a", "b,c"]) == "a,\"b,c\"\r\n")
    }

    @Test func adminsExportEveryoneInTheFarmsTimeZone() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            var shift = farm.shift(for: sam, start: morning, end: morning.addingTimeInterval(8.5 * 3600), notes: "Rows 1–12, \"done\"\nNext: block 3")
            shift.breaks = [Break(kind: .lunch, start: morning.addingTimeInterval(4 * 3600), end: morning.addingTimeInterval(4.5 * 3600))]
            try await RecordStore(db: app.db).save(.shift(shift), farm: farm.farmId)
            let josh = farm.shift(for: farm.admin, start: morning.addingTimeInterval(-24 * 3600), end: morning.addingTimeInterval(-24 * 3600 + 3600))
            try await RecordStore(db: app.db).save(.shift(josh), farm: farm.farmId)
            var gone = farm.shift(for: sam, start: morning.addingTimeInterval(-48 * 3600), end: morning.addingTimeInterval(-47 * 3600))
            gone.deletedAt = clock.now
            try await RecordStore(db: app.db).save(.shift(gone), farm: farm.farmId)

            let res = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId), token: farm.admin.token)
            #expect(res.status == .ok)
            #expect(res.headers.contentType?.description.hasPrefix("text/csv") == true)
            #expect(res.headers.first(name: .contentDisposition)?.contains("attachment") == true)
            let expected = "Name,Date,In,Out,Breaks,Hours,Notes\r\n"
                + "Josh,2025-10-14,7:02 AM,8:02 AM,0,1.00,\r\n"
                + "Sam,2025-10-15,7:02 AM,3:32 PM,30,8.00,\"Rows 1–12, \"\"done\"\"\nNext: block 3\"\r\n"
            #expect(res.text == expected)
        }
    }

    @Test func workersExportOnlyTheirOwn() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            try await RecordStore(db: app.db).save(.shift(farm.shift(for: sam, start: morning, end: morning.addingTimeInterval(3600))), farm: farm.farmId)
            try await RecordStore(db: app.db).save(.shift(farm.shift(for: farm.admin, start: morning, end: morning.addingTimeInterval(3600))), farm: farm.farmId)

            let mine = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId), token: sam.token)
            #expect(mine.status == .ok)
            #expect(mine.text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == 2)
            #expect(!mine.text.contains("Josh"))
            let theirs = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId) + "?userId=\(farm.admin.userId)", token: sam.token)
            #expect(theirs.status == .forbidden)
            let own = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId) + "?userId=\(sam.userId)", token: sam.token)
            #expect(own.status == .ok)

            let adminForSam = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId) + "?userId=\(sam.userId)", token: farm.admin.token)
            #expect(!adminForSam.text.contains("Josh"))
            #expect(adminForSam.text.contains("Sam"))
        }
    }

    @Test func datesFilterByClockIn() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            for day in 0..<5 {
                let start = morning.addingTimeInterval(Double(day) * 86400)
                try await RecordStore(db: app.db).save(.shift(farm.shift(for: farm.admin, start: start, end: start.addingTimeInterval(3600))), farm: farm.farmId)
            }
            let from = morning.addingTimeInterval(86400).millis
            let to = morning.addingTimeInterval(3 * 86400).millis
            let res = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId) + "?from=\(from)&to=\(to)", token: farm.admin.token)
            let rows = res.text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.dropFirst()
            #expect(rows.map { $0.split(separator: ",")[1] } == ["2025-10-16", "2025-10-17"])
            let bad = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId) + "?from=yesterday", token: farm.admin.token)
            #expect(bad.status == .badRequest)
            _ = clock
        }
    }

    @Test func anOpenShiftCountsToNow() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            try await RecordStore(db: app.db).save(.shift(farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-2 * 3600))), farm: farm.farmId)
            let res = try await app.client2.send(.GET, APIPath.exportCSV(farm: farm.farmId), token: farm.admin.token)
            let row = try #require(res.text.components(separatedBy: "\r\n").dropFirst().first)
            let cols = row.split(separator: ",", omittingEmptySubsequences: false)
            #expect(cols[3] == "")
            #expect(cols[5] == "2.00")
        }
    }
}
