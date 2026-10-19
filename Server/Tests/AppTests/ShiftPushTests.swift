import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Push: shifts")
struct ShiftPushTests {
    @Test func workersPushTheirOwnShifts() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let shift = farm.shift(for: sam, start: clock.now.addingTimeInterval(-3600))
            let result = try await farm.push(.shift(shift), as: sam)
            #expect(result.isApplied)
            #expect(result.seq != nil)
            #expect(try await RecordStore(db: app.db).shift(shift.id, farm: farm.farmId) == shift)
        }
    }

    @Test func workersCannotPushOtherPeoplesShifts() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let result = try await farm.push(.shift(farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))), as: sam)
            #expect(result.status == .rejected)
            #expect(result.reason == .forbidden)

            // Nor take one over by pushing its id under their own name.
            let josh = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-7200), end: clock.now.addingTimeInterval(-3600))
            #expect(try await farm.push(.shift(josh), as: farm.admin).isApplied)
            var stolen = josh
            stolen.userId = sam.userId
            stolen.updatedAt = clock.now.addingTimeInterval(1)
            let steal = try await farm.push(.shift(stolen), as: sam)
            #expect(steal.reason == .forbidden)
        }
    }

    @Test func adminsPushAnyonesShifts() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let shift = farm.shift(for: sam, start: clock.now.addingTimeInterval(-3600))
            #expect(try await farm.push(.shift(shift), as: farm.admin).isApplied)

            var moved = shift
            moved.userId = farm.admin.userId
            moved.updatedAt = clock.now.addingTimeInterval(5)
            let res = try await farm.push(.shift(moved), as: farm.admin)
            #expect(res.reason == .invalid)

            let stranger = Shift(userId: UUID(), farmId: farm.farmId, start: clock.now.addingTimeInterval(-60), rateCents: 0, updatedAt: clock.now)
            #expect(try await farm.push(.shift(stranger), as: farm.admin).reason == .notFound)
        }
    }

    @Test func recordsMustBelongToTheFarmInThePath() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            var shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            shift.farmId = UUID()
            #expect(try await farm.push(.shift(shift), as: farm.admin).reason == .forbidden)
        }
    }

    @Test func aSecondOpenShiftIsRefusedWithTheFirst() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let first = farm.shift(for: sam, start: clock.now.addingTimeInterval(-3600))
            #expect(try await farm.push(.shift(first), as: sam).isApplied)
            // Another phone clocks in offline.
            let second = farm.shift(for: sam, start: clock.now.addingTimeInterval(-60))
            let res = try await farm.push(.shift(second), as: sam)
            #expect(res.status == .rejected)
            #expect(res.reason == .openShiftExists)
            #expect(res.current == .shift(first))
            #expect(res.message?.contains("already clocked in") == true)

            // Once the first is closed the second can't overlap it, but a later one is fine.
            var closed = first
            closed.end = clock.now.addingTimeInterval(-120)
            closed.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.shift(closed), as: sam).isApplied)
            #expect(try await farm.push(.shift(second), as: sam).isApplied)
        }
    }

    @Test func anOlderCopyLosesToTheServers() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let original = farm.shift(for: sam, start: clock.now.addingTimeInterval(-7200), end: clock.now.addingTimeInterval(-3600), updatedAt: clock.now)
            #expect(try await farm.push(.shift(original), as: sam).isApplied)

            var newer = original
            newer.notes = "Fixed on the iPad"
            newer.updatedAt = clock.now.addingTimeInterval(60)
            #expect(try await farm.push(.shift(newer), as: sam).isApplied)

            // The phone was offline and still has an edit from before.
            var stale = original
            stale.notes = "Edited offline"
            stale.updatedAt = clock.now.addingTimeInterval(30)
            let res = try await farm.push(.shift(stale), as: sam)
            #expect(res.status == .rejected)
            #expect(res.reason == .invalid)
            #expect(res.message == "A newer copy of this shift is on the server.")
            #expect(res.current == .shift(newer))

            // A tie with different content also keeps the server's copy.
            var tie = newer
            tie.notes = "Same time, other words"
            #expect(try await farm.push(.shift(tie), as: sam).status == .rejected)
        }
    }

    @Test func pushingTheSameCopyAgainKeepsItsSeq() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            let first = try await farm.push(.shift(shift), as: farm.admin)
            let again = try await farm.push(.shift(shift), as: farm.admin)
            #expect(again.isApplied)
            #expect(again.seq == first.seq)
        }
    }

    @Test func shiftRulesAreEnforced() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let backwards = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-60), end: clock.now.addingTimeInterval(-3600))
            let res = try await farm.push(.shift(backwards), as: farm.admin)
            #expect(res.reason == .invalid)
            #expect(res.message == "Clock out has to be after clock in.")

            let future = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(10 * 60))
            #expect(try await farm.push(.shift(future), as: farm.admin).reason == .invalid)
            // A phone a few minutes fast is fine.
            let skewed = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(4 * 60))
            #expect(try await farm.push(.shift(skewed), as: farm.admin).isApplied)

            var badBreak = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-30 * 3600), end: clock.now.addingTimeInterval(-29 * 3600))
            badBreak.breaks = [Break(kind: .lunch, start: clock.now.addingTimeInterval(-40 * 3600), end: clock.now.addingTimeInterval(-39 * 3600))]
            let br = try await farm.push(.shift(badBreak), as: farm.admin)
            #expect(br.message == "Break 1 has to fall inside the shift.")

            var negative = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-50 * 3600), end: clock.now.addingTimeInterval(-49 * 3600))
            negative.rateCents = -5
            #expect(try await farm.push(.shift(negative), as: farm.admin).reason == .invalid)
        }
    }

    @Test func longNotesAreTrimmedToTheLimit() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600), notes: String(repeating: "a", count: Limits.notes + 50))
            #expect(try await farm.push(.shift(shift), as: farm.admin).isApplied)
            #expect(try await RecordStore(db: app.db).shift(shift.id, farm: farm.farmId)?.notes.count == Limits.notes)
        }
    }

    @Test func deletingAShiftIsAlwaysAllowedForItsOwner() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            var shift = farm.shift(for: sam, start: clock.now.addingTimeInterval(-3600))
            #expect(try await farm.push(.shift(shift), as: sam).isApplied)
            shift.deletedAt = clock.now
            shift.updatedAt = clock.now.addingTimeInterval(1)
            #expect(try await farm.push(.shift(shift), as: sam).isApplied)
            // With it gone, clocking in again works.
            #expect(try await farm.push(.shift(farm.shift(for: sam, start: clock.now.addingTimeInterval(-30))), as: sam).isApplied)
        }
    }

    @Test func batchesAreCapped() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let mutations = (0...Limits.pushBatch).map { i in
                Mutation(record: .shift(farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(Double(-i) * 7200), end: clock.now.addingTimeInterval(Double(-i) * 7200 + 60))))
            }
            let res = try await app.client2.send(.POST, APIPath.push(farm: farm.farmId), token: farm.admin.token, json: PushRequest(mutations: mutations))
            #expect(res.status == .payloadTooLarge)
            let ok = try await app.client2.send(.POST, APIPath.push(farm: farm.farmId), token: farm.admin.token, json: PushRequest(mutations: Array(mutations.prefix(Limits.pushBatch))))
            #expect(ok.status == .ok)
            #expect(try ok.decode(PushResponse.self).results.allSatisfy(\.isApplied))
        }
    }

    @Test func resultsComeBackInOrder() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let good = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-7200), end: clock.now.addingTimeInterval(-3600))
            let bad = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-60), end: clock.now.addingTimeInterval(-120))
            let ids = [UUID(), UUID()]
            let results = try await farm.push([.shift(bad), .shift(good)], as: farm.admin, ids: ids)
            #expect(results.map(\.mutationId) == ids)
            #expect(results.map(\.status) == [.rejected, .applied])
        }
    }
}
