import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

/// A refused change carries the server's copy whenever there is one the caller may
/// see, so a phone can put its own copy right without pulling everything again.
@Suite("Rejections carry the server's copy")
struct RejectionCurrentTests {
    @Test func aRefusedEditComesBackWithTheStoredCopy() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-7200), end: clock.now.addingTimeInterval(-3600))
            #expect(try await farm.push(.shift(shift), as: farm.admin).isApplied)
            let broken = edited(shift) { $0.end = $0.start.addingTimeInterval(-60) }
            let res = try await farm.push(.shift(broken), as: farm.admin)
            #expect(res.reason == .invalid)
            #expect(res.current == .shift(shift))
        }
    }

    @Test func forbiddenEditsOfSharedThingsComeBackToo() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let block = try await farm.seedBlock()
            let note = try await farm.seedNote(block, row: 0, tree: 0, by: farm.admin)
            let res = try await farm.push(.treeNote(edited(note) { $0.body = "Mine" }), as: sam)
            #expect(res.reason == .forbidden)
            #expect(res.current == .treeNote(note))

            let blockRes = try await farm.push(.block(edited(block) { $0.rowCount = 2 }), as: sam)
            #expect(blockRes.current == .block(block))

            // Other people's member records come back redacted.
            let josh = try #require(try await RecordStore(db: app.db).member(farm.admin.userId, farm: farm.farmId))
            let memberRes = try await farm.push(.member(edited(josh) { $0.rateCents = 1 }), as: sam)
            guard case .member(let m)? = memberRes.current else { Issue.record("no current"); return }
            #expect(m.email == "")
            #expect(m.rateCents == 0)
        }
    }

    @Test func nothingLeaksThatTheCallerCannotSee() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let josh = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-3600))
            try await farm.push(.shift(josh), as: farm.admin)
            let res = try await farm.push(.shift(edited(josh) { $0.notes = "peek" }), as: sam)
            #expect(res.reason == .forbidden)
            #expect(res.current == nil)
        }
    }

    @Test func aRefusedBlockChangeComesBackWithTheBlock() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock()
            let shift = try await farm.clockIn(farm.admin)
            try await farm.push(.treeMark(farm.mark(block, row: 60, tree: 0, on: shift)), as: farm.admin)
            let res = try await farm.push(.block(edited(block) { $0.rowCount = 10 }), as: farm.admin)
            #expect(res.reason == .blockInUse)
            #expect(res.current == .block(block))
        }
    }
}
