import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

@Suite("Hours and pay card")
struct HoursPayTests {
    let f = ClockFixture()

    @Test func todayAndTheWeekWithPayFromEachShiftsOwnRate() {
        let monday = f.shift(f.at(f.day(-2), 7, 0), f.at(f.day(-2), 15, 0), rateCents: 1600)
        let today = f.shift(f.today(7, 0))
        let h = HoursPay(state: f.state(shifts: [monday, today]), now: f.today(10, 0))
        #expect(h.todayHours == "3.00 hrs")
        #expect(h.weekHours == "11.00 hrs")
        #expect(h.todayPay == "$54.00")
        #expect(h.weekPay == "$182.00")
        #expect(h.days.map(\.label) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(h.days.map(\.hoursText) == ["8.00", "–", "3.00", "–", "–", "–", "–"])
        #expect(h.days.map(\.hours) == [8, 0, 3, 0, 0, 0, 0])
        #expect(h.days.map(\.isToday) == [false, false, true, false, false, false, false])
        #expect(h.days[0].spoken == "Monday, Oct 12: 8.00 hours")
        #expect(h.chartMax == 8)
        #expect(h.footnote(showPay: true) == "Week of Oct 12 – Oct 18, 2026 at $18.00 an hour. Breaks don’t count toward hours. Pay never shows on the report.")
        #expect(h.footnote(showPay: false) == "Week of Oct 12 – Oct 18, 2026. Breaks don’t count toward hours. Pay never shows on the report.")
        #expect(!h.needsRate)
    }

    @Test func aLongDayRaisesTheTopOfTheChart() {
        let long = f.shift(f.at(f.day(-1), 5, 0), f.at(f.day(-1), 15, 30))
        let h = HoursPay(state: f.state(shifts: [long]), now: f.today(10, 0))
        #expect(h.chartMax == 10.5)
    }

    @Test func noRateAsksForOne() {
        var me = f.me
        me.rateCents = 0
        let h = HoursPay(state: f.state(shifts: [f.shift(f.today(7, 0), rateCents: 0)], me: me), now: f.today(8, 0))
        #expect(h.needsRate)
        #expect(h.footnote(showPay: true) == "Week of Oct 12 – Oct 18, 2026. Breaks don’t count toward hours. Pay never shows on the report.")
    }
}

@Suite("Pace card")
struct PaceCardTests {
    let f = ClockFixture()

    @Test func noTreesNoCard() {
        let open = f.shift(f.today(7, 0))
        #expect(PaceCard(state: f.state(shifts: [open]), now: f.today(9, 0), showPay: true) == nil)
    }

    @Test func todayThisWeekAndTheSeason() {
        // Last week: 4 hours, 4 rows (40 trees). Monday: 2 hours, 2 rows. Today: 1 hour so far, 3 rows.
        let lastWeek = f.shift(f.at(f.day(-8), 7, 0), f.at(f.day(-8), 11, 0))
        let monday = f.shift(f.at(f.day(-2), 7, 0), f.at(f.day(-2), 9, 0))
        let today = f.shift(f.today(7, 0))
        let marks = f.marks(rows: 0...3, on: lastWeek) + f.marks(rows: 4...5, on: monday) + f.marks(rows: 6...8, on: today)
        let pace = try! #require(PaceCard(state: f.state(shifts: [lastWeek, monday, today], marks: marks), now: f.today(8, 0), showPay: true))

        #expect(pace.headline == "30 trees an hour today. Your season pace is 13 an hour.")
        #expect(pace.columns.map(\.title) == ["Today", "This week", "Season"])
        #expect(pace.columns.map(\.rate) == ["30.0", "16.7", "12.9"])
        #expect(pace.columns.map(\.trees) == ["30 trees", "50 trees", "90 trees"])
        #expect(pace.columns.map(\.each) == ["2:00/tree", "3:36/tree", "4:40/tree"])
        #expect(pace.columns.map(\.payEach) == ["$0.60/tree", "$1.08/tree", "$1.40/tree"])
        #expect(pace.columns.map(\.isNow) == [true, false, false])
        #expect(pace.notes == [
            "Today you’re 200% faster than your other days.",
            "Best day: Wed, Oct 14, 30.0 trees an hour (30 trees).",
            "110 trees left in North Field. At your season pace that’s about 8.5 hours of work, or about $154.",
        ])
    }

    @Test func hiddenPayStaysHidden() {
        let monday = f.shift(f.at(f.day(-2), 7, 0), f.at(f.day(-2), 9, 0))
        let pace = try! #require(PaceCard(state: f.state(shifts: [monday], marks: f.marks(rows: 0...1, on: monday)), now: f.today(8, 0), showPay: false))
        #expect(pace.columns.allSatisfy { $0.payEach == nil })
        #expect(pace.columns[0].rate == "–")
        #expect(pace.columns[0].trees == "0 trees")
        #expect(pace.columns[0].each == "–")
        #expect(!pace.columns[0].isNow)
        #expect(pace.notes == ["180 trees left in North Field. At your season pace that’s about 18 hours of work."])
    }

    @Test func steadyDaysAreOnPace() {
        let monday = f.shift(f.at(f.day(-2), 7, 0), f.at(f.day(-2), 8, 0))
        let today = f.shift(f.today(7, 0))
        let marks = f.marks(rows: 0...1, on: monday) + f.marks(rows: 2...3, on: today)
        let pace = try! #require(PaceCard(state: f.state(shifts: [monday, today], marks: marks), now: f.today(8, 1), showPay: false))
        #expect(pace.notes.first == "Today you’re right on your usual pace.")
    }

    @Test func aFinishedFieldSaysSo() {
        let monday = f.shift(f.at(f.day(-2), 7, 0), f.at(f.day(-2), 9, 0))
        let marks = f.marks(rows: 0...9, on: monday) + f.marks(block: f.block2, rows: 0...9, on: monday)
        let pace = try! #require(PaceCard(state: f.state(shifts: [monday], marks: marks), now: f.today(8, 0), showPay: false))
        #expect(pace.notes == ["Every tree in North Field is shaped."])
    }
}
