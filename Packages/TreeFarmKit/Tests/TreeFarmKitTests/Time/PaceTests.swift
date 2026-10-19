import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Pace")
struct PaceTests {
    typealias F = TimeFixture
    let now = F.wall("2026-10-18 10:00")

    func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    @Test func onlyShiftsWithTreesCount() {
        let a = F.shift("2026-10-12 07:00", "2026-10-12 11:00")
        let unmarked = F.shift("2026-10-13 07:00", "2026-10-13 09:00")
        let c = F.shift("2026-10-14 07:00", "2026-10-14 09:00")
        let deleted = F.shift("2026-10-15 07:00", "2026-10-15 12:00", deleted: true)
        let trees: [UUID: Int] = [a.id: 120, c.id: 40, deleted.id: 99]
        let p = Pace.stats([a, unmarked, c, deleted], now: now) { trees[$0.id] ?? 0 }
        #expect(p.trees == 160)
        #expect(p.worked == F.hours(6))
        #expect(near(p.treesPerHour, 160.0 / 6))
        #expect(near(p.minutesPerTree, 2.25))
        #expect(p.payCentsPerTree == 56) // $90 over 160 trees is 56.25 cents
    }

    @Test func payPerTreeUsesEachShiftsOwnRate() {
        let a = F.shift("2026-10-12 07:00", "2026-10-12 11:00", rateCents: 1500)
        let b = F.shift("2026-10-13 07:00", "2026-10-13 09:00", rateCents: 2100)
        let p = Pace.stats([a, b], now: now) { $0.id == a.id ? 60 : 40 }
        #expect(p.payCentsPerTree == 102) // (6000 + 4200) / 100
    }

    @Test func noTreesMeansNoPace() {
        let p = Pace.stats([F.shift("2026-10-12 07:00", "2026-10-12 11:00")], now: now) { _ in 0 }
        #expect(p == PaceStats(trees: 0, worked: 0, treesPerHour: 0, minutesPerTree: 0, payCentsPerTree: 0))
        #expect(Pace.stats([], now: now) { _ in 0 }.trees == 0)
    }

    @Test func theOpenShiftCountsUpToNow() {
        let open = F.shift("2026-10-18 08:00", nil, breaks: [F.rest("2026-10-18 09:30", nil)])
        let p = Pace.stats([open], now: now) { _ in 45 }
        #expect(p.worked == F.hours(1.5))
        #expect(near(p.treesPerHour, 30))
    }

    @Test func bestDayNeedsHalfAnHour() throws {
        let mon = F.shift("2026-10-12 07:00", "2026-10-12 10:00")      // 90 trees in 3 h = 30/h
        let tue1 = F.shift("2026-10-13 07:00", "2026-10-13 08:00")     // with tue2: 80 trees in 5.5 h
        let tue2 = F.shift("2026-10-13 20:00", "2026-10-14 00:30")
        let tueUnmarked = F.shift("2026-10-13 12:00", "2026-10-13 18:00") // no trees, so not counted
        let wed = F.shift("2026-10-14 07:00", "2026-10-14 07:20")      // 30 trees in 20 min, too short to count
        let gone = F.shift("2026-10-15 07:00", "2026-10-15 08:00", deleted: true)
        let trees: [UUID: Int] = [mon.id: 90, tue1.id: 50, tue2.id: 30, wed.id: 30, gone.id: 500]
        let shifts = [mon, tue1, tue2, tueUnmarked, wed, gone]
        let best = try #require(Pace.bestDay(shifts, now: now, calendar: F.indy) { trees[$0.id] ?? 0 })
        #expect(best.day == DayKey(year: 2026, month: 10, day: 12))
        #expect(near(best.treesPerHour, 30))
        #expect(best.trees == 90)
    }

    @Test func bestDayPicksTheFastestQualifyingDay() throws {
        let mon = F.shift("2026-10-12 07:00", "2026-10-12 10:00")  // 30/h
        let tue = F.shift("2026-10-13 23:00", "2026-10-14 01:00")  // past midnight, Tuesday: 40/h
        let wed = F.shift("2026-10-14 07:00", "2026-10-14 07:30")  // exactly 30 min: 20/h
        let trees: [UUID: Int] = [mon.id: 90, tue.id: 80, wed.id: 10]
        let best = try #require(Pace.bestDay([mon, tue, wed], now: now, calendar: F.indy) { trees[$0.id] ?? 0 })
        #expect(best.day == DayKey(year: 2026, month: 10, day: 13))
        #expect(near(best.treesPerHour, 40))
        #expect(best.trees == 80)
    }

    @Test func bestDayTiesGoToTheLatestDay() throws {
        let mon = F.shift("2026-10-12 07:00", "2026-10-12 08:00")
        let tue = F.shift("2026-10-13 07:00", "2026-10-13 08:00")
        let best = try #require(Pace.bestDay([mon, tue], now: now, calendar: F.indy) { _ in 30 })
        #expect(best.day == DayKey(year: 2026, month: 10, day: 13))
    }

    @Test func noBestDayWithoutAQualifyingDay() {
        let short = F.shift("2026-10-12 07:00", "2026-10-12 07:29")
        #expect(Pace.bestDay([short], now: now, calendar: F.indy) { _ in 30 } == nil)
        #expect(Pace.bestDay([F.shift("2026-10-12 07:00", "2026-10-12 10:00")], now: now, calendar: F.indy) { _ in 0 } == nil)
    }

    @Test func hoursLeftAtThisPace() {
        #expect(Pace.hoursLeft(treesLeft: 100, treesPerHour: 25) == 4)
        #expect(Pace.hoursLeft(treesLeft: 0, treesPerHour: 25) == 0)
        #expect(Pace.hoursLeft(treesLeft: -5, treesPerHour: 25) == 0)
        #expect(Pace.hoursLeft(treesLeft: 100, treesPerHour: 0) == nil)
        #expect(Pace.hoursLeft(treesLeft: 100, treesPerHour: .nan) == nil)
    }

    static let rateCases: [(Double, String)] = [
        (160.0 / 6, "26.7"), (34.25, "34.3"), (0, "0.0"), (7, "7.0"), (100, "100"), (152.5, "153"), (99.96, "100.0"), (.infinity, "–"),
    ]

    @Test(arguments: rateCases)
    func rateText(_ x: Double, _ text: String) {
        #expect(Pace.rateText(x) == text)
    }

    static let eachCases: [(Double, String)] = [
        (0, "–"), (2.25, "2:15"), (0.75, "45 sec"), (2.999, "3:00"), (0.999, "1:00"), (1, "1:00"), (12.5, "12:30"), (.nan, "–"),
    ]

    @Test(arguments: eachCases)
    func eachText(_ m: Double, _ text: String) {
        #expect(Pace.eachText(minutes: m) == text)
    }

    static let hoursCases: [(Double, String)] = [
        (0.5, "30 minutes"), (0.001, "1 minute"), (0.999, "1 hour"), (1, "1 hour"), (1.2, "1 hour"), (3.4, "3.5 hours"),
        (3.2, "3 hours"), (12.76, "13 hours"), (40.3, "40.5 hours"),
    ]

    @Test(arguments: hoursCases)
    func hoursWords(_ h: Double, _ text: String) {
        #expect(Pace.hoursWords(h) == text)
    }
}
