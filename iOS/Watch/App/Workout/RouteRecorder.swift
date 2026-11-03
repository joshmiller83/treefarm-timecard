import CoreLocation
import Foundation
import HealthKit

/// The Tree care workout's GPS route (docs/health.md 3), used only when the person turned on
/// Record route on the phone.
///
/// Location only ever goes into the workout builder's route, which Health saves with the workout.
/// It never goes to the phone, a file, the summary, the outbox or the tree map. GPS runs only
/// while the session runs, so lunch and breaks leave a gap in the map and cost no battery.
@MainActor
final class RouteRecorder: NSObject {
    /// Points go to Health in batches: one at a time fails on long routes.
    static let batchSize = 50
    /// Fixes less certain than this many meters are left out.
    static let maximumUncertainty: CLLocationAccuracy = 50

    private let manager = CLLocationManager()
    /// The session's builder. Its route is made at the first kept fix, so a shift with GPS off
    /// (or with no fix) saves no empty route.
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var buffer: [CLLocation] = []
    /// Inserts run one after another; a flush waits for the last.
    private var inserting: Task<Void, Never>?
    /// When updates last started: a cached fix from before then is left out.
    private var since: Date?
    private var authorizationWaiters: [CheckedContinuation<LocationAccess, Never>] = []
    /// Every fix as it arrives, unfiltered: the field log's only source of position, so there's
    /// never a second GPS (docs/gis.md 4 and 10).
    var onFixes: (([CLLocation]) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Every fix, about one a second: a 5 m filter left 60–90 s between fixes while circling a
        // tree, too few to place rows (docs/gis.md 10, Nov 2–3 logs).
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var access: LocationAccess { Self.access(manager.authorizationStatus) }

    /// "While using the app": a running workout session counts as using it. A request nobody
    /// answers (no prompt came) gives up after two minutes, so the card can't trap anyone.
    func requestAuthorization() async -> LocationAccess {
        guard access == .notDetermined else { return access }
        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            manager.requestWhenInUseAuthorization()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(120))
                self?.answerWaiters()
            }
        }
    }

    /// The session whose route this is. A new session starts a new route.
    func attach(_ builder: HKLiveWorkoutBuilder) {
        guard builder !== workoutBuilder else { return }
        stop()
        workoutBuilder = builder
        routeBuilder = nil
        buffer = []
    }

    /// GPS on only while the session runs, Record route is on and location is allowed.
    func update(running: Bool, wanted: Bool) {
        let on = running && wanted && workoutBuilder != nil && access == .authorized
        if on, since == nil {
            since = Date()
            manager.startUpdatingLocation()
        } else if !on, since != nil {
            stop()
        }
    }

    /// Sends what's waiting to the route, before the workout is saved. The workout builder
    /// finishes the route and attaches it when it saves; nothing calls `finishRoute`.
    func flush() async {
        send(buffer)
        buffer = []
        await inserting?.value
    }

    /// The session ended: no more GPS, and nothing kept here. A discarded workout takes its
    /// route with it.
    func detach() {
        stop()
        workoutBuilder = nil
        routeBuilder = nil
        buffer = []
    }

    private func stop() {
        guard since != nil else { return }
        since = nil
        manager.stopUpdatingLocation()
        send(buffer)
        buffer = []
    }

    private func receive(_ locations: [CLLocation]) {
        guard let since else { return }
        onFixes?(locations)
        buffer += locations.filter {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= Self.maximumUncertainty && $0.timestamp >= since
        }
        if buffer.count >= Self.batchSize {
            send(buffer)
            buffer = []
        }
    }

    private func send(_ batch: [CLLocation]) {
        guard !batch.isEmpty, let route = route() else { return }
        let previous = inserting
        inserting = Task {
            await previous?.value
            try? await route.insertRouteData(batch)
        }
    }

    private func route() -> HKWorkoutRouteBuilder? {
        if routeBuilder == nil {
            routeBuilder = workoutBuilder?.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
        }
        return routeBuilder
    }

    private func authorizationChanged() {
        guard access != .notDetermined else { return }
        answerWaiters()
    }

    private func answerWaiters() {
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume(returning: access) }
    }

    private static func access(_ status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }
}

// CoreLocation calls back on the main run loop, where the manager was made.
extension RouteRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        nonisolated(unsafe) let locations = locations
        MainActor.assumeIsolated { receive(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
