import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Fmt dates and times")
struct FmtDateTests {
    typealias F = TimeFixture

    static let timeCases: [(String, String)] = [
        ("2026-10-18 07:02", "7:02 AM"), ("2026-10-18 00:05", "12:05 AM"), ("2026-10-18 12:00", "12:00 PM"),
        ("2026-10-18 16:31", "4:31 PM"), ("2026-10-18 23:59", "11:59 PM"), ("2026-10-18 10:00", "10:00 AM"),
    ]

    @Test(arguments: timeCases)
    func time(_ wall: String, _ text: String) {
        #expect(Fmt.time(F.wall(wall), F.indy) == text)
    }

    @Test func timeReadsInTheFarmsZone() {
        let d = F.at("2026-10-18T11:02:00Z")
        #expect(Fmt.time(d, F.indy) == "7:02 AM")
        #expect(Fmt.time(d, F.utc) == "11:02 AM")
    }

    static let spokenCases: [(String, String)] = [
        ("2026-10-18 07:02", "7:02"), ("2026-10-18 16:31", "4:31"), ("2026-10-18 12:01", "12:01"),
        ("2026-10-18 06:00", "6:00"), ("2026-10-18 17:59", "5:59"), ("2026-10-18 05:45", "5:45 AM"),
        ("2026-10-18 18:10", "6:10 PM"), ("2026-10-18 00:30", "12:30 AM"), ("2026-10-18 23:15", "11:15 PM"),
    ]

    @Test(arguments: spokenCases)
    func spokenTimeDropsAMPMOnlyInTheWorkday(_ wall: String, _ text: String) {
        #expect(Fmt.spokenTime(F.wall(wall), F.indy) == text)
    }

    @Test func dayLabels() {
        let d = F.wall("2026-10-18 16:31")
        #expect(Fmt.day(d, F.indy) == "Sun, Oct 18")
        #expect(Fmt.dayLong(d, F.indy) == "Sunday, Oct 18")
        #expect(Fmt.monthDay(d, F.indy) == "Oct 18")
        #expect(Fmt.shortDay(d, F.indy) == "Sun 10/18")
        let jan = F.wall("2026-01-05 08:00")
        #expect(Fmt.day(jan, F.indy) == "Mon, Jan 5")
        #expect(Fmt.dayLong(jan, F.indy) == "Monday, Jan 5")
        #expect(Fmt.shortDay(jan, F.indy) == "Mon 1/5")
        // Late evening in Indy is already tomorrow in UTC.
        let late = F.wall("2026-10-18 22:00")
        #expect(Fmt.day(late, F.utc) == "Mon, Oct 19")
    }

    @Test func everyMonthAndWeekdayName() {
        let months = (1...12).map { Fmt.monthDay(F.wall("2026-\($0)-01 12:00"), F.indy) }
        #expect(months == ["Jan 1", "Feb 1", "Mar 1", "Apr 1", "May 1", "Jun 1", "Jul 1", "Aug 1", "Sep 1", "Oct 1", "Nov 1", "Dec 1"])
        let days = (12...18).map { Fmt.dayLong(F.wall("2026-10-\($0) 12:00"), F.indy) }
        #expect(days == ["Monday, Oct 12", "Tuesday, Oct 13", "Wednesday, Oct 14", "Thursday, Oct 15", "Friday, Oct 16", "Saturday, Oct 17", "Sunday, Oct 18"])
    }

    @Test func rangeLabelForOneDay() {
        let a = F.wall("2026-10-18 00:00")
        #expect(Fmt.rangeLabel(start: a, endExclusive: F.indy.addDays(a, 1), F.indy) == "Oct 18, 2026")
        #expect(Fmt.rangeLabel(start: a, endExclusive: a, F.indy) == "Oct 18, 2026")
    }

    @Test func rangeLabelForAWeek() {
        let bounds = F.indy.weekBounds(containing: F.wall("2026-10-18 10:00"))
        #expect(Fmt.rangeLabel(start: bounds[0], endExclusive: bounds[7], F.indy) == "Oct 12 – Oct 18, 2026")
    }

    @Test func rangeLabelAcrossMonthsAndDST() {
        let sep = F.indy.weekBounds(containing: F.wall("2026-10-01 10:00"))
        #expect(Fmt.rangeLabel(start: sep[0], endExclusive: sep[7], F.indy) == "Sep 28 – Oct 4, 2026")
        let fallBack = F.indy.weekBounds(containing: F.wall("2026-11-01 10:00"))
        #expect(Fmt.rangeLabel(start: fallBack[0], endExclusive: fallBack[7], F.indy) == "Oct 26 – Nov 1, 2026")
        let march = F.indy.monthBounds(containing: F.wall("2026-03-08 10:00"))
        #expect(Fmt.rangeLabel(start: march.start, endExclusive: march.end, F.indy) == "Mar 1 – Mar 31, 2026")
    }

    @Test func rangeLabelAcrossYearsNamesBothYears() {
        let bounds = F.indy.weekBounds(containing: F.wall("2027-01-01 10:00"))
        #expect(Fmt.rangeLabel(start: bounds[0], endExclusive: bounds[7], F.indy) == "Dec 28, 2026 – Jan 3, 2027")
    }
}
