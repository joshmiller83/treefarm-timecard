import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Card and voice agree")
struct FmtRoundingTests {
    @Test func oneMinuteFortyFiveIsTwoMinutesOnBoth() {
        #expect(Fmt.hmRounded(105) == "0:02")
        #expect(Fmt.spokenDuration(105) == "2 minutes")
        #expect(Fmt.hmRounded(6 * 3600 + 4 * 60 + 31) == "6:05")
        #expect(Fmt.spokenDuration(6 * 3600 + 4 * 60 + 31) == "6 hours 5 minutes")
    }
}
