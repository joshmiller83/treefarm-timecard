import Foundation
import Testing
@testable import TimeCardCore

/// The session's conveniences for the account screens and the admin's Team tab.
@MainActor
@Suite("Session: account and admin")
struct SessionAccountTests {
    let f = Fixtures()
    let tokens = InMemoryTokenStore()

    var me: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    var samMember: Member {
        Member(userId: f.otherUserId, farmId: f.farmId, displayName: "Sam", email: "sam@example.com", role: .worker, updatedAt: Fixtures.t0)
    }

    func makeStub() async -> StubAPIClient {
        let stub = StubAPIClient()
        await stub.seed(farmId: f.farmId, f.layout + [.member(samMember)])
        await stub.addAccount(email: "josh@example.com", password: "right horse", me: me)
        await stub.addAccount(email: "sam@example.com", password: "sam's password",
                              me: MeResponse(user: UserProfile(id: f.otherUserId, email: "sam@example.com", displayName: "Sam"),
                                             farms: [f.farm], memberships: [samMember]))
        return stub
    }

    func signedIn(_ stub: StubAPIClient, store: LocalStore? = nil, email: String = "josh@example.com", password: String = "right horse") async throws -> TimeCardSession {
        var config = SyncEngine.Configuration()
        config.debounce = .milliseconds(20)
        let session = TimeCardSession(store: try store ?? LocalStore.inMemory(), api: stub, tokens: tokens, deviceName: "Test iPhone",
                                      engineConfiguration: config)
        try await session.signIn(email: email, password: password)
        _ = await session.syncNow()
        return session
    }

    // MARK: Your account

    @Test func renamingUpdatesMeTheCacheAndTheCrewList() async throws {
        let store = try LocalStore.inMemory()
        let session = try await signedIn(await makeStub(), store: store)
        try await session.updateMe(UpdateMeRequest(displayName: "Joshua"))

        #expect(session.me?.user.displayName == "Joshua")
        #expect(session.membership?.displayName == "Joshua")
        #expect(session.snapshot.members[f.userId]?.displayName == "Joshua")
        // The next launch opens with the new name, even offline.
        #expect(AuthService.initialState(tokens: tokens, cache: store).me?.user.displayName == "Joshua")
    }

    @Test func aPasswordChangeKeepsThisPhoneSignedIn() async throws {
        let stub = await makeStub()
        let session = try await signedIn(stub)
        try await session.updateMe(UpdateMeRequest(currentPassword: "right horse", newPassword: "brand new horse"))
        #expect(session.auth == .signedIn(session.me!))
        #expect(try await session.listSessions().map(\.deviceName) == ["Test iPhone"])
    }

    @Test func aRefusedChangeSaysWhy() async throws {
        let session = try await signedIn(await makeStub())
        await #expect(throws: APIError.client(status: 403, reason: "Your current password isn’t right.")) {
            try await session.updateMe(UpdateMeRequest(currentPassword: "wrong", newPassword: "brand new horse"))
        }
        #expect(session.me?.user.displayName == "Josh")
    }

    @Test func signingOutRightAfterASaveSendsItFirst() async throws {
        let stub = await makeStub()
        let session = try await signedIn(stub)
        let shift = Shift(userId: f.userId, farmId: f.farmId, start: Fixtures.t0, end: Fixtures.t0 + 3600, rateCents: 1800, updatedAt: Fixtures.t0)
        try session.save([.shift(shift)])
        #expect(await session.signOut() == .signedOut)
        #expect(await stub.record(kind: .shift, id: shift.id) == .shift(shift))
        #expect(session.auth == .signedOut)
    }

    @Test func signingOutOfflineKeepsWorkThatCouldntBeSent() async throws {
        let stub = await makeStub()
        let session = try await signedIn(stub)
        for _ in 0..<3 { await stub.failNext(.offline) }
        let shift = Shift(userId: f.userId, farmId: f.farmId, start: Fixtures.t0, end: Fixtures.t0 + 3600, rateCents: 1800, updatedAt: Fixtures.t0)
        try session.save([.shift(shift)])
        #expect(await session.signOut(syncLimit: .seconds(2)) == .unsynced(1))
        #expect(session.auth != .signedOut)
        #expect(session.snapshot.shifts[shift.id] == shift)

        #expect(await session.signOut(discardingUnsynced: true) == .signedOut)
        #expect(session.auth == .signedOut)
        #expect(session.snapshot.shifts.isEmpty)
    }

    @Test func deletingTheAccountSendsLocalHoursFirstThenForgetsThePhone() async throws {
        let stub = await makeStub()
        let store = try LocalStore.inMemory()
        let session = try await signedIn(stub, store: store, email: "sam@example.com", password: "sam's password")
        let shift = Shift(userId: f.otherUserId, farmId: f.farmId, start: Fixtures.t0, end: Fixtures.t0.addingTimeInterval(3600), rateCents: 0,
                          updatedAt: Fixtures.t0)
        try session.save([.shift(shift)])

        try await session.deleteAccount(password: "sam's password")
        #expect(await stub.record(kind: .shift, id: shift.id) == .shift(shift))
        #expect(session.auth == .signedOut)
        #expect(session.farm == nil)
        #expect(try tokens.read() == nil)
        #expect(AuthService.initialState(tokens: tokens, cache: store) == .signedOut)
        #expect(session.snapshot.shifts.isEmpty)
        #expect(await stub.logouts == 0)
    }

    @Test func aWrongPasswordKeepsTheAccount() async throws {
        let session = try await signedIn(await makeStub())
        await #expect(throws: APIError.client(status: 403, reason: "That password isn’t right.")) {
            try await session.deleteAccount(password: "wrong")
        }
        await #expect(throws: AuthError.invalid("Enter your password.")) {
            try await session.deleteAccount(password: "")
        }
        #expect(session.auth == .signedIn(me))
    }

    @Test func listsAndRevokesOtherDevices() async throws {
        let stub = await makeStub()
        _ = try await stub.login(LoginRequest(email: "josh@example.com", password: "right horse", deviceName: "Office Mac"))
        let session = try await signedIn(stub)
        let devices = try await session.listSessions()
        #expect(Set(devices.map(\.deviceName)) == ["Office Mac", "Test iPhone"])
        let mac = try #require(devices.first { $0.deviceName == "Office Mac" })
        try await session.revokeSession(mac.id)
        #expect(try await session.listSessions().map(\.deviceName) == ["Test iPhone"])
    }

    @Test func aRevokedTokenMarksTheSessionExpired() async throws {
        let stub = await makeStub()
        let session = try await signedIn(stub)
        await stub.failNext(.unauthorized(reason: "Please sign in again."))
        await #expect(throws: APIError.unauthorized(reason: "Please sign in again.")) { _ = try await session.listSessions() }
        #expect(session.auth == .expired(me))
    }

    // MARK: Admin

    @Test func invitesForTheOpenFarm() async throws {
        let session = try await signedIn(await makeStub())
        let made = try await session.createInvite(role: .worker, note: "Jordan")
        #expect(made.code != nil)
        let listed = try await session.listInvites()
        #expect(listed.map(\.id) == [made.id])
        #expect(listed.first?.code == nil)
        try await session.revokeInvite(made.id)
        #expect(try await session.listInvites().isEmpty)
    }

    @Test func aResetCodeForACrewMember() async throws {
        let session = try await signedIn(await makeStub())
        let reset = try await session.resetCode(for: f.otherUserId)
        #expect(!reset.code.isEmpty)
    }

    @Test func removingSomeoneShowsUpInTheCrewList() async throws {
        let session = try await signedIn(await makeStub())
        #expect(session.snapshot.members[f.otherUserId]?.removedAt == nil)
        try await session.removeMember(f.otherUserId)
        #expect(session.snapshot.members[f.otherUserId]?.removedAt != nil)
    }

    @Test func exportsTheOpenFarm() async throws {
        let stub = await makeStub()
        await stub.seed(farmId: f.farmId, [.shift(f.shift())])
        let session = try await signedIn(stub)
        let csv = String(decoding: try await session.exportCSV(), as: UTF8.self)
        #expect(csv.hasPrefix("Name,Date,In,Out,Breaks,Hours,Notes\r\n"))
        #expect(csv.contains("Josh,"))
    }

    @Test func workersHearOnlyAnAdminCan() async throws {
        let session = try await signedIn(await makeStub(), email: "sam@example.com", password: "sam's password")
        await #expect(throws: APIError.client(status: 403, reason: "Only an admin can do that.")) {
            _ = try await session.listInvites()
        }
    }

    @Test func farmCallsNeedAFarm() async throws {
        let session = TimeCardSession(store: try LocalStore.inMemory(), api: await makeStub(), tokens: tokens, deviceName: "Test iPhone")
        await #expect(throws: APIError.client(status: 403, reason: "You’re not on this farm.")) {
            _ = try await session.listInvites()
        }
    }
}
