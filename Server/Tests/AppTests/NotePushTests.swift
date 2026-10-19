import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Push: tree notes")
struct NotePushTests {
    func note(_ farm: FarmFixture, _ block: Block, by person: Person, body: String = "Leaning east", name: String? = nil) -> TreeNote {
        TreeNote(farmId: farm.farmId, tree: TreeRef(blockId: block.id, row: 4, position: 2), authorId: person.userId,
                 authorName: name ?? person.name, body: body, flag: .attention, createdAt: farm.app.now)
    }

    @Test func anyoneWritesNotesInTheirOwnName() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let block = try await farm.seedBlock()
            let n = note(farm, block, by: sam, name: "Somebody Else")
            #expect(try await farm.push(.treeNote(n), as: sam).isApplied)
            let stored = try #require(try await RecordStore(db: app.db).find(.treeNote, n.id, farm: farm.farmId))
            if case .treeNote(let saved) = stored.record { #expect(saved.authorName == "Sam") }

            let forged = note(farm, block, by: farm.admin)
            #expect(try await farm.push(.treeNote(forged), as: sam).reason == .forbidden)

            // Everyone on the farm sees notes.
            let alex = try await farm.join("Alex")
            let seen = try await farm.pullAll(as: alex).contains { c in if case .treeNote(let x) = c.record { return x.id == n.id }; return false }
            #expect(seen)
        }
    }

    @Test func authorsAndAdminsEditAndDelete() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let alex = try await farm.join("Alex")
            let block = try await farm.seedBlock()
            let n = note(farm, block, by: sam)
            try await farm.push(.treeNote(n), as: sam)

            #expect(try await farm.push(.treeNote(edited(n) { $0.body = "Mine now" }), as: alex).reason == .forbidden)
            #expect(try await farm.push(.treeNote(edited(n) { $0.deletedAt = clock.now }), as: alex).reason == .forbidden)
            #expect(try await farm.push(.treeNote(edited(n) { $0.body = "Leaning a lot"; $0.flag = .dead }), as: sam).isApplied)

            let adminEdit = edited(n, by: 2) { $0.body = "Checked"; $0.authorName = "Josh"; $0.authorId = farm.admin.userId }
            #expect(try await farm.push(.treeNote(adminEdit), as: farm.admin).isApplied)
            let stored = try #require(try await RecordStore(db: app.db).find(.treeNote, n.id, farm: farm.farmId))
            guard case .treeNote(let saved) = stored.record else { Issue.record("not a note"); return }
            #expect(saved.body == "Checked")
            #expect(saved.authorId == sam.userId)
            #expect(saved.authorName == "Sam")

            #expect(try await farm.push(.treeNote(edited(n, by: 3) { $0.deletedAt = clock.now }), as: farm.admin).isApplied)
        }
    }

    @Test func notesAreChecked() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock(rows: 5, trees: 5)
            var outside = note(farm, block, by: farm.admin)
            outside.row = 5
            #expect(try await farm.push(.treeNote(outside), as: farm.admin).reason == .invalid)

            var otherFarm = note(farm, block, by: farm.admin)
            otherFarm.farmId = UUID()
            #expect(try await farm.push(.treeNote(otherFarm), as: farm.admin).reason == .forbidden)

            var noBlock = note(farm, block, by: farm.admin)
            noBlock.blockId = UUID()
            #expect(try await farm.push(.treeNote(noBlock), as: farm.admin).reason == .notFound)

            let long = note(farm, block, by: farm.admin, body: String(repeating: "x", count: Limits.notes + 10))
            #expect(try await farm.push(.treeNote(long), as: farm.admin).isApplied)
            let stored = try #require(try await RecordStore(db: app.db).find(.treeNote, long.id, farm: farm.farmId))
            if case .treeNote(let saved) = stored.record { #expect(saved.body.count == Limits.notes) }

            let stale = edited(long, by: -10) { $0.body = "older" }
            #expect(try await farm.push(.treeNote(stale), as: farm.admin).reason == .invalid)

            let moved = edited(long) { $0.row = 0 }
            #expect(try await farm.push(.treeNote(moved), as: farm.admin).reason == .invalid)
            _ = clock
        }
    }
}
