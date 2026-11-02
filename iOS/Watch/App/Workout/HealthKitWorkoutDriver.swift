import Foundation
import HealthKit
import Synchronization
import TreeFarmKit

/// The real `WorkoutDriver`: one `HKWorkoutSession` with its `HKLiveWorkoutBuilder` (docs/watch.md 2).
///
/// HealthKit calls its delegates on its own queues, so those methods are `nonisolated` and only
/// yield into `events` (consumed by `ShiftWorkout` on the main actor) or touch the lock-guarded
/// `Shared` below. Closures written here never assume the main actor. [HK-P8]
@MainActor
final class HealthKitWorkoutDriver: NSObject, WorkoutDriver {
    enum DriverError: Error { case noSession }

    /// Bumped when Time Card starts reading a new type from Health, so a watch that answered an
    /// older request sees the card once more (docs/health.md 2). 2: steps and distance.
    static let readVersion = 2
    static let readVersionKey = "workout.healthReadVersion"
    /// The types collected beside the defaults for Other.
    static let movementTypes = [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning)]

    private let healthStore = HKHealthStore()
    private let store: WorkoutStore
    private let defaults: UserDefaults
    private let route = RouteRecorder()
    /// Record route is on and location allowed (`recordRoute(_:)`).
    private var routeWanted = false
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var local: WorkoutLocal {
        didSet { if local != oldValue { store.save(local) } }
    }

    let events: AsyncStream<WorkoutDriverEvent>
    private let continuation: AsyncStream<WorkoutDriverEvent>.Continuation

    /// What the HealthKit delegates share with the main actor, one session at a time.
    private struct Shared {
        /// The session and builder in use. Callbacks from any other (one we ended ourselves, whose
        /// `.ended` can arrive after the next session started) are ignored.
        var session: ObjectIdentifier?
        var builder: ObjectIdentifier?
        var reportedUnexpectedEnd = false
        var failure: String?
        /// A `stop` waiting for `.stopped`.
        var stoppedWaiter: ResumeOnce<Void>?
    }

    private let shared = Mutex(Shared())

    init(store: WorkoutStore = WorkoutStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        self.local = store.local()
        (events, continuation) = AsyncStream.makeStream()
        super.init()
    }

    // MARK: Authorization

    func authorizationStatus() -> HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        switch healthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    /// Share workouts (and their routes); read heart rate, active energy, steps and distance.
    /// Nothing more. [HK-F16]
    func requestAuthorization() async -> HealthAccess {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let read = Set<HKObjectType>([HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)] + Self.movementTypes)
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            defaults.set(Self.readVersion, forKey: Self.readVersionKey)
        } catch {}
        return authorizationStatus()
    }

    var asksForMore: Bool {
        authorizationStatus() == .authorized && defaults.integer(forKey: Self.readVersionKey) < Self.readVersion
    }

    // MARK: The route (docs/health.md 3)

    func locationStatus() -> LocationAccess { route.access }

    func requestLocation() async -> LocationAccess {
        let access = await route.requestAuthorization()
        updateRoute()
        return access
    }

    func recordRoute(_ on: Bool) {
        routeWanted = on
        updateRoute()
    }

    /// GPS only while the session runs.
    private func updateRoute() {
        route.update(running: session != nil && local.phase == .running, wanted: routeWanted)
    }

    // MARK: The session

    func start(at date: Date, shiftId: UUID?, origin: WorkoutLocal.Origin) async throws {
        let configuration = WorkoutMetadata.configuration()
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = Self.dataSource(healthStore, configuration)
        attach(session, builder)
        session.startActivity(with: date)
        do {
            try await builder.beginCollection(at: date)
        } catch {
            endSession()
            throw error
        }
        local = local.started(at: date, shiftId: shiftId, origin: origin, syncIdentifier: UUID())
        updateRoute()
    }

    func tag(shiftId: UUID) {
        local = local.tagged(shiftId)
    }

    /// `pause()` takes no date, so Health's active time can differ from paid time by seconds.
    /// The time card is the truth. [HK-F2, HK-P5]
    func pause() {
        session?.pause()
        local = local.with(phase: .paused)
        updateRoute()
    }

    func resume() {
        session?.resume()
        local = local.with(phase: .running)
        updateRoute()
    }

    func stop(at date: Date) async throws {
        guard let session else { throw DriverError.noSession }
        await stopActivity(session, at: date)
        local = local.stopped(at: date)
        updateRoute()
    }

    func finish(at end: Date, timeZone: String) async throws -> WorkoutSummary? {
        guard let session, let builder else {
            local = local.ended()
            return nil
        }
        do {
            await stopActivity(session, at: end)
            // The last of the route goes in before the workout saves and attaches it.
            route.update(running: false, wanted: false)
            await route.flush()
            try await builder.endCollection(at: end)
            let active = builder.elapsedTime(at: end)
            // A mistaken clock-in leaves no junk workout. [HK-P14]
            guard active >= WorkoutPlan.minimumDuration else {
                builder.discardWorkout()
                endLocally()
                return nil
            }
            try await builder.addMetadata(WorkoutMetadata.make(local: local, timeZone: timeZone))
            _ = try await builder.finishWorkout()
            let summary = Self.summary(of: builder, local: local, end: end, active: active)
            endLocally()
            return summary
        } catch {
            endLocally()
            throw error
        }
    }

    func salvage(at date: Date, timeZone: String) async -> WorkoutSummary? {
        let summary = (try? await finish(at: date, timeZone: timeZone)) ?? nil
        local = local.endedUnexpectedly()
        return summary
    }

    func discard() async {
        builder?.discardWorkout()
        endLocally()
    }

    /// A new data source and both delegates on the recovered session. [HK-F10, HK-R8]
    func recover() async -> Bool {
        if session != nil { return true }
        guard let recovered = (try? await healthStore.recoverActiveWorkoutSession()) ?? nil else {
            local = local.lost()
            return false
        }
        let builder = recovered.associatedWorkoutBuilder()
        builder.dataSource = Self.dataSource(healthStore, recovered.workoutConfiguration)
        attach(recovered, builder)
        var restored = local
        restored.phase = Self.phase(of: recovered.state)
        if restored.phase == .stopped, restored.stoppedAt == nil {
            // A stopped session without its stop time would never reach the 60-minute rule.
            restored.stoppedAt = recovered.endDate ?? Date()
        }
        restored.startedAt = restored.startedAt ?? recovered.startDate ?? builder.startDate
        restored.syncIdentifier = restored.syncIdentifier ?? UUID()
        restored.origin = restored.origin ?? .recovered
        local = restored
        updateRoute()
        return true
    }

    // MARK: Helpers

    private func attach(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder) {
        shared.withLock { $0 = Shared(session: ObjectIdentifier(session), builder: ObjectIdentifier(builder)) }
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        route.attach(builder)
    }

    /// The live data source: Other's defaults, plus steps and distance (docs/health.md 2).
    private static func dataSource(_ healthStore: HKHealthStore, _ configuration: HKWorkoutConfiguration) -> HKLiveWorkoutDataSource {
        let source = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        for type in movementTypes { source.enableCollection(for: type, predicate: nil) }
        return source
    }

    private func endLocally() {
        endSession()
        local = local.ended()
    }

    /// Ends the session on purpose: from here its callbacks are ignored, so its `.ended` isn't
    /// mistaken for an end from outside.
    private func endSession() {
        let waiter = shared.withLock { shared in
            defer { shared = Shared() }
            return shared.stoppedWaiter
        }
        waiter?.resume(returning: ())
        route.detach()
        session?.end()
        session = nil
        builder = nil
    }

    /// `stopActivity(with:)`, then wait for `.stopped` (never more than 5 seconds).
    private func stopActivity(_ session: HKWorkoutSession, at date: Date) async {
        guard session.state != .stopped, session.state != .ended else { return }
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let once = ResumeOnce(continuation)
            shared.withLock { $0.stoppedWaiter = once }
            session.stopActivity(with: date)
            if session.state == .stopped || session.state == .ended { once.resume(returning: ()) }
            Task {
                try? await Task.sleep(for: .seconds(5))
                once.resume(returning: ())
            }
        }
    }

    private static func phase(of state: HKWorkoutSessionState) -> WorkoutLocal.Phase {
        switch state {
        case .paused: .paused
        case .stopped: .stopped
        case .ended: .ended
        default: .running
        }
    }

    private static func summary(of builder: HKLiveWorkoutBuilder, local: WorkoutLocal, end: Date, active: TimeInterval) -> WorkoutSummary {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = builder.statistics(for: HKQuantityType(.heartRate))
        let energy = builder.statistics(for: HKQuantityType(.activeEnergyBurned))
        let (steps, meters) = movement(of: builder)
        return WorkoutSummary(shiftId: local.shiftId, start: local.startedAt ?? builder.startDate ?? end, end: end,
                              activeDuration: active,
                              activeKcal: energy?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                              avgHeartRate: heart?.averageQuantity()?.doubleValue(for: bpm),
                              maxHeartRate: heart?.maximumQuantity()?.doubleValue(for: bpm),
                              steps: steps, distanceMeters: meters)
    }

    /// Steps and meters so far. Distance is the watch's stride estimate, refined by GPS when
    /// Record route is on.
    nonisolated private static func movement(of builder: HKWorkoutBuilder) -> (steps: Double?, meters: Double?) {
        (builder.statistics(for: HKQuantityType(.stepCount))?.sumQuantity()?.doubleValue(for: .count()),
         builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()))
    }
}

// MARK: - HealthKit's delegates (its own queues)

extension HealthKitWorkoutDriver: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard isCurrent(workoutSession) else { return }
        switch toState {
        case .running:
            continuation.yield(.phase(.running))
        case .paused:
            continuation.yield(.phase(.paused))
        case .stopped:
            wakeStop()
            continuation.yield(.phase(.stopped))
        case .ended:
            // Still the current session, so nobody here ended it.
            wakeStop()
            reportUnexpectedEnd()
        default:
            break
        }
    }

    /// Another workout starting, the user leaving the app, or the system: the session ends, and
    /// the `.ended` change (before or after this) reports it once.
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        guard isCurrent(workoutSession) else { return }
        shared.withLock { $0.failure = error.localizedDescription }
        if workoutSession.state == .ended { reportUnexpectedEnd() }
    }

    nonisolated private func reportUnexpectedEnd() {
        let reason: String? = shared.withLock { shared in
            guard !shared.reportedUnexpectedEnd else { return nil }
            shared.reportedUnexpectedEnd = true
            return shared.failure ?? WatchDisplay.recordingStopped
        }
        if let reason { continuation.yield(.endedUnexpectedly(reason)) }
    }

    nonisolated private func isCurrent(_ session: HKWorkoutSession) -> Bool {
        shared.withLock { $0.session == ObjectIdentifier(session) }
    }

    nonisolated private func wakeStop() {
        let waiter = shared.withLock { shared in
            defer { shared.stoppedWaiter = nil }
            return shared.stoppedWaiter
        }
        waiter?.resume(returning: ())
    }
}

extension HealthKitWorkoutDriver: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard shared.withLock({ $0.builder == ObjectIdentifier(workoutBuilder) }) else { return }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: bpm)
        let kcal = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let (steps, meters) = Self.movement(of: workoutBuilder)
        continuation.yield(.metrics(heartRate: heart, kcal: kcal, steps: steps, meters: meters))
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
