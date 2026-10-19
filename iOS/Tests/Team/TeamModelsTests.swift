import Foundation
import Testing
import TimeCardCore
@testable import TimeCard

/// The demo farm on a stub server, signed in as its admin, synced.
@MainActor
private func demoSession() async throws -> (session: TimeCardSession, server: StubAPIClient) {
    let demo = DemoFarm.makeServer(signedIn: true)
    let store = try LocalStore.inMemory()
    try store.setValue(try JSONCoding.encoder().encode(demo.me), forKey: AuthService.meKey)
    let session = TimeCardSession(store: store, api: demo.server, tokens: InMemoryTokenStore(token: "t"), deviceName: "Test iPhone")
    await session.start()
    // The launch's own /me and sync run first, so a scripted failure lands on the call under test.
    await session.launchRefresh?.value
    _ = await session.syncNow()
    return (session, demo.server)
}

@MainActor
@Suite("Team: invites and people on the server")
struct TeamModelsTests {
    @Test func listsMakesAndRevokesInvites() async throws {
        let (session, _) = try await demoSession()
        let model = InvitesModel(session: session)
        await model.load()
        #expect(model.loaded)
        #expect(model.invites.map(\.note) == ["New trimmer"])

        let made = try #require(await model.create(role: .admin, note: "  Jordan "))
        #expect(made.code?.count == 12)
        #expect(made.role == .admin)
        #expect(model.invites.count == 2)
        #expect(model.invites.first?.id == made.id)
        // The list never holds a code: it's shown once, right after making it.
        #expect(model.invites.allSatisfy { $0.code == nil })

        #expect(await model.revoke(made))
        #expect(model.invites.map(\.note) == ["New trimmer"])
        await session.stop()
    }

    @Test func offlineSaysTheInviteNeedsAConnection() async throws {
        let (session, server) = try await demoSession()
        let model = InvitesModel(session: session)
        await server.failNext(.offline)
        #expect(await model.create(role: .worker, note: "") == nil)
        #expect(model.error == "You’re offline. Making an invite needs a connection, so try again when you have signal.")
        await server.failNext(.offline)
        await model.load()
        #expect(model.listError == "You’re offline. The invite list needs a connection, so try again when you have signal.")
        await session.stop()
    }

    @Test func issuesAResetCodeAndRemovesSomeone() async throws {
        let (session, _) = try await demoSession()
        let sam = try #require(session.snapshot.members.values.first { $0.email == DemoFarm.workerEmail })
        let model = MemberActionsModel(session: session)

        let reset = try #require(await model.resetCode(for: sam))
        #expect(reset.code.count == 12)
        #expect(reset.expiresAt > Date())

        #expect(await model.remove(sam))
        #expect(session.snapshot.members[sam.userId]?.removedAt != nil)
        await session.stop()
    }

    @Test func neverAsksTheServerToRemoveYourself() async throws {
        let (session, server) = try await demoSession()
        let alex = try #require(session.membership)
        let model = MemberActionsModel(session: session)
        // Even if the server would say yes, the app says no first.
        await server.failNext(.offline)
        #expect(await model.remove(alex) == false)
        #expect(model.error == "You can’t remove yourself. To leave the farm, delete your account in Settings.")
        await session.stop()
    }

    @Test func savesEditsThroughTheSession() async throws {
        let (session, _) = try await demoSession()
        let sam = try #require(session.snapshot.members.values.first { $0.email == DemoFarm.workerEmail })
        var draft = MemberDraft(sam)
        draft.rateText = "17.75"
        let edit = MemberRules.save(draft, for: sam, members: Array(session.snapshot.members.values), now: Date())
        try TeamSave.apply(edit, in: session)
        #expect(session.snapshot.members[sam.userId]?.rateCents == 1775)
        #expect(try session.store.pendingCount() >= 1)
        await session.stop()
    }
}

@Suite("Team: waiting for the farm")
struct TeamLoadingTests {
    @Test func waitsUntilTheFarmsSeasonIsHere() {
        let f = TeamFixture()
        let synced = SyncStatus(lastSyncedAt: f.now)
        // Synced, with the active season: ready.
        #expect(!TeamLoading.isWaitingForFarm(snapshot: f.snapshot, farm: f.farm, syncStatus: synced))
        // Before the first pull the farm from /me already names its season, but the season isn't here yet.
        var empty = FarmSnapshot(farmId: f.farm.id)
        #expect(TeamLoading.isWaitingForFarm(snapshot: empty, farm: f.farm, syncStatus: SyncStatus()))
        #expect(TeamLoading.isWaitingForFarm(snapshot: empty, farm: f.farm, syncStatus: synced))
        // A farm without a season yet: wait for the first pull, then believe the empty lists.
        var bare = f.farm
        bare.activeSeasonId = nil
        #expect(TeamLoading.isWaitingForFarm(snapshot: empty, farm: bare, syncStatus: SyncStatus()))
        #expect(!TeamLoading.isWaitingForFarm(snapshot: empty, farm: bare, syncStatus: synced))
        // Records already on the phone from an earlier launch count, even before this launch's pull.
        empty.fields[f.north.id] = f.north
        #expect(!TeamLoading.isWaitingForFarm(snapshot: empty, farm: bare, syncStatus: SyncStatus()))
        // No farm open at all.
        #expect(TeamLoading.isWaitingForFarm(snapshot: f.snapshot, farm: nil, syncStatus: synced))
    }

    @Test func saysWhyItIsWaiting() {
        #expect(TeamLoading.detail(SyncStatus()) == "The farm’s fields and seasons show up in a moment.")
        #expect(TeamLoading.detail(SyncStatus(phase: .offline))
            == "You’re offline. The farm’s fields and seasons show up once you have signal.")
        #expect(TeamLoading.detail(SyncStatus(phase: .failed, lastError: "x")) == "The server didn’t answer. Pull down to try again.")
    }

    @Test func reloadsInvitesThatAreOverHalfAMinuteOld() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(InvitesModel.isStale(loadedAt: nil, now: now))
        #expect(!InvitesModel.isStale(loadedAt: now.addingTimeInterval(-29), now: now))
        #expect(InvitesModel.isStale(loadedAt: now.addingTimeInterval(-31), now: now))
    }
}
