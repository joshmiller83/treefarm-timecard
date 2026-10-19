import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Speech")
struct SpeechTests {
    typealias T = TimeFixture

    @Test func aShiftLeftOpenSaysWhenItStarted() {
        let shift = T.shift("2026-10-17 07:00", nil)
        #expect(Speech.clockedInSince(shift, calendar: T.indy) == "You’ve been clocked in since Sat, Oct 17 at 7:00 AM.")
        #expect(Speech.fixTheTimes == "If you forgot to clock out, fix the times.")
    }

    @Test func aSaveThatFailedOnThePhone() {
        #expect(Speech.saveFailed == "Couldn’t save that on this phone. Try again.")
    }
}
