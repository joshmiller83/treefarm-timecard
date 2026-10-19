import Foundation

/// Why a sync was asked for.
public enum SyncTrigger: Sendable, Equatable {
    /// Something was saved on this device. Waits for a quiet moment (the debounce).
    case localChange
    case launch
    case foreground
    case networkReturn
    case background
    case manual
}

/// How one sync pass went.
public enum SyncOutcome: Equatable, Sendable {
    case synced(pushed: Int, pulled: Int)
    /// Offline, rate limited or a server error: the engine tries again after a pause.
    case retryLater(APIError)
    /// The server refused the pass outright (a 4xx, or the local database failed).
    case failed(String)
    /// The token was refused. Local data and the outbox are kept until sign-in.
    case signedOut
}

/// What the Settings screen and the status line show.
public struct SyncStatus: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case syncing
        case offline
        case failed
        case signedOut
    }

    public var phase: Phase
    public var pendingCount: Int
    public var lastSyncedAt: Date?
    public var lastError: String?

    public init(phase: Phase = .idle, pendingCount: Int = 0, lastSyncedAt: Date? = nil, lastError: String? = nil) {
        self.phase = phase
        self.pendingCount = pendingCount
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
    }

    /// "All changes saved", "3 changes waiting to sync", ...
    public var summary: String {
        if pendingCount == 0 { return "All changes saved" }
        return pendingCount == 1 ? "1 change waiting to sync" : "\(pendingCount) changes waiting to sync"
    }
}

/// A change the server turned down, in words the app can show or Siri can speak. Tree marks
/// lost to someone else in one pass come as one notice per row.
public struct SyncNotice: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: RecordKind
    public var entityId: UUID
    /// Every record the notice is about (the trees of a row, say), `entityId` first.
    public var entityIds: [UUID]
    public var reason: RejectReason?
    public var message: String

    public init(_ rejection: Rejection) {
        id = rejection.mutationId
        kind = rejection.kind
        entityId = rejection.entityId
        entityIds = [rejection.entityId]
        reason = rejection.reason
        message = rejection.message
    }

    /// One notice for several rejections of the same kind and reason.
    init(_ group: [Rejection], message: String) {
        self.init(group[0])
        entityIds = group.map(\.entityId)
        self.message = message
    }

    /// The pass's rejections as notices: lost trees grouped by who shaped them and which row
    /// ("Sam shaped 10 trees in Block 2, row 1 first. …"), everything else one by one (a single
    /// lost tree keeps the server's "Row 12, tree 4 in Block 2 was shaped by Sam on Oct 16.").
    public static func grouped(_ rejections: [Rejection], snapshot: FarmSnapshot) -> [SyncNotice] {
        struct RowKey: Hashable { var userId: UUID; var blockId: UUID; var row: Int }
        var notices: [SyncNotice] = []
        var rows: [RowKey: [Rejection]] = [:]
        var order: [RowKey] = []
        for rejection in rejections {
            guard rejection.kind == .treeMark, rejection.reason == .treeTaken, case .treeMark(let winner)? = rejection.current else {
                notices.append(SyncNotice(rejection))
                continue
            }
            let key = RowKey(userId: winner.userId, blockId: winner.blockId, row: winner.row)
            if rows[key] == nil { order.append(key) }
            rows[key, default: []].append(rejection)
        }
        for key in order {
            let group = rows[key] ?? []
            // One tree: the server's own sentence already says who, where and when.
            guard group.count > 1 else {
                notices.append(SyncNotice(group[0]))
                continue
            }
            let message = MarkMessages.shapedFirst(by: snapshot.members[key.userId]?.displayName, count: group.count, row: key.row,
                                                   in: snapshot.blocks[key.blockId])
            notices.append(SyncNotice(group, message: message))
        }
        return notices
    }
}

/// Exponential backoff with jitter: attempt n waits a random time between half and all
/// of `base × 2^(n-1)`, never more than `maximum`.
public struct Backoff: Sendable {
    public var base: Duration
    public var maximum: Duration
    public var random: @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }

    public init(base: Duration = .seconds(2), maximum: Duration = .seconds(300)) {
        self.base = base
        self.maximum = maximum
    }

    public func delay(attempt: Int) -> Duration {
        let baseSeconds = Self.seconds(base)
        let cap = Self.seconds(maximum)
        let full = min(cap, baseSeconds * pow(2, Double(max(attempt, 1) - 1)))
        return .seconds(random((full / 2)...full))
    }

    static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}

/// Moves changes between the local store and the server for one farm.
///
/// A pass pushes the outbox oldest first in batches, applies each answer (rejections
/// become `SyncNotice`s), then pulls from the saved cursor until the server has no more.
/// Passes never overlap. Local saves trigger a pass after a short pause; foreground,
/// network return and background refresh trigger one right away. Failures that may pass
/// (offline, 5xx, 429) retry with backoff; a 401 stops syncing but keeps every local change.
public actor SyncEngine {
    public struct Configuration: Sendable {
        public var debounce: Duration = .milliseconds(1500)
        public var pushBatch = Limits.pushBatch
        public var pullLimit = 500
        public var backoff = Backoff()
        public var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
        public var now: @Sendable () -> Date = { Date() }

        public init() {}
    }

    public nonisolated let farmId: UUID
    private let store: LocalStore
    private let api: any APIClient
    private let config: Configuration

    public private(set) var status = SyncStatus()
    private var signedOut = false
    /// Set by `stopAndWait()`: no pass writes to the store again.
    private var stopped = false
    private var running: Task<SyncOutcome, Never>?
    private var scheduled: Task<Void, Never>?
    private var generation = 0
    private var failures = 0
    private var listener: Task<Void, Never>?
    private var noticeObservers: [UUID: AsyncStream<SyncNotice>.Continuation] = [:]
    private var statusObservers: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    public init(store: LocalStore, api: any APIClient, farmId: UUID, configuration: Configuration = Configuration()) {
        self.store = store
        self.api = api
        self.farmId = farmId
        self.config = configuration
        self.status = SyncStatus(pendingCount: (try? store.pendingCount(farmId: farmId)) ?? 0)
    }

    // MARK: Lifecycle

    /// Starts listening to the store: local saves schedule a pass.
    public func start() {
        guard listener == nil else { return }
        let events = store.events()
        listener = Task { [weak self] in
            for await change in events {
                guard let self else { return }
                await self.storeChanged(change)
            }
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        scheduled?.cancel()
        scheduled = nil
        generation += 1
    }

    /// Stops for good and waits for a pass already running to end (it stops at its next step
    /// and writes nothing more). Call before wiping the store, so a pull that was on its way
    /// can't put the last person's records back after the wipe.
    public func stopAndWait() async {
        stop()
        stopped = true
        running?.cancel()
        while let current = running { _ = await current.value }
    }

    /// Stops syncing as if the server had refused the token (the app opened with an
    /// expired session). Local saves still queue up.
    public func markSignedOut() {
        signedOut = true
        update { $0.phase = .signedOut }
    }

    /// Call after signing in again: syncing picks up where it stopped.
    public func resume() {
        signedOut = false
        failures = 0
        update { $0.phase = .idle; $0.lastError = nil }
    }

    private func storeChanged(_ change: StoreChange) {
        update { $0.pendingCount = change.pendingCount }
        if change.origin == .local { requestSync(.localChange) }
    }

    // MARK: Scheduling

    /// Asks for a pass. Local changes wait for `debounce` of quiet; everything else goes now.
    public func requestSync(_ trigger: SyncTrigger) {
        guard !signedOut else { return }
        if trigger != .localChange { failures = 0 }
        schedule(after: trigger == .localChange ? config.debounce : .zero)
    }

    private func schedule(after delay: Duration) {
        scheduled?.cancel()
        generation += 1
        let mine = generation
        let sleep = config.sleep
        scheduled = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.fire(mine)
        }
    }

    private func fire(_ mine: Int) async {
        guard mine == generation else { return }
        let outcome = await syncNow()
        // A newer request already has its own pass scheduled.
        guard mine == generation else { return }
        scheduled = nil
        switch outcome {
        case .synced, .signedOut:
            failures = 0
        case .retryLater(let error):
            failures += 1
            var delay = config.backoff.delay(attempt: failures)
            if case .rateLimited(_, let retryAfter?) = error { delay = max(delay, .seconds(retryAfter)) }
            schedule(after: delay)
        case .failed:
            failures += 1
            schedule(after: config.backoff.maximum)
        }
    }

    // MARK: Passes

    /// Runs one pass now (after any pass already running) and reports how it went.
    @discardableResult
    public func syncNow() async -> SyncOutcome {
        if let current = running { _ = await current.value }
        if let current = running { return await current.value }
        let pass = Task { await self.runPass() }
        running = pass
        return await pass.value
    }

    /// Waits until no pass is running or already asked for. A pass requested a moment ago
    /// (signing in asks for one) may not have started when `syncNow()` returns, and then runs
    /// after it; tests wait here before scripting the server's next answer, so that late pass
    /// can't take it. A backoff retry is waited for too, so call this only when nothing fails.
    func settle() async {
        var waited: Set<Task<Void, Never>> = []
        while true {
            if let pending = scheduled, !waited.contains(pending) {
                waited.insert(pending)
                await pending.value
            } else if let current = running {
                _ = await current.value
            } else {
                return
            }
        }
    }

    /// Pulls everything again from the start, after any pass already running, because the
    /// person's role changed and the server now shows them different records. With `owner`,
    /// other people's shifts are dropped first (no longer an admin).
    @discardableResult
    public func pullEverythingAgain(keepingOnlyShiftsOf owner: UUID?) async -> SyncOutcome {
        // A pass already running would move the cursor past the restart when it ends.
        while let current = running { _ = await current.value }
        do {
            try store.restartPulls(farmId: farmId, keepingOnlyShiftsOf: owner)
        } catch {
            return .failed("Couldn’t save on this phone: \(error.localizedDescription)")
        }
        return await syncNow()
    }

    /// Before every store write in a pass: stop when the engine was stopped meanwhile.
    private func stillRunning() throws {
        if stopped || Task.isCancelled { throw CancellationError() }
    }

    private func runPass() async -> SyncOutcome {
        defer { running = nil }
        guard !signedOut else { return .signedOut }
        guard !stopped else { return .failed("Syncing stopped.") }
        update { $0.phase = .syncing }
        do {
            let pushed = try await pushAll()
            let pulled = try await pullAll()
            let pending = (try? store.pendingCount(farmId: farmId)) ?? status.pendingCount
            let now = config.now()
            update {
                $0.phase = .idle
                $0.pendingCount = pending
                $0.lastSyncedAt = now
                $0.lastError = nil
            }
            return .synced(pushed: pushed, pulled: pulled)
        } catch is CancellationError {
            return .failed("Syncing stopped.")
        } catch let error as APIError {
            if stopped || Task.isCancelled { return .failed("Syncing stopped.") }
            switch error {
            case .unauthorized:
                signedOut = true
                update { $0.phase = .signedOut; $0.lastError = error.userMessage }
                return .signedOut
            default:
                let phase: SyncStatus.Phase = error == .offline ? .offline : .failed
                update { $0.phase = phase; $0.lastError = error.userMessage }
                return error.isRetryable ? .retryLater(error) : .failed(error.userMessage)
            }
        } catch where AppDatabase.isSuspension(error) {
            // The app is going to sleep and let go of the database: try again when it wakes.
            update { $0.phase = .idle }
            return .retryLater(.transport("The database is paused while Time Card is in the background."))
        } catch {
            let message = "Couldn’t save on this phone: \(error.localizedDescription)"
            update { $0.phase = .failed; $0.lastError = message }
            return .failed(message)
        }
    }

    private func pushAll() async throws -> Int {
        var after: Int64 = 0
        var pushed = 0
        var refused: [Rejection] = []
        // Said once per pass, grouped, even when a later batch fails.
        defer {
            if !refused.isEmpty {
                for notice in SyncNotice.grouped(refused, snapshot: store.snapshot) { broadcast(notice) }
            }
        }
        while true {
            let batch = try store.outbox(farmId: farmId, after: after, limit: config.pushBatch)
            guard let last = batch.last else { break }
            after = last.seq
            let response: PushResponse
            do {
                response = try await api.push(farmId: farmId, PushRequest(mutations: batch.map(\.mutation)))
            } catch let error as APIError {
                try stillRunning()
                try? store.recordAttempt(mutationIds: batch.map(\.mutationId), error: error.userMessage)
                throw error
            }
            try stillRunning()
            let rejections = try store.applyPushResults(response.results, farmId: farmId)
            let answered = Set(response.results.map(\.mutationId))
            let unanswered = batch.map(\.mutationId).filter { !answered.contains($0) }
            try store.recordAttempt(mutationIds: unanswered, error: "The server didn’t answer this change.")
            pushed += response.results.filter { $0.status == .applied }.count
            refused += rejections
        }
        return pushed
    }

    private func pullAll() async throws -> Int {
        var since = try store.cursor(farmId: farmId)
        var pulled = 0
        while true {
            let page = try await api.pull(farmId: farmId, since: since, limit: config.pullLimit)
            try stillRunning()
            try store.applyRemote(page.changes, farmId: farmId, cursor: page.cursor)
            pulled += page.changes.count
            // Stop if the server says it's done, or stops making progress.
            guard page.hasMore, page.cursor > since else { break }
            since = page.cursor
        }
        try stillRunning()
        try store.finishPull(farmId: farmId)
        return pulled
    }

    // MARK: Observation

    /// Rejections, as they happen, for each caller that listens.
    public func notices() -> AsyncStream<SyncNotice> {
        let (stream, continuation) = AsyncStream<SyncNotice>.makeStream(bufferingPolicy: .bufferingNewest(50))
        let id = UUID()
        noticeObservers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeNoticeObserver(id) }
        }
        return stream
    }

    /// The current status, then every change to it.
    public func statusUpdates() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream<SyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        statusObservers[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusObserver(id) }
        }
        return stream
    }

    private func removeNoticeObserver(_ id: UUID) { noticeObservers[id] = nil }
    private func removeStatusObserver(_ id: UUID) { statusObservers[id] = nil }

    private func broadcast(_ notice: SyncNotice) {
        for observer in noticeObservers.values { observer.yield(notice) }
    }

    private func update(_ change: (inout SyncStatus) -> Void) {
        var next = status
        change(&next)
        guard next != status else { return }
        status = next
        for observer in statusObservers.values { observer.yield(next) }
    }
}

/// Spots the moment the network comes back (fed by `NWPathMonitor` in the app).
public struct ReachabilityTracker: Sendable {
    private var last: Bool?

    public init() {}

    /// True when this reading turns "unreachable" into "reachable".
    public mutating func update(isReachable: Bool) -> Bool {
        defer { last = isReachable }
        return isReachable && last == false
    }
}
