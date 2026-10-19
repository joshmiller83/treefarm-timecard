import Fluent
import Foundation
import Testing
import TreeFarmKit
@testable import App

@Suite("Record store")
struct RecordStoreTests {
    @Test func savingGivesEachChangeTheNextSeq() async throws {
        try await withTestApp { app, clock in
            let store = RecordStore(db: app.db)
            let farm = Farm(name: "Dull's", timeZoneId: "America/Indiana/Indianapolis", updatedAt: clock.now)
            let s1 = try await store.save(.farm(farm), farm: farm.id)
            let season = Season(farmId: farm.id, name: "2026", startedAt: clock.now, updatedAt: clock.now)
            let s2 = try await store.save(.season(season), farm: farm.id)
            #expect(s1 == 1)
            #expect(s2 == 2)

            var renamed = farm
            renamed.name = "Dull's Tree Farm"
            let s3 = try await store.save(.farm(renamed), farm: farm.id)
            #expect(s3 == 3)

            let back = try await store.farm(farm.id)
            #expect(back?.name == "Dull's Tree Farm")
            #expect(try await RecordModel.query(on: app.db).count() == 2)
            #expect(try await store.maxSeq() == 3)
        }
    }

    @Test func membersAreKeyedByFarmAndUser() async throws {
        try await withTestApp { app, clock in
            let store = RecordStore(db: app.db)
            let user = UUID()
            let farmA = UUID(), farmB = UUID()
            try await store.save(.member(Member(userId: user, farmId: farmA, displayName: "Sam", email: "s@x.com", role: .worker, updatedAt: clock.now)), farm: farmA)
            try await store.save(.member(Member(userId: user, farmId: farmB, displayName: "Sam B", email: "s@x.com", role: .admin, updatedAt: clock.now)), farm: farmB)
            #expect(try await store.member(user, farm: farmA)?.role == .worker)
            #expect(try await store.member(user, farm: farmB)?.role == .admin)
        }
    }

    @Test func storedJSONRoundTripsToTheSameBytes() async throws {
        try await withTestApp { app, _ in
            let store = RecordStore(db: app.db)
            let farmId = UUID()
            let odd = Date(timeIntervalSince1970: 1_760_000_000.1237)
            let shift = Shift(userId: UUID(), farmId: farmId, start: odd, end: odd.addingTimeInterval(3600.0004), notes: "x", rateCents: 1500, updatedAt: odd)
            try await store.save(.shift(shift), farm: farmId)
            let stored = try #require(try await store.find(.shift, shift.id, farm: farmId))
            let again = try ServerJSON.string(stored.record)
            #expect(again == stored.model.json)
            let model = stored.model
            #expect(model.ownerUserId == shift.userId)
            #expect(model.endsAt != nil)
        }
    }

    @Test func usersHaveUniqueEmails() async throws {
        try await withTestApp { app, clock in
            try await UserModel(email: "a@b.com", displayName: "A", passwordHash: "x", createdAt: clock.now).create(on: app.db)
            await #expect(throws: (any Error).self) {
                try await UserModel(email: "a@b.com", displayName: "B", passwordHash: "y", createdAt: clock.now).create(on: app.db)
            }
        }
    }
}
