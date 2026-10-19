import Foundation
import Testing
@testable import TimeCardCore

/// The stub server keeps docs/api.md's account and admin promises, with the server's sentences.
@Suite("Stub server: account and admin")
struct StubAccountTests {
    let f = Fixtures()
    static let now = Date(timeIntervalSince1970: 1_760_700_000)

    var josh: MeResponse {
        MeResponse(user: UserProfile(id: f.userId, email: "josh@example.com", displayName: "Josh"), farms: [f.farm], memberships: [f.member])
    }

    var samMember: Member {
        Member(userId: f.otherUserId, farmId: f.farmId, displayName: "Sam", email: "sam@example.com", role: .worker, updatedAt: Fixtures.t0)
    }

    var sam: MeResponse {
        MeResponse(user: UserProfile(id: f.otherUserId, email: "sam@example.com", displayName: "Sam"), farms: [f.farm], memberships: [samMember])
    }

    /// Josh (admin) and Sam (worker) on the test farm; nobody signed in yet.
    func makeStub() async -> StubAPIClient {
        let stub = StubAPIClient()
        await stub.setClock { Self.now }
        await stub.seed(farmId: f.farmId, f.layout + [.member(samMember)])
        await stub.addAccount(email: "josh@example.com", password: "right horse", me: josh)
        await stub.addAccount(email: "sam@example.com", password: "sam's password", me: sam)
        return stub
    }

    func signIn(_ stub: StubAPIClient, _ email: String = "josh@example.com", _ password: String = "right horse", device: String = "Josh’s iPhone") async throws {
        _ = try await stub.login(LoginRequest(email: email, password: password, deviceName: device))
    }

    func storedMember(_ stub: StubAPIClient, _ userId: UUID) async -> Member? {
        guard case .member(let member)? = await stub.record(kind: .member, id: userId) else { return nil }
        return member
    }

    // MARK: Updating me

    @Test func renamingReachesTheFarmAndMe() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        let cursor = try await stub.pull(farmId: f.farmId, since: 0, limit: 1000).cursor

        let answer = try await stub.updateMe(UpdateMeRequest(displayName: "  Joshua "))
        #expect(answer.user.displayName == "Joshua")
        #expect(answer.memberships.map(\.displayName) == ["Joshua"])
        #expect(try await stub.me() == answer)

        let pulled = try await stub.pull(farmId: f.farmId, since: cursor, limit: 1000)
        let member = try #require(pulled.changes.compactMap { change -> Member? in
            if case .member(let m) = change.record { return m }
            return nil
        }.first)
        #expect(member.displayName == "Joshua")
        #expect(member.updatedAt == Self.now)
    }

    @Test func aBlankNameIsTurnedDown() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        await #expect(throws: APIError.client(status: 400, reason: "Please enter your name.")) {
            _ = try await stub.updateMe(UpdateMeRequest(displayName: "   "))
        }
    }

    @Test func changingThePasswordNeedsTheCurrentOne() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        await #expect(throws: APIError.client(status: 400, reason: "Enter your current password to change it.")) {
            _ = try await stub.updateMe(UpdateMeRequest(newPassword: "brand new horse"))
        }
        await #expect(throws: APIError.client(status: 403, reason: "Your current password isn’t right.")) {
            _ = try await stub.updateMe(UpdateMeRequest(currentPassword: "wrong", newPassword: "brand new horse"))
        }
        await #expect(throws: APIError.client(status: 400, reason: "Use at least 8 characters for your password.")) {
            _ = try await stub.updateMe(UpdateMeRequest(currentPassword: "right horse", newPassword: "short"))
        }
    }

    @Test func aNewPasswordSignsOutOtherDevices() async throws {
        let stub = await makeStub()
        try await signIn(stub, device: "Office Mac")
        try await signIn(stub, device: "Josh’s iPhone")
        #expect(try await stub.sessions().count == 2)

        _ = try await stub.updateMe(UpdateMeRequest(currentPassword: "right horse", newPassword: "brand new horse"))
        let left = try await stub.sessions()
        #expect(left.map(\.deviceName) == ["Josh’s iPhone"])
        #expect(left.first?.isCurrent == true)

        await #expect(throws: APIError.self) { try await signIn(stub) }
        try await signIn(stub, "josh@example.com", "brand new horse")
    }

    // MARK: Sessions

    @Test func listsAndRevokesSessions() async throws {
        let stub = await makeStub()
        try await signIn(stub, device: "Office Mac")
        await stub.setClock { Self.now.addingTimeInterval(3600) }
        try await signIn(stub, device: "Josh’s iPhone")

        let sessions = try await stub.sessions()
        #expect(sessions.map(\.deviceName) == ["Josh’s iPhone", "Office Mac"])
        #expect(sessions.map(\.isCurrent) == [true, false])

        try await stub.revokeSession(id: sessions[1].id)
        #expect(try await stub.sessions().map(\.deviceName) == ["Josh’s iPhone"])
        await #expect(throws: APIError.client(status: 404, reason: "That session isn’t signed in anymore.")) {
            try await stub.revokeSession(id: sessions[1].id)
        }
    }

    @Test func revokingThisPhonesSessionSignsItOut() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        let current = try #require(try await stub.sessions().first)
        try await stub.revokeSession(id: current.id)
        await #expect(throws: APIError.unauthorized(reason: "Please sign in again.")) { _ = try await stub.sessions() }
    }

    @Test func anotherPersonsSessionsStayHidden() async throws {
        let stub = await makeStub()
        try await signIn(stub, "sam@example.com", "sam's password", device: "Sam’s phone")
        let samsSession = try #require(try await stub.sessions().first)
        try await signIn(stub)
        #expect(try await stub.sessions().map(\.deviceName) == ["Josh’s iPhone"])
        await #expect(throws: APIError.client(status: 404, reason: "That session isn’t signed in anymore.")) {
            try await stub.revokeSession(id: samsSession.id)
        }
    }

    @Test func aSeededSignInHasThisPhonesSession() async throws {
        let other = SessionInfo(id: UUID(), deviceName: "Office Mac", createdAt: Fixtures.t0, lastUsedAt: Fixtures.t0, isCurrent: false)
        let stub = StubAPIClient(seed: .init(farmId: f.farmId, records: f.layout, signedIn: josh, sessions: [other]))
        let sessions = try await stub.sessions()
        #expect(sessions.count == 2)
        #expect(sessions.filter(\.isCurrent).count == 1)
        #expect(sessions.contains { $0.id == other.id && !$0.isCurrent })
    }

    // MARK: Deleting the account

    @Test func deletingTheAccountKeepsTheHoursAndDropsTheLogin() async throws {
        let stub = await makeStub()
        try await signIn(stub, "sam@example.com", "sam's password")
        await #expect(throws: APIError.client(status: 403, reason: "That password isn’t right.")) {
            try await stub.deleteAccount(DeleteAccountRequest(password: "wrong"))
        }
        try await stub.deleteAccount(DeleteAccountRequest(password: "sam's password"))

        let member = try #require(await storedMember(stub, f.otherUserId))
        #expect(member.removedAt == Self.now)
        #expect(member.email == "")
        #expect(member.displayName == "Sam")
        await #expect(throws: APIError.unauthorized(reason: "Please sign in again.")) { _ = try await stub.me() }
        await #expect(throws: APIError.self) { try await signIn(stub, "sam@example.com", "sam's password") }
    }

    @Test func theOnlyAdminCantLeaveACrewBehind() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        await #expect(throws: APIError.client(status: 409, reason: "You’re the only admin of Test Tree Farm. Make someone else an admin first.")) {
            try await stub.deleteAccount(DeleteAccountRequest(password: "right horse"))
        }
    }

    // MARK: Invites

    @Test func anInviteCodeLetsSomeoneJoinOnce() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        let made = try await stub.createInvite(farmId: f.farmId, CreateInviteRequest(role: .worker, note: " Jordan "))
        let code = try #require(made.code)
        #expect(code.count == 12)
        #expect(made.note == "Jordan")
        #expect(made.role == .worker)
        #expect(made.createdAt == Self.now)
        #expect(made.expiresAt == Self.now.addingTimeInterval(7 * 86400))

        let listed = try await stub.invites(farmId: f.farmId)
        #expect(listed.map(\.id) == [made.id])
        #expect(listed.first?.code == nil)

        // Codes read off paper come in any case and spacing.
        let joined = try await stub.register(RegisterRequest(inviteCode: code.lowercased().replacingOccurrences(of: "-", with: " "),
                                                             email: "jordan@example.com", password: "jordan's pw", displayName: "Jordan",
                                                             deviceName: "Jordan’s phone"))
        #expect(joined.me.farms.map(\.id) == [f.farmId])
        #expect(joined.me.memberships.first?.role == .worker)

        try await signIn(stub)
        #expect(try await stub.invites(farmId: f.farmId).first?.usedAt == Self.now)
        await #expect(throws: APIError.client(status: 400, reason: "That invite code was already used. Ask your admin for a new one.")) {
            _ = try await stub.register(RegisterRequest(inviteCode: code, email: "pat@example.com", password: "pat's pw",
                                                        displayName: "Pat", deviceName: "d"))
        }
    }

    @Test func invitesListNewestFirstAndCanBeRevoked() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        let first = try await stub.createInvite(farmId: f.farmId, CreateInviteRequest(role: .worker))
        await stub.setClock { Self.now.addingTimeInterval(60) }
        let second = try await stub.createInvite(farmId: f.farmId, CreateInviteRequest(role: .admin, note: "Liz"))
        #expect(try await stub.invites(farmId: f.farmId).map(\.id) == [second.id, first.id])

        try await stub.revokeInvite(farmId: f.farmId, id: first.id)
        #expect(try await stub.invites(farmId: f.farmId).map(\.id) == [second.id])
        await #expect(throws: APIError.client(status: 404, reason: "That invite is already gone.")) {
            try await stub.revokeInvite(farmId: f.farmId, id: first.id)
        }
        await #expect(throws: APIError.client(status: 400, reason: "That invite code isn’t valid. Ask your admin for a new one.")) {
            _ = try await stub.register(RegisterRequest(inviteCode: try #require(first.code), email: "pat@example.com", password: "pat's pw",
                                                        displayName: "Pat", deviceName: "d"))
        }
    }

    @Test func workersCantUseAdminRoutes() async throws {
        let stub = await makeStub()
        try await signIn(stub, "sam@example.com", "sam's password")
        let onlyAdmins = APIError.client(status: 403, reason: "Only an admin can do that.")
        await #expect(throws: onlyAdmins) { _ = try await stub.invites(farmId: f.farmId) }
        await #expect(throws: onlyAdmins) { _ = try await stub.createInvite(farmId: f.farmId, CreateInviteRequest(role: .admin)) }
        await #expect(throws: onlyAdmins) { try await stub.revokeInvite(farmId: f.farmId, id: UUID()) }
        await #expect(throws: onlyAdmins) { _ = try await stub.resetCode(farmId: f.farmId, userId: f.userId) }
        await #expect(throws: onlyAdmins) { try await stub.removeMember(farmId: f.farmId, userId: f.userId) }
    }

    @Test func otherFarmsAreOffLimits() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        await #expect(throws: APIError.client(status: 403, reason: "You’re not on this farm.")) {
            _ = try await stub.invites(farmId: UUID())
        }
    }

    @Test func signedOutCallsAreUnauthorized() async throws {
        let stub = await makeStub()
        await #expect(throws: APIError.unauthorized(reason: "Please sign in again.")) { _ = try await stub.invites(farmId: f.farmId) }
        await #expect(throws: APIError.unauthorized(reason: "Please sign in again.")) { _ = try await stub.updateMe(UpdateMeRequest(displayName: "X")) }
    }

    // MARK: Reset codes

    @Test func aResetCodeLetsTheMemberChooseANewPassword() async throws {
        let stub = await makeStub()
        try await signIn(stub, "sam@example.com", "sam's password", device: "Sam’s old phone")
        try await signIn(stub)
        let reset = try await stub.resetCode(farmId: f.farmId, userId: f.otherUserId)
        #expect(reset.code.count == 12)
        #expect(reset.expiresAt == Self.now.addingTimeInterval(86400))

        let answer = try await stub.resetPassword(ResetPasswordRequest(email: "sam@example.com", resetCode: reset.code, newPassword: "sam's new pw",
                                                                       deviceName: "Sam’s new phone"))
        #expect(answer.me.user.id == f.otherUserId)
        // Every other session ends.
        #expect(try await stub.sessions().map(\.deviceName) == ["Sam’s new phone"])
        try await signIn(stub, "sam@example.com", "sam's new pw")
        await #expect(throws: APIError.self) {
            _ = try await stub.resetPassword(ResetPasswordRequest(email: "sam@example.com", resetCode: reset.code, newPassword: "again pw", deviceName: "d"))
        }
    }

    @Test func resetCodesAreOnlyForPeopleOnTheFarm() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        await #expect(throws: APIError.client(status: 404, reason: "That person isn’t on this farm.")) {
            _ = try await stub.resetCode(farmId: f.farmId, userId: UUID())
        }
    }

    // MARK: Removing people

    @Test func removingSomeoneKeepsTheirHoursAndSyncs() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        let cursor = try await stub.pull(farmId: f.farmId, since: 0, limit: 1000).cursor
        try await stub.removeMember(farmId: f.farmId, userId: f.otherUserId)

        let pulled = try await stub.pull(farmId: f.farmId, since: cursor, limit: 1000)
        #expect(pulled.changes.count == 1)
        guard case .member(let removed)? = pulled.changes.first?.record else { Issue.record("expected a member"); return }
        #expect(removed.userId == f.otherUserId)
        #expect(removed.removedAt == Self.now)

        // Doing it again changes nothing.
        try await stub.removeMember(farmId: f.farmId, userId: f.otherUserId)
        #expect(try await stub.pull(farmId: f.farmId, since: pulled.cursor, limit: 1000).changes.isEmpty)

        // Sam is on no farm now, so he can't sign in.
        await #expect(throws: APIError.client(status: 403, reason: "You’re no longer on any farm. Ask an admin for a new invite.")) {
            try await signIn(stub, "sam@example.com", "sam's password")
        }
    }

    @Test func theLastAdminStays() async throws {
        let stub = await makeStub()
        try await signIn(stub)
        await #expect(throws: APIError.client(status: 409, reason: "A farm needs at least one admin. Make someone else an admin first.")) {
            try await stub.removeMember(farmId: f.farmId, userId: f.userId)
        }
        await #expect(throws: APIError.client(status: 404, reason: "That person isn’t on this farm.")) {
            try await stub.removeMember(farmId: f.farmId, userId: UUID())
        }
    }

    // MARK: Export

    func shift(_ userId: UUID, start: Date, hours: Double, notes: String = "", deleted: Bool = false) -> Shift {
        Shift(userId: userId, farmId: f.farmId, start: start, end: start.addingTimeInterval(hours * 3600),
              breaks: [Break(kind: .lunch, start: start.addingTimeInterval(3600), end: start.addingTimeInterval(3600 + 30 * 60))],
              notes: notes, rateCents: 0, updatedAt: start, deletedAt: deleted ? start : nil)
    }

    /// Oct 14 and 15 2025, 8:00 AM in Indianapolis (UTC-4).
    static let oct14 = Date(timeIntervalSince1970: 1_760_443_200)
    static let oct15 = oct14.addingTimeInterval(86400)

    func seedShifts(_ stub: StubAPIClient) async {
        await stub.seed(farmId: f.farmId, [
            .shift(shift(f.userId, start: Self.oct15, hours: 8.5, notes: "Shaped, \"north\" rows")),
            .shift(shift(f.otherUserId, start: Self.oct14, hours: 4.5)),
            .shift(shift(f.otherUserId, start: Self.oct15, hours: 2, deleted: true)),
            .shift(shift(f.userId, start: Self.oct14.addingTimeInterval(-7 * 86400), hours: 3)),
        ])
    }

    @Test func adminsExportEveryoneInTheRange() async throws {
        let stub = await makeStub()
        await seedShifts(stub)
        try await signIn(stub)
        let data = try await stub.exportCSV(farmId: f.farmId, from: Self.oct14.addingTimeInterval(-3600), to: Self.oct15.addingTimeInterval(86400))
        let csv = String(decoding: data, as: UTF8.self)
        #expect(csv == "Name,Date,In,Out,Breaks,Hours,Notes\r\n"
            + "Sam,2025-10-14,8:00 AM,12:30 PM,30,4.00,\r\n"
            + "Josh,2025-10-15,8:00 AM,4:30 PM,30,8.00,\"Shaped, \"\"north\"\" rows\"\r\n")
    }

    @Test func adminsCanExportOnePerson() async throws {
        let stub = await makeStub()
        await seedShifts(stub)
        try await signIn(stub)
        let csv = String(decoding: try await stub.exportCSV(farmId: f.farmId, userId: f.otherUserId), as: UTF8.self)
        #expect(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == 2)
        #expect(csv.contains("Sam,2025-10-14"))
    }

    @Test func workersExportTheirOwnHoursOnly() async throws {
        let stub = await makeStub()
        await seedShifts(stub)
        try await signIn(stub, "sam@example.com", "sam's password")
        let csv = String(decoding: try await stub.exportCSV(farmId: f.farmId), as: UTF8.self)
        #expect(!csv.contains("Josh"))
        #expect(csv.contains("Sam,2025-10-14"))
        await #expect(throws: APIError.client(status: 403, reason: "You can only export your own hours.")) {
            _ = try await stub.exportCSV(farmId: f.farmId, userId: f.userId)
        }
    }
}
