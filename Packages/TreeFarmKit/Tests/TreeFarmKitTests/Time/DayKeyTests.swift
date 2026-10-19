import Foundation
import Testing
@testable import TreeFarmKit

@Suite("DayKey")
struct DayKeyTests {
    @Test func parsesAndPrintsISODays() throws {
        let key = try #require(DayKey("2026-10-18"))
        #expect(key == DayKey(year: 2026, month: 10, day: 18))
        #expect(key.description == "2026-10-18")
        #expect(DayKey(year: 2026, month: 1, day: 5).description == "2026-01-05")
        #expect(DayKey("2026-1-5") == DayKey(year: 2026, month: 1, day: 5))
        #expect(DayKey(year: 987, month: 12, day: 31).description == "0987-12-31")
    }

    @Test(arguments: ["", "abc", "2026-10", "2026/10/18", "2026-10-18x", "2026-13-01", "2026-00-10", "2026-02-29", "2026-04-31", "2026-10-00", "-2026-10-18", "2026--10-18", "20260-10-18"])
    func rejectsDaysThatDontExist(_ text: String) {
        #expect(DayKey(text) == nil)
    }

    @Test func knowsLeapDays() {
        #expect(DayKey("2028-02-29") != nil)
        #expect(DayKey("2000-02-29") != nil)
        #expect(DayKey("2100-02-29") == nil)
    }

    @Test func sortsByDate() {
        let a = DayKey(year: 2026, month: 9, day: 30)
        let b = DayKey(year: 2026, month: 10, day: 1)
        let c = DayKey(year: 2027, month: 1, day: 1)
        #expect(a < b && b < c)
        #expect([c, a, b].sorted() == [a, b, c])
    }

    @Test func encodesAsAPlainString() throws {
        let data = try JSONCoding.encoder().encode([DayKey(year: 2026, month: 10, day: 18)])
        #expect(String(data: data, encoding: .utf8) == #"["2026-10-18"]"#)
        let back = try JSONCoding.decoder().decode([DayKey].self, from: data)
        #expect(back == [DayKey(year: 2026, month: 10, day: 18)])
    }

    @Test func refusesToDecodeABadDay() {
        let json = #"["2026-02-30"]"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) { try JSONCoding.decoder().decode([DayKey].self, from: json) }
    }
}
