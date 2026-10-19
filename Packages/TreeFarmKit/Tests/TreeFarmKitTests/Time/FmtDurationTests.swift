import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Fmt durations and money")
struct FmtDurationTests {
    static let h: TimeInterval = 3600

    static let hmsCases: [(Double, String)] = [
        (0.0, "0:00:00"), (59.6, "0:00:59"), (3600.0, "1:00:00"), (25 * h, "25:00:00"),
        (6 * h + 5 * 60 + 9, "6:05:09"), (-5.0, "0:00:00"),
    ]

    static let hmCases: [(Double, String)] = [
        (0.0, "0:00"), (59.6, "0:00"), (3600.0, "1:00"), (25 * h, "25:00"), (6 * h + 5 * 60 + 59, "6:05"), (-60.0, "0:00"),
    ]

    static let decimalHoursCases: [(Double, String)] = [
        (0.0, "0.00"), (59.6, "0.02"), (3600.0, "1.00"), (25 * h, "25.00"), (6 * h + 5 * 60, "6.08"),
        (6 * h + 5 * 60 + 9, "6.09"), (18.0, "0.01"), (17.9, "0.00"), (-100.0, "0.00"), (8.5 * h, "8.50"),
    ]

    static let minutesTextCases: [(Double, String)] = [
        (0.0, "0 min"), (29.0, "0 min"), (59.6, "1 min"), (45 * 60.0, "45 min"), (3600.0, "1 h"),
        (65 * 60.0, "1 h 5 min"), (25 * h, "25 h"), (119.6 * 60, "2 h"), (-60.0, "0 min"),
    ]

    static let hmWordsCases: [(Double, String)] = [
        (0.0, "0 h 0 min"), (59.6, "0 h 1 min"), (3600.0, "1 h 0 min"), (6 * h + 5 * 60, "6 h 5 min"), (25 * h, "25 h 0 min"),
    ]

    static let spokenDurationCases: [(Double, String)] = [
        (0.0, "less than a minute"), (29.0, "less than a minute"), (59.6, "1 minute"), (45 * 60.0, "45 minutes"),
        (3600.0, "1 hour"), (6 * h + 5 * 60, "6 hours 5 minutes"), (h + 60, "1 hour 1 minute"), (25 * h, "25 hours"),
        (2 * h + 40 * 60, "2 hours 40 minutes"),
    ]

    static let usdCases: [(Int, String)] = [
        (0, "$0.00"), (9450, "$94.50"), (5, "$0.05"), (100_000, "$1,000.00"), (123_456_789, "$1,234,567.89"), (-500, "-$5.00"), (-5, "-$0.05"),
    ]

    @Test(arguments: hmsCases)
    func hms(_ t: Double, _ text: String) {
        #expect(Fmt.hms(t) == text)
    }

    @Test(arguments: hmCases)
    func hm(_ t: Double, _ text: String) {
        #expect(Fmt.hm(t) == text)
    }

    @Test(arguments: decimalHoursCases)
    func decimalHours(_ t: Double, _ text: String) {
        #expect(Fmt.decimalHours(t) == text)
    }

    @Test(arguments: minutesTextCases)
    func minutesText(_ t: Double, _ text: String) {
        #expect(Fmt.minutesText(t) == text)
    }

    @Test(arguments: hmWordsCases)
    func hmWords(_ t: Double, _ text: String) {
        #expect(Fmt.hmWords(t) == text)
    }

    @Test(arguments: spokenDurationCases)
    func spokenDuration(_ t: Double, _ text: String) {
        #expect(Fmt.spokenDuration(t) == text)
    }

    @Test(arguments: usdCases)
    func usd(_ cents: Int, _ text: String) {
        #expect(Fmt.usd(cents: cents) == text)
    }

    @Test func pluralCountsAndGroupsThousands() {
        #expect(Fmt.plural(1, "tree") == "1 tree")
        #expect(Fmt.plural(0, "tree") == "0 trees")
        #expect(Fmt.plural(3, "tree") == "3 trees")
        #expect(Fmt.plural(8540, "tree") == "8,540 trees")
        #expect(Fmt.plural(2, "day") == "2 days")
    }
}
