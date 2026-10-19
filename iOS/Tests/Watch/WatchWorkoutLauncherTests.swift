import Foundation
import Testing
@testable import TimeCard

// STUB: slice b replaces
@Suite("Watch workout launcher")
struct WatchWorkoutLauncherTests {
    @Test func aTestHostNeverStartsAWatchWorkout() async {
        #expect(await UnavailableWatchLauncher().startShiftWorkout(timeout: .seconds(1)) == .unavailable)
    }
}
