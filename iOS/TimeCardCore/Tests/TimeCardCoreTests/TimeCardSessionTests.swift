import Foundation
import Testing
@testable import TimeCardCore

@MainActor
@Suite("Session")
struct TimeCardSessionTests {
    let f = Fixtures()
    let tokens = InMemoryTokenStore()

    var me: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    func makeStub() async -> StubAPIClient {
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, f.layout)
        await stub.addAccount(email: "josh@example.com", password: "pw", me: me)
        return stub
    }

    func makeSession(store: LocalStore? = nil, stub: StubAPIClient) throws -> TimeCardSession {
        var config = SyncEngine.Configuration()
        config.debounce = .milliseconds(20)
        return TimeCardSession(store: try store ?? LocalStore.inMemory(), api: stub, tokens: tokens, deviceName: "Test iPhone", engineConfiguration: config)
    }

    @Test func opensSignedOutTheFirstTime() async throws {
        let session = try makeSession(stub: await makeStub())
        await session.start()
        #expect(session.auth == .signedOut)
        #expect(session.farm == nil)
    }

    @Test func signingInPicksTheFarmAndSyncs() async throws {
        let session = try makeSession(stub: await makeStub())
        await session.start()
        try await session.signIn(email: "josh@example.com", password: "pw")

        #expect(session.auth == .signedIn(me))
        #expect(session.farm == f.farm)
        #expect(session.membership == f.member)
        #expect(session.isAdmin)
        try await waitUntil { await MainActor.run { session.snapshot.blocks[f.blockId] != nil && session.syncStatus.lastSyncedAt != nil } }
    }

    @Test func opensOfflineFromTheCache() async throws {
        let store = try LocalStore.inMemory()
        let stub = await makeStub()
        let first = try makeSession(store: store, stub: stub)
        try await first.signIn(email: "josh@example.com", password: "pw")
        _ = await first.syncNow()
        await first.stop()

        await stub.failNext(.offline)
        await stub.failNext(.offline)
        let second = try makeSession(store: store, stub: stub)
        await second.start()
        #expect(second.auth == .signedIn(me))
        #expect(second.farm == f.farm)
        #expect(second.snapshot.blocks[f.blockId] == f.block)
    }

    @Test func aSignedInLaunchKnowsItsFarmBeforeTheStoreOpens() async throws {
        let store = try LocalStore.inMemory()
        let stub = await makeStub()
        let first = try makeSession(store: store, stub: stub)
        try await first.signIn(email: "josh@example.com", password: "pw")
        _ = await first.syncNow()
        await first.stop()

        let second = try makeSession(store: store, stub: stub)
        // Straight from the cached `/me`: the app never shows "No farm yet" for a crew member.
        #expect(second.farm == f.farm)
        #expect(!second.hasOpened)
        await second.start()
        #expect(second.hasOpened)
        #expect(second.snapshot.blocks[f.blockId] == f.block)
    }

    @Test func aSignedOutLaunchHasNothingToOpen() async throws {
        let session = try makeSession(stub: await makeStub())
        #expect(session.farm == nil)
        await session.start()
        #expect(session.hasOpened)
    }

    @Test func savesShowUpAndWaitToSync() async throws {
        let stub = await makeStub()
        let session = try makeSession(stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        await session.engine?.settle()
        await stub.failNext(.offline)
        await stub.failNext(.offline)
        await stub.failNext(.offline)

        try session.save([.shift(f.shift())])
        #expect(session.snapshot.shifts[f.shiftId] == f.shift())
        try await waitUntil { await MainActor.run { session.syncStatus.pendingCount == 1 && session.syncStatus.phase == .offline } }
        #expect(session.syncStatus.summary == "1 change waiting to sync")
    }

    @Test func anExpiredTokenKeepsTheWorkUntilSignInAgain() async throws {
        let stub = await makeStub()
        let session = try makeSession(stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        await stub.failNext(.unauthorized(reason: "Your session ended."))
        try session.save([.shift(f.shift())])
        #expect(await session.syncNow() == .signedOut)
        try await waitUntil { await MainActor.run { session.auth == .expired(me) } }
        #expect(session.snapshot.shifts[f.shiftId] != nil)

        try await session.signIn(email: "josh@example.com", password: "pw")
        #expect(session.auth == .signedIn(me))
        _ = await session.syncNow()
        #expect(await stub.record(kind: .shift, id: f.shiftId) == .shift(f.shift()))
        #expect(try session.store.pendingCount() == 0)
    }

    @Test func someoneElseSigningInStartsClean() async throws {
        let stub = await makeStub()
        let otherFarm = Farm(name: "Other Farm", timeZoneId: "UTC", updatedAt: Fixtures.t0)
        let sam = MeResponse(user: UserProfile(id: f.otherUserId, email: "sam@example.com", displayName: "Sam"), farms: [otherFarm],
                             memberships: [Member(userId: f.otherUserId, farmId: otherFarm.id, displayName: "Sam", email: "sam@example.com", role: .worker)])
        await stub.addAccount(email: "sam@example.com", password: "pw", me: sam)
        let store = try LocalStore.inMemory()
        let session = try makeSession(store: store, stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        try session.save([.shift(f.shift())])
        await stub.failNext(.unauthorized(reason: ""))
        _ = await session.syncNow()

        try await session.signIn(email: "sam@example.com", password: "pw")
        #expect(session.farm == otherFarm)
        #expect(!session.isAdmin)
        #expect(try store.pendingCount() == 0)
        try store.activate(farmId: f.farmId)
        #expect(store.snapshot.shifts.isEmpty)
    }

    @Test func signingOutForgetsEverything() async throws {
        let stub = await makeStub()
        let store = try LocalStore.inMemory()
        let session = try makeSession(store: store, stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        await session.signOut()

        #expect(session.auth == .signedOut)
        #expect(session.farm == nil)
        #expect(try tokens.read() == nil)
        #expect(await stub.logouts == 1)
        #expect(try store.cursor(farmId: f.farmId) == 0)
        #expect(session.snapshot.blocks.isEmpty)
    }

    @Test func signingOutDuringASlowPullLeavesNothingBehind() async throws {
        let stub = await makeStub()
        let store = try LocalStore.inMemory()
        let session = try makeSession(store: store, stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        // Sam's shift comes with the next pull, which takes a while.
        let sams = Shift(userId: f.otherUserId, farmId: f.farmId, start: Fixtures.t0, end: Fixtures.t0 + 3600, rateCents: 2000, updatedAt: Fixtures.t0)
        await stub.seed(farmId: f.farmId, [.shift(sams)])
        await stub.setPullDelay(.milliseconds(400))
        await session.requestSync(.manual)
        try await Task.sleep(for: .milliseconds(100))

        #expect(await session.signOut() == .signedOut)
        try await Task.sleep(for: .milliseconds(600))
        #expect(store.snapshot.shifts.isEmpty, "the pull on its way wrote into the signed-out phone")
        #expect(store.snapshot.blocks.isEmpty)
        #expect(try store.cursor(farmId: f.farmId) == 0)
    }

    @Test func rejectionsBecomeTheLatestNotice() async throws {
        let stub = await makeStub()
        let session = try makeSession(stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        await stub.setRejector { .rejected($0.id, .invalid, "Clock-out has to be after clock-in.") }
        try session.save([.shift(f.shift())])
        _ = await session.syncNow()
        try await waitUntil { await MainActor.run { session.latestNotice?.message == "Clock-out has to be after clock-in." } }
        session.dismissNotice()
        #expect(session.latestNotice == nil)
    }

    @Test func remembersTheChosenFarm() async throws {
        let stub = await makeStub()
        let second = Farm(name: "Second Farm", timeZoneId: "UTC", updatedAt: Fixtures.t0)
        var both = me
        both.farms.append(second)
        both.memberships.append(Member(userId: f.userId, farmId: second.id, displayName: "Josh", email: "josh@example.com", role: .worker))
        await stub.addAccount(email: "josh@example.com", password: "pw", me: both)
        let store = try LocalStore.inMemory()
        let session = try makeSession(store: store, stub: stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        // The server's order decides until someone picks.
        #expect(session.farm == f.farm)
        await session.selectFarm(second.id)
        #expect(session.farm == second)
        #expect(!session.isAdmin)
        await session.stop()

        let relaunched = try makeSession(store: store, stub: stub)
        await relaunched.start()
        #expect(relaunched.farm == second)
    }

    @Test func aRemovedMembershipIsNotAFarmChoice() {
        let removed = Member(userId: f.userId, farmId: f.farmId, displayName: "Josh", email: "", role: .worker, removedAt: Fixtures.t0)
        let me = MeResponse(user: UserProfile(id: f.userId, email: "", displayName: "Josh"), farms: [f.farm], memberships: [removed])
        #expect(TimeCardSession.chooseFarm(in: me, preferred: f.farmId) == nil)
    }

    // MARK: Role changes

    struct Crew {
        let stub: StubAPIClient
        let me: Member
        let boss: Member
        let bossShift: Shift
    }

    /// Josh (the phone's person) with `role`, and Sam, an admin on $25 with a shift of his own.
    func crew(joshAs role: Role) async -> Crew {
        let me = Member(userId: f.userId, farmId: f.farmId, displayName: "Josh", email: "josh@example.com", role: role,
                        rateCents: 1800, updatedAt: Fixtures.t0)
        let boss = Member(userId: f.otherUserId, farmId: f.farmId, displayName: "Sam", email: "sam@example.com", role: .admin,
                          rateCents: 2500, updatedAt: Fixtures.t0)
        let bossShift = Shift(userId: boss.userId, farmId: f.farmId, start: Fixtures.t0, end: Fixtures.t0 + 3600, rateCents: 2500,
                              updatedAt: Fixtures.t0)
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, [.farm(f.farm), .member(me), .member(boss), .season(f.season), .field(f.field), .block(f.block),
                                           .shift(bossShift)])
        let response = MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [me])
        await stub.addAccount(email: "josh@example.com", password: "pw", me: response)
        return Crew(stub: stub, me: me, boss: boss, bossShift: bossShift)
    }

    @Test func aPromotedWorkerGetsEveryonesHoursAndRealRates() async throws {
        let crew = await crew(joshAs: .worker)
        let session = try makeSession(stub: crew.stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        #expect(session.snapshot.shifts[crew.bossShift.id] == nil)
        #expect(session.snapshot.members[crew.boss.userId]?.rateCents == 0)
        #expect(!session.isAdmin)

        var promoted = crew.me
        promoted.role = .admin
        promoted.updatedAt = Fixtures.t0 + 60
        await crew.stub.seed(farmId: f.farmId, [.member(promoted)])
        _ = await session.syncNow()

        try await waitUntil { await MainActor.run {
            session.snapshot.shifts[crew.bossShift.id] != nil && !session.isCatchingUpOnRole
        } }
        #expect(session.isAdmin)
        #expect(session.snapshot.members[crew.boss.userId] == crew.boss)
        #expect(try session.store.pulledAs(farmId: f.farmId) == .admin)
    }

    @Test func aDemotedAdminsPhoneForgetsOtherPeoplesHours() async throws {
        let crew = await crew(joshAs: .admin)
        let session = try makeSession(stub: crew.stub)
        try await session.signIn(email: "josh@example.com", password: "pw")
        _ = await session.syncNow()
        #expect(session.snapshot.shifts[crew.bossShift.id] == crew.bossShift)
        #expect(session.snapshot.members[crew.boss.userId]?.rateCents == 2500)

        var demoted = crew.me
        demoted.role = .worker
        demoted.updatedAt = Fixtures.t0 + 60
        await crew.stub.seed(farmId: f.farmId, [.member(demoted)])
        _ = await session.syncNow()

        try await waitUntil { await MainActor.run {
            session.snapshot.shifts[crew.bossShift.id] == nil && !session.isCatchingUpOnRole
                && session.snapshot.members[crew.boss.userId]?.rateCents == 0
        } }
        #expect(session.snapshot.members[crew.boss.userId]?.email == "")
        #expect(!session.isAdmin)
    }
}
