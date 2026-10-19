import Foundation
import Testing
@testable import TimeCardCore

@Suite("Sync engine")
struct SyncEngineTests {
    let f = Fixtures()

    struct Rig {
        let store: LocalStore
        let stub: StubAPIClient
        let engine: SyncEngine
    }

    func makeRig(store: LocalStore? = nil, pullLimit: Int = 500, sleep: (@Sendable (Duration) async throws -> Void)? = nil) async throws -> Rig {
        let store = try store ?? LocalStore.inMemory()
        try store.activate(farmId: f.farmId)
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, f.layout)
        var config = SyncEngine.Configuration()
        config.pullLimit = pullLimit
        config.debounce = .milliseconds(50)
        if let sleep { config.sleep = sleep }
        let engine = SyncEngine(store: store, api: stub, farmId: f.farmId, configuration: config)
        return Rig(store: store, stub: stub, engine: engine)
    }

    // MARK: Push and pull

    @Test func pushesLocalChangesAndPullsTheFarm() async throws {
        let rig = try await makeRig()
        let mark = f.mark(row: 0, position: 0)
        try rig.store.save([.shift(f.shift()), .treeMark(mark)])

        let outcome = await rig.engine.syncNow()

        #expect(outcome == .synced(pushed: 2, pulled: 7))
        #expect(await rig.stub.record(kind: .treeMark, id: mark.id) == .treeMark(mark))
        #expect(try rig.store.pendingCount() == 0)
        #expect(rig.store.snapshot.farm == f.farm)
        #expect(rig.store.snapshot.blocks[f.blockId] == f.block)
        #expect(try rig.store.cursor(farmId: f.farmId) == 7)
        let status = await rig.engine.status
        #expect(status.phase == .idle)
        #expect(status.pendingCount == 0)
        #expect(status.lastSyncedAt != nil)
        #expect(status.lastError == nil)
    }

    @Test func pullsEveryPage() async throws {
        let rig = try await makeRig(pullLimit: 2)
        let outcome = await rig.engine.syncNow()
        #expect(outcome == .synced(pushed: 0, pulled: 5))
        #expect(await rig.stub.pulls.map(\.since) == [0, 2, 4])
        #expect(rig.store.snapshot.member(f.userId) == f.member)
    }

    @Test func sendsBigBacklogsInBatchesOldestFirst() async throws {
        let rig = try await makeRig()
        let marks = (0..<450).map { f.mark(row: $0 / 10, position: $0 % 10) }
        try rig.store.save(marks.map(SyncRecord.treeMark))

        let outcome = await rig.engine.syncNow()

        #expect(outcome == .synced(pushed: 450, pulled: 455))
        let pushes = await rig.stub.pushes
        #expect(pushes.map(\.mutations.count) == [200, 200, 50])
        #expect(pushes.flatMap(\.mutations).map(\.record.entityId) == marks.map(\.id))
        #expect(try rig.store.pendingCount() == 0)
    }

    @Test func retriesAfterATimeoutWithoutDuplicates() async throws {
        let rig = try await makeRig()
        let mutations = try rig.store.save([.shift(f.shift())])
        await rig.stub.loseNextPushAnswer()

        #expect(await rig.engine.syncNow() == .retryLater(.offline))
        let waiting = try rig.store.outbox(farmId: f.farmId, limit: 10)
        #expect(waiting.map(\.mutationId) == mutations.map(\.id))
        #expect(waiting.first?.attempts == 1)
        #expect(await rig.engine.status.phase == .offline)

        #expect(await rig.engine.syncNow() == .synced(pushed: 1, pulled: 6))
        let pushes = await rig.stub.pushes
        #expect(pushes.count == 2)
        #expect(pushes[0].mutations.map(\.id) == pushes[1].mutations.map(\.id))
        let shifts = await rig.stub.records(farmId: f.farmId).filter { $0.kind == .shift }
        #expect(shifts.count == 1)
        #expect(try rig.store.pendingCount() == 0)
    }

    @Test func persistsTheCursorAcrossRestarts() async throws {
        let dir = try temporaryDirectory()
        let first = try await makeRig(store: LocalStore.onDisk(directory: dir))
        _ = await first.engine.syncNow()
        #expect(try first.store.cursor(farmId: f.farmId) == 5)

        let second = try await makeRig(store: LocalStore.onDisk(directory: dir))
        await second.stub.seed(farmId: f.farmId, [.season(Season(farmId: f.farmId, name: "2027", startedAt: Fixtures.t0, updatedAt: Fixtures.t0))])
        _ = await second.engine.syncNow()
        #expect(await second.stub.pulls.map(\.since) == [5])
        #expect(second.store.snapshot.seasons.count == 2)
    }

    // MARK: Rejections

    @Test func aRejectionWithTheServersCopyKeepsItAndSaysWhy() async throws {
        let rig = try await makeRig()
        await rig.stub.addMember(Member(userId: f.otherUserId, farmId: f.farmId, displayName: "Sam", email: "", role: .worker, updatedAt: Fixtures.t0))
        let sams = f.mark(row: 11, position: 3, userId: f.otherUserId, shiftId: UUID(), at: Date(timeIntervalSince1970: 1_760_630_400))
        await rig.stub.seed(farmId: f.farmId, [.treeMark(sams)])
        let mine = f.mark(row: 11, position: 3)
        try rig.store.save([.treeMark(mine)])
        let notices = await rig.engine.notices()

        _ = await rig.engine.syncNow()

        #expect(rig.store.snapshot.marks[mine.id] == nil)
        #expect(rig.store.snapshot.marks[sams.id] == sams)
        var iterator = notices.makeAsyncIterator()
        let notice = await iterator.next()
        #expect(notice?.message == "Row 12, tree 4 was shaped by Sam on Oct 16.")
        #expect(notice?.reason == .treeTaken)
        #expect(notice?.entityId == mine.id)
    }

    @Test func aRejectionWithoutACopyRevertsToTheServer() async throws {
        let rig = try await makeRig()
        _ = await rig.engine.syncNow()
        // Someone renamed the block on the server; this device's rename is refused.
        var renamed = f.block
        renamed.name = "North 1"
        await rig.stub.seed(farmId: f.farmId, [.block(renamed)])
        var mine = f.block
        mine.name = "Mine"
        let note = TreeNote(farmId: f.farmId, tree: TreeRef(blockId: f.blockId, row: 0, position: 0), authorId: f.userId,
                            authorName: "Josh", body: "Leaning", createdAt: Fixtures.t0)
        try rig.store.save([.block(mine), .treeNote(note)])
        await rig.stub.setRejector { mutation in
            .rejected(mutation.id, .forbidden, "Only admins can change blocks.")
        }
        let notices = await rig.engine.notices()

        _ = await rig.engine.syncNow()

        #expect(rig.store.snapshot.blocks[f.blockId]?.name == "North 1")
        #expect(rig.store.snapshot.notes[note.id] == nil)
        #expect(await rig.stub.pulls.map(\.since) == [0, 0])
        var iterator = notices.makeAsyncIterator()
        #expect(await iterator.next()?.message == "Only admins can change blocks.")
    }

    @Test func anEditMadeDuringAPushSurvivesThePull() async throws {
        let rig = try await makeRig()
        try rig.store.save([.shift(f.shift(notes: "first"))])
        let store = rig.store
        let f = self.f
        await rig.stub.setRejector { _ in
            // The person types more notes while the push is on the wire.
            _ = try? store.save([.shift(f.shift(notes: "first and second", updatedAt: Fixtures.t0 + 1))])
            return nil
        }

        _ = await rig.engine.syncNow()

        #expect(rig.store.snapshot.shifts[f.shiftId]?.notes == "first and second")
        #expect(try rig.store.pendingCount() == 1)
    }

    // MARK: Failures

    @Test func a401SignsOutButKeepsTheWork() async throws {
        let rig = try await makeRig()
        let mark = f.mark(row: 0, position: 0)
        try rig.store.save([.treeMark(mark)])
        await rig.stub.failNext(.unauthorized(reason: "Sign in again."))

        #expect(await rig.engine.syncNow() == .signedOut)
        #expect(await rig.engine.status.phase == .signedOut)
        #expect(try rig.store.pendingCount() == 1)
        #expect(rig.store.snapshot.marks[mark.id] == mark)

        // Nothing goes out until someone signs in again.
        #expect(await rig.engine.syncNow() == .signedOut)
        #expect(await rig.stub.pushes.count == 0)
        await rig.engine.resume()
        #expect(await rig.engine.syncNow() == .synced(pushed: 1, pulled: 6))
    }

    @Test func serverErrorsWaitAndTryAgain() async throws {
        let rig = try await makeRig()
        await rig.stub.failNext(.server(status: 503, reason: APIError.serverTrouble))
        #expect(await rig.engine.syncNow() == .retryLater(.server(status: 503, reason: APIError.serverTrouble)))
        let status = await rig.engine.status
        #expect(status.phase == .failed)
        #expect(status.lastError == APIError.serverTrouble)
    }

    // MARK: Scheduling

    @Test func localSavesSyncAfterAPause() async throws {
        let rig = try await makeRig()
        await rig.engine.start()
        for position in 0..<3 {
            try rig.store.save([.treeMark(f.mark(row: 0, position: position))])
        }
        try await waitUntil { await rig.stub.pushes.count >= 1 && (try? rig.store.pendingCount()) == 0 }
        try await Task.sleep(for: .milliseconds(150))
        #expect(await rig.stub.pushes.count == 1)
        #expect(await rig.stub.pushes.first?.mutations.count == 3)
        await rig.engine.stop()
    }

    @Test func backsOffAfterAFailureThenRecovers() async throws {
        let slept = Locked<[Duration]>([])
        let rig = try await makeRig(sleep: { duration in slept.withLock { $0.append(duration) } })
        await rig.stub.failNext(.offline)
        await rig.engine.requestSync(.foreground)

        try await waitUntil { await rig.engine.status.lastSyncedAt != nil }
        let delays = slept.withLock { $0 }
        #expect(delays.count == 2)
        #expect(delays[0] == .zero)
        #expect(delays[1] >= .seconds(1) && delays[1] <= .seconds(2))
    }

    @Test func backoffGrowsWithJitterUpToACap() {
        var low = Backoff(base: .seconds(2), maximum: .seconds(60))
        low.random = { $0.lowerBound }
        var high = low
        high.random = { $0.upperBound }
        #expect(low.delay(attempt: 1) == .seconds(1))
        #expect(high.delay(attempt: 1) == .seconds(2))
        #expect(high.delay(attempt: 3) == .seconds(8))
        #expect(high.delay(attempt: 10) == .seconds(60))
        #expect(low.delay(attempt: 10) == .seconds(30))
    }

    @Test func noticesReachEverySubscriber() async throws {
        let rig = try await makeRig()
        try rig.store.save([.treeNote(TreeNote(farmId: f.farmId, tree: TreeRef(blockId: f.blockId, row: 0, position: 0), authorId: f.userId,
                                                authorName: "Josh", body: "x", createdAt: Fixtures.t0))])
        await rig.stub.setRejector { .rejected($0.id, .invalid, "Too long.") }
        let a = await rig.engine.notices()
        let b = await rig.engine.notices()
        _ = await rig.engine.syncNow()
        var ia = a.makeAsyncIterator()
        var ib = b.makeAsyncIterator()
        #expect(await ia.next()?.message == "Too long.")
        #expect(await ib.next()?.message == "Too long.")
    }

    @Test func networkReturnIsNoticedOnce() {
        var tracker = ReachabilityTracker()
        let readings = [true, false, true, true].map { tracker.update(isReachable: $0) }
        // The first reading isn't a return; only unreachable → reachable is.
        #expect(readings == [false, false, true, false])
    }
}

/// Polls `condition` until it holds or two seconds pass.
func waitUntil(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("timed out waiting")
}

extension FarmSnapshot {
    func member(_ id: UUID) -> Member? { members[id] }
}
