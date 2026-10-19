import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Push: farm, seasons, fields and blocks")
struct LayoutPushTests {
    @Test func adminsAddBlocksAndWorkersCannot() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let block = Block(fieldId: farm.fieldId, name: " 3 ", gridRow: 0, gridColumn: 2, rowCount: 61, treesPerRow: 10, updatedAt: clock.now)
            #expect(try await farm.push(.block(block), as: sam).reason == .forbidden)
            #expect(try await farm.push(.block(block), as: farm.admin).isApplied)
            #expect(try await RecordStore(db: app.db).block(block.id, farm: farm.farmId)?.name == "3")
        }
    }

    @Test func blocksAreChecked() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let other = try await FarmFixture.make(app, farmName: "B", adminEmail: "b@example.com")
            let zero = Block(fieldId: farm.fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 0, treesPerRow: 10, updatedAt: clock.now)
            #expect(try await farm.push(.block(zero), as: farm.admin).reason == .invalid)
            let huge = Block(fieldId: farm.fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 10, treesPerRow: 301, updatedAt: clock.now)
            #expect(try await farm.push(.block(huge), as: farm.admin).reason == .invalid)
            let unnamed = Block(fieldId: farm.fieldId, name: "  ", gridRow: 0, gridColumn: 0, rowCount: 10, treesPerRow: 10, updatedAt: clock.now)
            let res = try await farm.push(.block(unnamed), as: farm.admin)
            #expect(res.message == "Give the block a name.")
            let negative = Block(fieldId: farm.fieldId, name: "1", gridRow: -1, gridColumn: 0, rowCount: 10, treesPerRow: 10, updatedAt: clock.now)
            #expect(try await farm.push(.block(negative), as: farm.admin).reason == .invalid)
            let elsewhere = Block(fieldId: other.fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 10, treesPerRow: 10, updatedAt: clock.now)
            #expect(try await farm.push(.block(elsewhere), as: farm.admin).reason == .notFound)
        }
    }

    @Test func aResizeThatWouldStrandMarksIsRefused() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock(rows: 61, trees: 10)
            let shift = try await farm.clockIn(farm.admin)
            try await farm.push(.treeMark(farm.mark(block, row: 50, tree: 9, on: shift)), as: farm.admin)

            let shorter = try await farm.push(.block(edited(block) { $0.rowCount = 50 }), as: farm.admin)
            #expect(shorter.reason == .blockInUse)
            #expect(shorter.message == "1 shaped tree would fall outside that size. Erase it first, or keep the size.")
            #expect(try await farm.push(.block(edited(block) { $0.treesPerRow = 9 }), as: farm.admin).reason == .blockInUse)
            #expect(try await farm.push(.block(edited(block) { $0.rowCount = 51; $0.name = "One" }), as: farm.admin).isApplied)
            #expect(try await farm.push(.block(edited(block, by: 2) { $0.rowCount = 80; $0.direction = .down }), as: farm.admin).isApplied)
        }
    }

    @Test func notesAndOldSeasonsCountToo() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock(rows: 61, trees: 10)
            _ = try await farm.seedNote(block, row: 60, tree: 0, by: farm.admin)
            #expect(try await farm.push(.block(edited(block) { $0.rowCount = 60 }), as: farm.admin).reason == .blockInUse)

            // A mark from last season still holds the block's size.
            let block2 = try await farm.seedBlock(name: "2", rows: 10, trees: 10, column: 1)
            let shift = try await farm.clockIn(farm.admin)
            try await farm.push(.treeMark(farm.mark(block2, row: 9, tree: 9, on: shift)), as: farm.admin)
            let next = Season(farmId: farm.farmId, name: "2026", startedAt: clock.now, updatedAt: clock.now)
            #expect(try await farm.push(.season(next), as: farm.admin).isApplied)
            #expect(try await farm.push(.farm(edited(try await farm.farmRecord()) { $0.activeSeasonId = next.id }), as: farm.admin).isApplied)
            #expect(try await farm.push(.block(edited(block2) { $0.rowCount = 5 }), as: farm.admin).reason == .blockInUse)
        }
    }

    @Test func blocksWithMarksOrNotesStayPut() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock()
            let shift = try await farm.clockIn(farm.admin)
            var mark = farm.mark(block, row: 0, tree: 0, on: shift)
            try await farm.push(.treeMark(mark), as: farm.admin)

            let remove = try await farm.push(.block(edited(block) { $0.deletedAt = clock.now }), as: farm.admin)
            #expect(remove.reason == .blockInUse)
            #expect(remove.message?.contains("can’t be removed") == true)

            let north = Field(farmId: farm.farmId, name: "North", sortOrder: 1, updatedAt: clock.now)
            #expect(try await farm.push(.field(north), as: farm.admin).isApplied)
            #expect(try await farm.push(.block(edited(block) { $0.fieldId = north.id }), as: farm.admin).reason == .blockInUse)
            // Moving around the grid is fine.
            #expect(try await farm.push(.block(edited(block) { $0.gridRow = 1; $0.gridColumn = 3 }), as: farm.admin).isApplied)

            mark.deletedAt = clock.now
            mark.updatedAt = clock.now.addingTimeInterval(1)
            try await farm.push(.treeMark(mark), as: farm.admin)
            let moved = try #require(try await RecordStore(db: app.db).block(block.id, farm: farm.farmId))
            #expect(try await farm.push(.block(edited(moved) { $0.fieldId = north.id }), as: farm.admin).isApplied)
            let current = try #require(try await RecordStore(db: app.db).block(block.id, farm: farm.farmId))
            #expect(try await farm.push(.block(edited(current) { $0.deletedAt = clock.now }), as: farm.admin).isApplied)
        }
    }

    @Test func fieldsAreForAdminsAndKeepTheirBlocks() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let north = Field(farmId: farm.farmId, name: "North", sortOrder: 1, updatedAt: clock.now)
            #expect(try await farm.push(.field(north), as: sam).reason == .forbidden)
            #expect(try await farm.push(.field(edited(north) { $0.name = " " }), as: farm.admin).reason == .invalid)
            #expect(try await farm.push(.field(edited(north) { $0.farmId = UUID() }), as: farm.admin).reason == .forbidden)
            #expect(try await farm.push(.field(north), as: farm.admin).isApplied)

            _ = try await farm.seedBlock()
            let field1 = try #require(try await RecordStore(db: app.db).field(farm.fieldId, farm: farm.farmId))
            let res = try await farm.push(.field(edited(field1) { $0.deletedAt = clock.now }), as: farm.admin)
            #expect(res.reason == .invalid)
            #expect(try await farm.push(.field(edited(field1) { $0.archivedAt = clock.now }), as: farm.admin).isApplied)
            #expect(try await farm.push(.field(edited(north, by: 2) { $0.deletedAt = clock.now }), as: farm.admin).isApplied)
        }
    }

    @Test func seasonsAreForAdmins() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let next = Season(farmId: farm.farmId, name: "2026", startedAt: clock.now, updatedAt: clock.now)
            #expect(try await farm.push(.season(next), as: sam).reason == .forbidden)
            #expect(try await farm.push(.season(edited(next) { $0.name = "" }), as: farm.admin).reason == .invalid)
            #expect(try await farm.push(.season(edited(next) { $0.farmId = UUID() }), as: farm.admin).reason == .forbidden)
            #expect(try await farm.push(.season(next), as: farm.admin).isApplied)
        }
    }

    @Test func aNewSeasonStartsWithACleanMap() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let block = try await farm.seedBlock()
            let shift = try await farm.clockIn(farm.admin)
            try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: shift)), as: farm.admin)
            let next = Season(farmId: farm.farmId, name: "2026", startedAt: clock.now, updatedAt: clock.now)
            try await farm.push(.season(next), as: farm.admin)
            try await farm.push(.farm(edited(try await farm.farmRecord()) { $0.activeSeasonId = next.id }), as: farm.admin)
            #expect(try await farm.push(.treeMark(farm.mark(block, row: 0, tree: 0, on: shift, season: next.id)), as: farm.admin).isApplied)
        }
    }

    @Test func adminsChangeTheFarm() async throws {
        try await withTestApp { app, _ in
            let farm = try await FarmFixture.make(app)
            let sam = try await farm.join("Sam")
            let record = try await farm.farmRecord()
            #expect(try await farm.push(.farm(edited(record) { $0.name = "Mine now" }), as: sam).reason == .forbidden)
            #expect(try await farm.push(.farm(edited(record) { $0.timeZoneId = "Mars/Olympus" }), as: farm.admin).reason == .invalid)
            #expect(try await farm.push(.farm(edited(record) { $0.activeSeasonId = UUID() }), as: farm.admin).reason == .invalid)
            #expect(try await farm.push(.farm(edited(record) { $0.name = "" }), as: farm.admin).reason == .invalid)
            #expect(try await farm.push(.farm(edited(record) { $0.id = UUID() }), as: farm.admin).reason == .forbidden)
            let ok = try await farm.push(.farm(edited(record) { $0.name = "Dull’s"; $0.timeZoneId = "America/Chicago"; $0.weekStart = .sunday }), as: farm.admin)
            #expect(ok.isApplied)
            let now = try await farm.farmRecord()
            #expect(now.name == "Dull’s")
            #expect(now.timeZoneId == "America/Chicago")
            #expect(now.weekStart == .sunday)
        }
    }
}
