import Foundation
import HealthKit
import Synchronization
import Testing
@testable import TimeCard

/// Starting the watch's shift workout after a phone clock-in (`HKHealthStore.startWatchApp`),
/// whose completion can hang when the watch is off, so it has a timeout (docs/watch.md 1.3 step 7).
@Suite("Watch workout launcher")
struct WatchWorkoutLauncherTests {
    /// A `startWatchApp` that answers the way a test says, and counts its calls.
    final class FakeStart: Sendable {
        enum Answer: Sendable { case success, failure(String), never, late(Duration) }
        let answer: Answer
        private let calls = Mutex(0)
        var count: Int { calls.withLock { $0 } }

        init(_ answer: Answer) { self.answer = answer }

        func callAsFunction(_ completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
            calls.withLock { $0 += 1 }
            switch answer {
            case .success: completion(true, nil)
            case .failure(let message): completion(false, NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
            case .never: break
            case .late(let delay):
                Task {
                    try? await Task.sleep(for: delay)
                    completion(true, nil)
                }
            }
        }
    }

    func launcher(_ start: FakeStart, available: Bool = true) -> HealthKitWatchLauncher {
        HealthKitWatchLauncher(isAvailable: { available }, startWatchApp: { start($0) })
    }

    @Test func aTestHostNeverStartsAWatchWorkout() async {
        #expect(await UnavailableWatchLauncher().startShiftWorkout(timeout: .seconds(1)) == .unavailable)
    }

    @Test func theShiftIsAnOutdoorOtherWorkout() {
        let configuration = HealthKitWatchLauncher.shiftConfiguration()
        #expect(configuration.activityType == .other)
        #expect(configuration.locationType == .outdoor)
    }

    @Test func aLaunchTheWatchConfirmsHasStarted() async {
        let start = FakeStart(.success)
        #expect(await launcher(start).startShiftWorkout(timeout: .seconds(10)) == .started)
        #expect(start.count == 1)
    }

    @Test func aLaunchThatFailsSaysWhy() async {
        let start = FakeStart(.failure("The watch is locked."))
        #expect(await launcher(start).startShiftWorkout(timeout: .seconds(10)) == .failed("The watch is locked."))
    }

    @Test func aLaunchThatNeverAnswersTimesOut() async {
        let clock = ContinuousClock()
        let began = clock.now
        #expect(await launcher(FakeStart(.never)).startShiftWorkout(timeout: .milliseconds(100)) == .timedOut)
        #expect(clock.now - began < .seconds(5))
    }

    @Test func anAnswerAfterTheTimeoutIsIgnored() async throws {
        let start = FakeStart(.late(.milliseconds(300)))
        #expect(await launcher(start).startShiftWorkout(timeout: .milliseconds(50)) == .timedOut)
        // The late completion arrives and resumes nothing twice.
        try await Task.sleep(for: .milliseconds(500))
        #expect(start.count == 1)
    }

    @Test func withoutHealthKitNothingIsLaunched() async {
        let start = FakeStart(.success)
        #expect(await launcher(start, available: false).startShiftWorkout(timeout: .seconds(10)) == .unavailable)
        #expect(start.count == 0)
    }

    @Test func twoLaunchesAreAnsweredSeparately() async {
        let launcher = launcher(FakeStart(.success))
        async let first = launcher.startShiftWorkout(timeout: .seconds(10))
        async let second = launcher.startShiftWorkout(timeout: .seconds(10))
        #expect(await [first, second] == [.started, .started])
    }
}
