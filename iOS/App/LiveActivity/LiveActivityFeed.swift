import Foundation
import Observation
import TimeCardCore
import UIKit

/// What the lock screen should show, read from the session.
struct LiveActivityReading: Equatable {
    /// False while the app is still opening its store and session (or can't open them): a
    /// missing snapshot then means "not known yet", not "off the clock".
    var loaded: Bool
    /// Nil off the clock or signed out.
    var snapshot: LiveSnapshot?
    var attributes: TimeCardActivityAttributes?
}

extension AppModel {
    /// What the lock screen should show right now. Reading it from `withObservationTracking`
    /// tracks everything that changes it: the session's records, sign-in and farm.
    var liveActivityReading: LiveActivityReading {
        LiveActivityReading(loaded: storageError == nil && (session.me == nil || session.farm != nil),
                            snapshot: actions.liveSnapshot(),
                            attributes: activityAttributes)
    }
}

/// Keeps the Live Activity in step with the session, whatever changed it.
///
/// Field actions hand the controller a snapshot themselves, at once. Everything else that
/// changes what the lock screen should say reaches it here: a sync bringing rows other people
/// marked, or blocks that were moved or deleted; a shift edited in the app; signing out or
/// switching farms; the session finishing opening on a cold launch; and the app coming forward.
/// It reads with `withObservationTracking`, waits `settle` after a change so a burst of them
/// (a sync applies many records) makes one update, and reads again.
@MainActor
final class LiveActivityFeed {
    /// Quick enough that the lock screen follows an edit before the phone is back in a pocket.
    static let settle: Duration = .milliseconds(300)

    private let read: @MainActor () -> LiveActivityReading
    private let publish: @MainActor (LiveActivityReading) -> Void
    private let settle: Duration
    private let wakes: AsyncStream<Void>
    private let wake: AsyncStream<Void>.Continuation
    private var loop: Task<Void, Never>?
    private var foreground: (any NSObjectProtocol)?

    init(settle: Duration = LiveActivityFeed.settle, read: @escaping @MainActor () -> LiveActivityReading,
         publish: @escaping @MainActor (LiveActivityReading) -> Void) {
        self.settle = settle
        self.read = read
        self.publish = publish
        // One waiting wake-up is enough: each one reads everything again.
        (wakes, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    convenience init(controller: LiveActivityController, settle: Duration = LiveActivityFeed.settle,
                     read: @escaping @MainActor () -> LiveActivityReading) {
        self.init(settle: settle, read: read) { [weak controller] reading in
            controller?.update(reading.snapshot, attributes: reading.attributes, sessionLoaded: reading.loaded)
        }
    }

    func start() {
        guard loop == nil else { return }
        let wake = self.wake
        // Coming forward restarts an old activity (the 7 h 50 min reminder sends people here).
        foreground = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                            object: nil, queue: .main) { _ in wake.yield() }
        readAndPublish()
        loop = Task { [weak self, wakes, settle] in
            for await _ in wakes {
                try? await Task.sleep(for: settle)
                guard let self, !Task.isCancelled else { return }
                self.readAndPublish()
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        wake.finish()
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
        foreground = nil
    }

    /// Reads now, and asks to hear about the next change to anything it read.
    private func readAndPublish() {
        let wake = self.wake
        let reading = withObservationTracking { read() } onChange: { wake.yield() }
        publish(reading)
    }
}
