import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Pull")
struct PullTests {
    @Test func aNewDeviceGetsTheWholeFarmInOrder() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let page = try await farm.pull(as: farm.admin)
            #expect(page.changes.map(\.record.kind) == [.farm, .season, .member, .field])
            #expect(page.changes.map(\.seq) == page.changes.map(\.seq).sorted())
            #expect(page.cursor == page.changes.last?.seq)
            #expect(!page.hasMore)

            let nothing = try await farm.pull(as: farm.admin, since: page.cursor)
            #expect(nothing.changes.isEmpty)
            #expect(nothing.cursor == page.cursor)
            #expect(!nothing.hasMore)
        }
    }

    @Test func pagesFollowTheLimit() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            for i in 1...5 {
                let start = clock.now.addingTimeInterval(Double(-i) * 7200)
                try await farm.push(.shift(farm.shift(for: farm.admin, start: start, end: start.addingTimeInterval(600))), as: farm.admin)
            }
            let first = try await farm.pull(as: farm.admin, limit: 3)
            #expect(first.changes.count == 3)
            #expect(first.hasMore)
            let all = try await farm.pullAll(as: farm.admin)
            #expect(all.count == 9)
            #expect(Set(all.map(\.seq)).count == 9)
        }
    }

    @Test func workersSeeOnlyTheirOwnShifts() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let mine = farm.shift(for: sam, start: clock.now.addingTimeInterval(-3600))
            let joshs = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            try await farm.push(.shift(mine), as: sam)
            try await farm.push(.shift(joshs), as: farm.admin)

            let samSees = try await farm.pullAll(as: sam).compactMap { c -> Shift? in
                if case .shift(let s) = c.record { return s }; return nil
            }
            #expect(samSees.map(\.id) == [mine.id])
            let joshSees = try await farm.pullAll(as: farm.admin).compactMap { c -> Shift? in
                if case .shift(let s) = c.record { return s }; return nil
            }
            #expect(Set(joshSees.map(\.id)) == [mine.id, joshs.id])
        }
    }

    @Test func workersSeeNamesButNotOtherPeoplesEmailOrRate() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let store = RecordStore(db: app.db)
            for id in [farm.admin.userId, sam.userId] {
                var m = try #require(try await store.member(id, farm: farm.farmId))
                m.rateCents = 2000
                m.updatedAt = clock.now
                try await store.save(.member(m), farm: farm.farmId)
            }

            let members = { (changes: [Change]) -> [UUID: Member] in
                var out: [UUID: Member] = [:]
                for c in changes { if case .member(let m) = c.record { out[m.userId] = m } }
                return out
            }
            let samSees = members(try await farm.pullAll(as: sam))
            #expect(samSees[farm.admin.userId]?.displayName == "Josh")
            #expect(samSees[farm.admin.userId]?.email == "")
            #expect(samSees[farm.admin.userId]?.rateCents == 0)
            #expect(samSees[sam.userId]?.email == sam.email)
            #expect(samSees[sam.userId]?.rateCents == 2000)

            let joshSees = members(try await farm.pullAll(as: farm.admin))
            #expect(joshSees[sam.userId]?.email == sam.email)
            #expect(joshSees[sam.userId]?.rateCents == 2000)
        }
    }

    @Test func otherFarmsStayOut() async throws {
        try await withTestApp { app, _ in
            let farmA = try await FarmFixture.make(app)
            let farmB = try await FarmFixture.make(app, farmName: "B", adminEmail: "b@example.com")
            let seen = try await farmA.pullAll(as: farmA.admin)
            #expect(!seen.contains { c in if case .farm(let f) = c.record { return f.id == farmB.farmId }; return false })
            #expect(seen.count == 4)
        }
    }

    @Test func queryValuesAreChecked() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let bad = try await app.client2.send(.GET, APIPath.pull(farm: farm.farmId) + "?since=abc", token: farm.admin.token)
            #expect(bad.status == .badRequest)
            let negative = try await app.client2.send(.GET, APIPath.pull(farm: farm.farmId) + "?since=-1", token: farm.admin.token)
            #expect(negative.status == .badRequest)
            let big = try await app.client2.send(.GET, APIPath.pull(farm: farm.farmId) + "?limit=5000", token: farm.admin.token)
            #expect(big.status == .ok)
            let none = try await app.client2.send(.GET, APIPath.pull(farm: farm.farmId), token: farm.admin.token)
            #expect(try none.decode(PullResponse.self).changes.count == 4)
        }
    }
}
