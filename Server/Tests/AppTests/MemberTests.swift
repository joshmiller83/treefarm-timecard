import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Members and removal")
struct MemberTests {
    func member(_ farm: FarmFixture, _ person: Person) async throws -> Member {
        try #require(try await RecordStore(db: farm.app.db).member(person.userId, farm: farm.farmId))
    }

    @Test func workersEditTheirOwnNameJobAndRate() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let me = try await member(farm, sam)
            let change = edited(me) { $0.displayName = "Sammy"; $0.jobTitle = "Shaper"; $0.rateCents = 1800; $0.email = "spoof@example.com" }
            #expect(try await farm.push(.member(change), as: sam).isApplied)
            let now = try await member(farm, sam)
            #expect(now.displayName == "Sammy")
            #expect(now.jobTitle == "Shaper")
            #expect(now.rateCents == 1800)
            #expect(now.email == sam.email)

            #expect(try await farm.push(.member(edited(now) { $0.role = .admin }), as: sam).reason == .forbidden)
            #expect(try await farm.push(.member(edited(now) { $0.removedAt = app.now }), as: sam).reason == .forbidden)
            let boss = try await member(farm, farm.admin)
            #expect(try await farm.push(.member(edited(boss) { $0.rateCents = 1 }), as: sam).reason == .forbidden)
            #expect(try await farm.push(.member(edited(now, by: 2) { $0.displayName = " " }), as: sam).reason == .invalid)
            #expect(try await farm.push(.member(edited(now, by: 2) { $0.rateCents = -1 }), as: sam).reason == .invalid)
        }
    }

    @Test func adminsSetRolesAndRates() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let m = try await member(farm, sam)
            #expect(try await farm.push(.member(edited(m) { $0.role = .admin; $0.rateCents = 2200 }), as: farm.admin).isApplied)
            #expect(try await member(farm, sam).role == .admin)

            let stranger = Member(userId: UUID(), farmId: farm.farmId, displayName: "Who", email: "", role: .worker, updatedAt: app.now)
            #expect(try await farm.push(.member(stranger), as: farm.admin).reason == .notFound)
        }
    }

    @Test func theLastAdminStays() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let josh = try await member(farm, farm.admin)
            let res = try await farm.push(.member(edited(josh) { $0.role = .worker }), as: farm.admin)
            #expect(res.reason == .invalid)
            #expect(res.message == "A farm needs at least one admin. Make someone else an admin first.")

            let removal = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: farm.admin.userId), token: farm.admin.token)
            #expect(removal.status == .conflict)

            let s = try await member(farm, sam)
            #expect(try await farm.push(.member(edited(s) { $0.role = .admin }), as: farm.admin).isApplied)
            #expect(try await farm.push(.member(edited(josh) { $0.role = .worker }), as: farm.admin).isApplied)
        }
    }

    @Test func removingSomeoneKeepsTheirHoursAndSignsThemOut() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let shift = farm.shift(for: sam, start: clock.now.addingTimeInterval(-7200), end: clock.now.addingTimeInterval(-3600))
            try await farm.push(.shift(shift), as: sam)
            let cursor = try await farm.pull(as: farm.admin).cursor

            let res = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: sam.userId), token: farm.admin.token)
            #expect(res.status == .noContent)
            #expect(try await member(farm, sam).removedAt != nil)
            #expect(try await RecordStore(db: app.db).shift(shift.id, farm: farm.farmId) != nil)
            // The removal syncs like any other change.
            let changes = try await farm.pull(as: farm.admin, since: cursor).changes
            #expect(changes.contains { c in if case .member(let m) = c.record { return m.userId == sam.userId && m.removedAt != nil }; return false })

            #expect(try await app.client2.send(.GET, APIPath.me, token: sam.token).status == .unauthorized)
            let login = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: sam.password, deviceName: "x"))
            #expect(login.status == .forbidden)

            let again = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: sam.userId), token: farm.admin.token)
            #expect(again.status == .noContent)
            let nobody = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: UUID()), token: farm.admin.token)
            #expect(nobody.status == .notFound)
        }
    }

    @Test func someoneRemovedFromOneFarmKeepsTheOther() async throws {
        try await withTestApp { app, _ in
            let farmA = try await FarmFixture.make(app)
            let farmB = try await FarmFixture.make(app, farmName: "B", adminEmail: "b@example.com")
            let sam = try await farmA.join("Sam")
            let joinB = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farmB.inviteCode(), email: sam.email, password: sam.password, displayName: "Sam", deviceName: "p"))
            #expect(joinB.status == .ok)

            #expect(try await app.client2.send(.DELETE, APIPath.member(farm: farmA.farmId, user: sam.userId), token: farmA.admin.token).status == .noContent)
            let onA = try await app.client2.send(.GET, APIPath.pull(farm: farmA.farmId), token: sam.token)
            #expect(onA.status == .forbidden)
            let onB = try await app.client2.send(.GET, APIPath.pull(farm: farmB.farmId), token: sam.token)
            #expect(onB.status == .ok)
            let me = try await app.client2.send(.GET, APIPath.me, token: sam.token).decode(MeResponse.self)
            #expect(me.farms.map(\.id) == [farmB.farmId])
        }
    }

    @Test func aNewInviteBringsSomeoneBack() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            _ = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: sam.userId), token: farm.admin.token)
            let back = try await app.client2.send(.POST, APIPath.register, json: RegisterRequest(inviteCode: try await farm.inviteCode(role: .admin), email: sam.email, password: sam.password, displayName: "Sam", deviceName: "p"))
            #expect(back.status == .ok)
            let m = try await member(farm, sam)
            #expect(m.removedAt == nil)
            #expect(m.role == .admin)
        }
    }

    @Test func workersCannotRemovePeople() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let res = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: alex.userId), token: sam.token)
            #expect(res.status == .forbidden)
        }
    }

    @Test func adminsCanUndoARemoval() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            _ = try await app.client2.send(.DELETE, APIPath.member(farm: farm.farmId, user: sam.userId), token: farm.admin.token)
            let removed = try await member(farm, sam)
            #expect(try await farm.push(.member(edited(removed) { $0.removedAt = nil }), as: farm.admin).isApplied)
            let login = try await app.client2.send(.POST, APIPath.login, json: LoginRequest(email: sam.email, password: sam.password, deviceName: "x"))
            #expect(login.status == .ok)
        }
    }
}
