import Foundation
import Testing
@testable import TimeCardCore

@Suite("Demo farm")
struct DemoFarmTests {
    @Test func theDemoServerHasASignedInAdminAndAFarm() async throws {
        let demo = DemoFarm.makeServer()
        let me = try await demo.server.me()
        #expect(me == demo.me)
        #expect(me.memberships.first?.role == .admin)

        let farmId = try #require(me.farms.first?.id)
        let pulled = try await demo.server.pull(farmId: farmId, since: 0, limit: 1000)
        let kinds = Set(pulled.changes.map(\.record.kind))
        #expect(kinds.isSuperset(of: [.farm, .member, .season, .field, .block, .treeMark]))
        #expect(!pulled.hasMore)
    }

    @Test func theDemoPersonCanSignInByPassword() async throws {
        let demo = DemoFarm.makeServer(signedIn: false)
        await #expect(throws: APIError.self) { _ = try await demo.server.me() }
        let auth = try await demo.server.login(LoginRequest(email: DemoFarm.email, password: DemoFarm.password, deviceName: "d"))
        #expect(auth.me == demo.me)
    }
}

@Suite("Demo farm: crew and account")
struct DemoFarmCrewTests {
    @Test func theDemoAdminHasAnotherDeviceAndAnOpenInvite() async throws {
        let demo = DemoFarm.makeServer()
        let sessions = try await demo.server.sessions()
        #expect(sessions.count == 2)
        #expect(sessions.filter(\.isCurrent).count == 1)

        let farmId = try #require(demo.me.farms.first?.id)
        let invites = try await demo.server.invites(farmId: farmId)
        #expect(invites.count == 1)
        #expect(invites.first?.code == nil)
    }

    @Test func theDemoWorkerCanSignInAndGetAResetCode() async throws {
        let demo = DemoFarm.makeServer()
        let farmId = try #require(demo.me.farms.first?.id)
        let pulled = try await demo.server.pull(farmId: farmId, since: 0, limit: 1000)
        let sam = try #require(pulled.changes.compactMap { change -> Member? in
            if case .member(let m) = change.record, m.role == .worker { return m }
            return nil
        }.first)
        _ = try await demo.server.resetCode(farmId: farmId, userId: sam.userId)

        let auth = try await demo.server.login(LoginRequest(email: DemoFarm.workerEmail, password: DemoFarm.password, deviceName: "d"))
        #expect(auth.me.user.id == sam.userId)
        #expect(auth.me.memberships.first?.role == .worker)
    }

    @Test func theDemoInviteCodeJoinsTheFarm() async throws {
        let demo = DemoFarm.makeServer(signedIn: false)
        let joined = try await demo.server.register(RegisterRequest(inviteCode: DemoFarm.inviteCode, email: "new@example.com",
                                                                    password: "new person pw", displayName: "New Person", deviceName: "d"))
        #expect(joined.me.farms.map(\.id) == demo.me.farms.map(\.id))
    }
}
