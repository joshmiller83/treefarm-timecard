import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Admin: invites and reset codes")
struct AdminTests {
    @Test func adminsMakeListAndDeleteInvites() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let res = try await app.client2.send(.POST, APIPath.invites(farm: farm.farmId), token: farm.admin.token, json: CreateInviteRequest(role: .worker, note: "Sam"))
            #expect(res.status == .ok)
            let created = try res.decode(InviteInfo.self)
            let code = try #require(created.code)
            #expect(created.role == .worker)
            #expect(created.note == "Sam")
            #expect(created.expiresAt == clock.now.addingTimeInterval(7 * 24 * 3600))

            let list = try await app.client2.send(.GET, APIPath.invites(farm: farm.farmId), token: farm.admin.token).decode([InviteInfo].self)
            #expect(list.map(\.id) == [created.id])
            #expect(list[0].code == nil)

            let del = try await app.client2.send(.DELETE, APIPath.invite(farm: farm.farmId, id: created.id), token: farm.admin.token)
            #expect(del.status == .noContent)
            let reg = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: code, email: "sam@example.com", password: "long enough", displayName: "Sam", deviceName: "p"))
            #expect(reg.status == .badRequest)
            let missing = try await app.client2.send(.DELETE, APIPath.invite(farm: farm.farmId, id: created.id), token: farm.admin.token)
            #expect(missing.status == .notFound)
        }
    }

    @Test func usedInvitesShowWhenTheyWereUsed() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            _ = try await farm.join("Sam")
            let list = try await app.client2.send(.GET, APIPath.invites(farm: farm.farmId), token: farm.admin.token).decode([InviteInfo].self)
            #expect(list.count == 1)
            #expect(list[0].usedAt != nil)
        }
    }

    @Test func workersCannotManageInvites() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let res = try await app.client2.send(.POST, APIPath.invites(farm: farm.farmId), token: sam.token, json: CreateInviteRequest(role: .admin))
            #expect(res.status == .forbidden)
            #expect(try await app.client2.send(.GET, APIPath.invites(farm: farm.farmId), token: sam.token).status == .forbidden)
        }
    }

    @Test func invitesBelongToTheirFarm() async throws {
        try await withTestApp { app, _ in
            let farmA = try await FarmFixture.make(app)
            let farmB = try await FarmFixture.make(app, farmName: "B", adminEmail: "b@example.com")
            let invite = try await app.client2.send(.POST, APIPath.invites(farm: farmA.farmId), token: farmA.admin.token, json: CreateInviteRequest(role: .worker)).decode(InviteInfo.self)
            // B's admin can't see or delete A's invite, even through B's own farm path.
            let res = try await app.client2.send(.DELETE, APIPath.invite(farm: farmB.farmId, id: invite.id), token: farmB.admin.token)
            #expect(res.status == .notFound)
            let other = try await app.client2.send(.GET, APIPath.invites(farm: farmA.farmId), token: farmB.admin.token)
            #expect(other.status == .forbidden)
        }
    }

    @Test func adminsIssueResetCodesForTheirPeople() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let res = try await app.client2.send(.POST, APIPath.memberReset(farm: farm.farmId, user: sam.userId), token: farm.admin.token)
            #expect(res.status == .ok)
            let reset = try res.decode(ResetCodeResponse.self)
            #expect(reset.expiresAt == clock.now.addingTimeInterval(24 * 3600))

            let used = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: sam.email, resetCode: reset.code, newPassword: "a new password", deviceName: "phone"))
            #expect(used.status == .ok)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .unauthorized)
        }
    }

    @Test func aNewResetCodeReplacesTheOldOne() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let first = try await app.client2.send(.POST, APIPath.memberReset(farm: farm.farmId, user: sam.userId), token: farm.admin.token).decode(ResetCodeResponse.self)
            _ = try await app.client2.send(.POST, APIPath.memberReset(farm: farm.farmId, user: sam.userId), token: farm.admin.token)
            let res = try await app.client2.send(.POST, APIPath.resetPassword, json: ResetPasswordRequest(email: sam.email, resetCode: first.code, newPassword: "a new password", deviceName: "phone"))
            #expect(res.status == .badRequest)
        }
    }

    @Test func resetCodesOnlyForPeopleOnTheFarm() async throws {
        try await withTestApp { app, _ in
            let farmA = try await FarmFixture.make(app)
            let farmB = try await FarmFixture.make(app, farmName: "B", adminEmail: "b@example.com")
            let res = try await app.client2.send(.POST, APIPath.memberReset(farm: farmA.farmId, user: farmB.admin.userId), token: farmA.admin.token)
            #expect(res.status == .notFound)
            let sam = try await farmA.join("Sam")
            let worker = try await app.client2.send(.POST, APIPath.memberReset(farm: farmA.farmId, user: farmA.admin.userId), token: sam.token)
            #expect(worker.status == .forbidden)
        }
    }

    @Test func farmRoutesNeedMembership() async throws {
        try await withTestApp { app, _ in
            let farmA = try await FarmFixture.make(app)
            let farmB = try await FarmFixture.make(app, farmName: "B", adminEmail: "b@example.com")
            let res = try await app.client2.send(.GET, APIPath.invites(farm: farmA.farmId), token: farmB.admin.token)
            #expect(res.status == .forbidden)
            #expect(res.errorReason == "You’re not on this farm.")
            let anon = try await app.client2.send(.GET, APIPath.invites(farm: farmA.farmId))
            #expect(anon.status == .unauthorized)
            let bogus = try await app.client2.send(.GET, "/v1/farms/not-a-uuid/invites", token: farmA.admin.token)
            #expect(bogus.status == .notFound)
        }
    }
}
