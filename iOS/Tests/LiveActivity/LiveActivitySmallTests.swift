import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

// STUB: slice c replaces
@Suite("Live Activity small layout")
struct LiveActivitySmallTests {
    @Test func theSmallLayoutIsBuiltIntoTheApp() {
        let snapshot = LiveSnapshot(phase: .working, timerStart: Date(), workedSoFar: 0, workedLabel: "worked today", breakStart: nil,
                                    breakReason: "", fieldName: "North", nextRows: [], shiftTrees: 0, fieldShaped: 0, fieldTotal: 0,
                                    lastAction: nil, canUndo: false)
        _ = LiveActivitySmallView(state: snapshot)
    }
}
