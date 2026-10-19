import Foundation
import Testing
@testable import TimeCardCore

@Suite("Demo farm")
struct DemoFarmTests {
    @Test func theDemoServerHasASignedInAdminAndAFarm() async throws {
        let demo = await DemoFarm.makeServer()
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
        let demo = await DemoFarm.makeServer()
        let auth = try await demo.server.login(LoginRequest(email: DemoFarm.email, password: DemoFarm.password, deviceName: "d"))
        #expect(auth.me == demo.me)
    }
}
