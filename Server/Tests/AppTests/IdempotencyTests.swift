import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Retries")
struct IdempotencyTests {
    @Test func aRetriedMutationGetsItsFirstAnswer() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            let id = UUID()
            let first = try await farm.push([.shift(shift)], as: farm.admin, ids: [id])[0]
            #expect(first.isApplied)

            // A newer edit lands, then the phone retries the first push (its answer was lost).
            let newer = edited(shift) { $0.notes = "Newer" }
            #expect(try await farm.push(.shift(newer), as: farm.admin).isApplied)
            let retry = try await farm.push([.shift(shift)], as: farm.admin, ids: [id])[0]
            #expect(retry == first)
            #expect(try await RecordStore(db: app.db).shift(shift.id, farm: farm.farmId)?.notes == "Newer")
        }
    }

    @Test func rejectionsAreRemembered() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let bad = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-60), end: clock.now.addingTimeInterval(-120))
            let id = UUID()
            let first = try await farm.push([.shift(bad)], as: farm.admin, ids: [id])[0]
            let again = try await farm.push([.shift(bad)], as: farm.admin, ids: [id])[0]
            #expect(first.status == .rejected)
            #expect(again == first)
        }
    }

    @Test func theSameIdTwiceInABatchIsAppliedOnce() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            let id = UUID()
            let results = try await farm.push([.shift(shift), .shift(edited(shift) { $0.notes = "dup" })], as: farm.admin, ids: [id, id])
            #expect(results[0] == results[1])
            #expect(try await RecordStore(db: app.db).shift(shift.id, farm: farm.farmId)?.notes == "")
        }
    }

    @Test func someoneElsesMutationIdIsNotTheirs() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let id = UUID()
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            _ = try await farm.push([.shift(shift)], as: farm.admin, ids: [id])
            let samShift = farm.shift(for: sam, start: clock.now.addingTimeInterval(-3600))
            let res = try await farm.push([.shift(samShift)], as: sam, ids: [id])[0]
            #expect(res.reason == .forbidden)
            #expect(res.current == nil)
        }
    }
}
