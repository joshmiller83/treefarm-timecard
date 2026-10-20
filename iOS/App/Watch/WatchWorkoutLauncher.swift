import Foundation
import HealthKit
import TreeFarmKit

// Starts the watch's shift workout after a phone clock-in (docs/watch.md 1.3 step 7):
// `HKHealthStore.startWatchApp` launches the watch app, whose `handle(_ workoutConfiguration:)`
// starts the session there. The bridge updates the application context first, because the
// configuration carries no shift; the watch reads the shift from the context.
//
// The completion can hang when the watch is off or off the wrist, so every launch has a
// timeout, and whichever of the two comes first is the answer (`ResumeOnce`).

enum WatchLaunchResult: Equatable, Sendable {
    case started
    case timedOut
    case failed(String)
    /// No paired watch, HealthKit unavailable, or a test host.
    case unavailable
}

protocol WatchWorkoutLauncher: Sendable {
    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult
}

/// The real one: `HKHealthStore.startWatchApp` with an outdoor `.other` configuration.
///
/// The iPhone doesn't ask for HealthKit authorization: the watch owns the session and asks there.
/// If a device run shows `startWatchApp` failing without it, the Settings toggle asks for share
/// `[workoutType]` only (docs/watch.md 2.4).
struct HealthKitWatchLauncher: WatchWorkoutLauncher {
    typealias Completion = @Sendable (Bool, (any Error)?) -> Void

    private let isAvailable: @Sendable () -> Bool
    private let startWatchApp: @Sendable (@escaping Completion) -> Void

    init() {
        let store = HKHealthStore()
        self.init(isAvailable: { HKHealthStore.isHealthDataAvailable() },
                  startWatchApp: { completion in
                      store.startWatchApp(with: Self.shiftConfiguration(), completion: completion)
                  })
    }

    /// For tests: whether HealthKit is there, and what `startWatchApp` does.
    init(isAvailable: @escaping @Sendable () -> Bool, startWatchApp: @escaping @Sendable (@escaping Completion) -> Void) {
        self.isAvailable = isAvailable
        self.startWatchApp = startWatchApp
    }

    /// The same configuration the watch's session uses: there's no gardening or occupational
    /// type, and Other is Apple's catch-all. Outdoor, with no location tracking.
    static func shiftConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .other
        configuration.locationType = .outdoor
        return configuration
    }

    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult {
        guard isAvailable() else { return .unavailable }
        let start = startWatchApp
        let result = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WatchLaunchResult, any Error>) in
            let once = ResumeOnce(continuation)
            let timer = Task {
                // Cancelled means the watch answered first.
                guard (try? await Task.sleep(for: timeout)) != nil else { return }
                once.resume(returning: .timedOut)
            }
            start { success, error in
                once.resume(returning: success ? .started : .failed(Self.reason(error)))
                timer.cancel()
            }
        }
        return result ?? .failed(Self.reason(nil))
    }

    private static func reason(_ error: (any Error)?) -> String {
        error?.localizedDescription ?? "The watch didn’t start the workout."
    }
}

/// For UI-test mode and test hosts: there is never a watch to start.
struct UnavailableWatchLauncher: WatchWorkoutLauncher {
    func startShiftWorkout(timeout: Duration) async -> WatchLaunchResult {
        .unavailable
    }
}
