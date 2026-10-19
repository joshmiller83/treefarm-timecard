import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("My account and sessions")
struct MeTests {
    @Test func sessionsListMarksTheCurrentOne() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let ipad = try await farm.login(sam, device: "Sam's iPad")
            let res = try await app.client2.send(.GET, APIPath.sessions, token: sam.token)
            #expect(res.status == .ok)
            let sessions = try res.decode([SessionInfo].self)
            #expect(sessions.count == 2)
            #expect(sessions.filter(\.isCurrent).map(\.deviceName) == ["Sam's phone"])
            #expect(Set(sessions.map(\.deviceName)) == ["Sam's phone", "Sam's iPad"])

            _ = try await app.client2.send(.POST, APIPath.logout, token: ipad)
            let after = try await app.client2.send(.GET, APIPath.sessions, token: sam.token).decode([SessionInfo].self)
            #expect(after.count == 1)
        }
    }

    @Test func revokingASessionSignsThatDeviceOut() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let ipad = try await farm.login(sam, device: "Sam's iPad")
            let sessions = try await app.client2.send(.GET, APIPath.sessions, token: sam.token).decode([SessionInfo].self)
            let other = try #require(sessions.first { !$0.isCurrent })
            let res = try await app.client2.send(.DELETE, APIPath.session(other.id), token: sam.token)
            #expect(res.status == .noContent)
            #expect(try await app.client2.send(.GET, APIPath.me, token: ipad).status == .unauthorized)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .ok)
        }
    }

    @Test func nobodyCanRevokeSomeoneElsesSession() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let adminSessions = try await app.client2.send(.GET, APIPath.sessions, token: farm.admin.token).decode([SessionInfo].self)
            let res = try await app.client2.send(.DELETE, APIPath.session(adminSessions[0].id), token: sam.token)
            #expect(res.status == .notFound)
            #expect(try await app.client2.send(.GET, APIPath.me, token: farm.admin.token).status == .ok)
        }
    }

    @Test func changingMyNameUpdatesMyMemberships() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let before = try await RecordStore(db: app.db).maxSeq()
            let res = try await app.client2.send(.PATCH, APIPath.me, token: sam.token, json: UpdateMeRequest(displayName: "  Samuel  "))
            #expect(res.status == .ok)
            let me = try res.decode(MeResponse.self)
            #expect(me.user.displayName == "Samuel")
            #expect(me.memberships.first?.displayName == "Samuel")
            #expect(try await RecordStore(db: app.db).maxSeq() > before)

            let blank = try await app.client2.send(.PATCH, APIPath.me, token: sam.token, json: UpdateMeRequest(displayName: "  "))
            #expect(blank.status == .badRequest)
        }
    }

    @Test func changingMyPasswordNeedsTheCurrentOne() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let ipad = try await farm.login(sam, device: "Sam's iPad")

            let missing = try await app.client2.send(.PATCH, APIPath.me, token: sam.token, json: UpdateMeRequest(newPassword: "brand new password"))
            #expect(missing.status == .badRequest)
            let wrong = try await app.client2.send(.PATCH, APIPath.me, token: sam.token, json: UpdateMeRequest(currentPassword: "nope nope", newPassword: "brand new password"))
            #expect(wrong.status == .forbidden)
            let short = try await app.client2.send(.PATCH, APIPath.me, token: sam.token, json: UpdateMeRequest(currentPassword: sam.password, newPassword: "short"))
            #expect(short.status == .badRequest)

            let ok = try await app.client2.send(.PATCH, APIPath.me, token: sam.token, json: UpdateMeRequest(currentPassword: sam.password, newPassword: "brand new password"))
            #expect(ok.status == .ok)
            // Other devices are signed out; this one stays in.
            #expect(try await app.client2.send(.GET, APIPath.me, token: ipad).status == .unauthorized)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .ok)
            let old = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: sam.password, deviceName: "x"))
            #expect(old.status == .unauthorized)
            let new = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: "brand new password", deviceName: "x"))
            #expect(new.status == .ok)
        }
    }

    @Test func deletingMyAccountKeepsMyShiftsUnderMyName() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let shift = Shift(userId: sam.userId, farmId: farm.farmId, start: clock.now.addingTimeInterval(-7200), end: clock.now, rateCents: 1500, updatedAt: clock.now)
            try await RecordStore(db: app.db).save(.shift(shift), farm: farm.farmId)

            let wrong = try await app.client2.send(.DELETE, APIPath.me, token: sam.token, json: DeleteAccountRequest(password: "nope nope"))
            #expect(wrong.status == .forbidden)

            let res = try await app.client2.send(.DELETE, APIPath.me, token: sam.token, json: DeleteAccountRequest(password: sam.password))
            #expect(res.status == .noContent)
            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .unauthorized)
            let login = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: sam.password, deviceName: "x"))
            #expect(login.status == .unauthorized)

            let store = RecordStore(db: app.db)
            #expect(try await store.shift(shift.id, farm: farm.farmId) != nil)
            let member = try #require(try await store.member(sam.userId, farm: farm.farmId))
            #expect(member.removedAt != nil)
            #expect(member.displayName == "Sam")
            #expect(member.email == "")
            #expect(try await UserModel.find(sam.userId, on: app.db) == nil)
            #expect(try await SessionModel.query(on: app.db).filter(\.$userId == sam.userId).count() == 0)

            // The email can be used again with a new invite.
            let again = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farm.inviteCode(), email: sam.email, password: "a fresh start", displayName: "Sam", deviceName: "p"))
            #expect(again.status == .ok)
        }
    }

    @Test func theLastAdminCannotDeleteTheirAccountWhileOthersRemain() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            _ = try await farm.join("Sam")
            let res = try await app.client2.send(.DELETE, APIPath.me, token: farm.admin.token, json: DeleteAccountRequest(password: farm.admin.password))
            #expect(res.status == .conflict)
            #expect(res.errorReason?.contains("only admin") == true)

            _ = try await farm.join("Boss", role: .admin)
            let ok = try await app.client2.send(.DELETE, APIPath.me, token: farm.admin.token, json: DeleteAccountRequest(password: farm.admin.password))
            #expect(ok.status == .noContent)
        }
    }

    @Test func aFarmsOnlyPersonCanDeleteTheirAccount() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let res = try await app.client2.send(.DELETE, APIPath.me, token: farm.admin.token, json: DeleteAccountRequest(password: farm.admin.password))
            #expect(res.status == .noContent)
        }
    }
}
