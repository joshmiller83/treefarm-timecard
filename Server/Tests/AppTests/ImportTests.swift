import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

/// Synthetic artifact exports only; real time cards never go in the repo.
enum SampleExport {
    static func json(farm: String = "Pine Hollow", name: String = "Jo Field", job: String = "Shaper", rate: Double = 15,
                     weekStart: Int = 0, openShift: Bool = true, start: Date) -> Data {
        let ms = { (d: Date) in Int64(d.timeIntervalSince1970 * 1000) }
        let day1 = start
        let day2 = start.addingTimeInterval(24 * 3600)
        let s1 = """
        {"id":"s1","start":\(ms(day1)),"end":\(ms(day1.addingTimeInterval(8 * 3600))),
         "breaks":[{"type":"lunch","start":\(ms(day1.addingTimeInterval(4 * 3600))),"end":\(ms(day1.addingTimeInterval(4.5 * 3600))),"reason":""}],
         "notes":"Block 1, first rows","trees":{"b1":[0,1,2,1000,1001],"b2":[5]},"updatedAt":\(ms(day1.addingTimeInterval(8 * 3600)))}
        """
        let s2end = openShift ? "" : ",\"end\":\(ms(day2.addingTimeInterval(3600)))"
        let s2 = """
        {"id":"s2","start":\(ms(day2))\(s2end),"breaks":[],"notes":"","trees":{"b1":[2,2001],"zz":[1]},"updatedAt":\(ms(day2))}
        """
        let text = """
        {"settings":{"farm":"\(farm)","job":"\(job)","name":"\(name)","rate":\(rate),"weekStart":\(weekStart)},
         "field":{"batches":[{"id":"b1","name":"1","rows":61,"trees":10,"dir":"across"},{"id":"b2","name":"2","rows":61,"trees":10,"dir":"down"}]},
         "shifts":[\(s1),\(s2)]}
        """
        return Data(text.utf8)
    }
}

@Suite("Artifact import")
struct ImportTests {
    @Test func importsBlocksShiftsAndMarksForThePerson() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let start = clock.now.addingTimeInterval(-3 * 24 * 3600)
            clock.advance(-1) // the open shift started two days ago
            let summary = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: "JOSH@example.com",
                                                        data: SampleExport.json(start: start))
            #expect(summary.blocks.added == 2)
            #expect(summary.shifts.added == 2)
            // s2 claims tree 2 again (s1 keeps it) and one tree in an unknown block.
            #expect(summary.marks.added == 7)
            #expect(summary.warnings.contains { $0.contains("more than one shift") })
            #expect(summary.warnings.contains { $0.contains("zz") })

            let store = RecordStore(db: app.db)
            let blocks = try await store.all(.block, farm: farm.farmId)
            #expect(blocks.count == 2)
            if case .block(let b) = blocks[0].record { #expect(b.fieldId == farm.fieldId) }
            let shifts = try await store.all(.shift, farm: farm.farmId)
            #expect(shifts.count == 2)
            #expect(try await TreeClaimModel.query(on: app.db).count() == 7)
            #expect(try await RecordModel.query(on: app.db).filter(\.$kind == "treeMark").count() == 7)

            let member = try #require(try await store.member(farm.admin.userId, farm: farm.farmId))
            #expect(member.displayName == "Jo Field")
            #expect(member.jobTitle == "Shaper")
            #expect(member.rateCents == 1500)
            let f = try #require(try await store.farm(farm.farmId))
            #expect(f.name == "Pine Hollow")
            #expect(f.weekStart == .sunday)
            #expect(summary.lines.joined(separator: "\n").contains("7 marks"))
        }
    }

    @Test func runningItTwiceChangesNothing() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let data = SampleExport.json(start: clock.now.addingTimeInterval(-3 * 24 * 3600))
            _ = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: farm.admin.email, data: data)
            let seq = try await RecordStore(db: app.db).maxSeq()
            clock.advance(3600)
            let again = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: farm.admin.email, data: data)
            #expect(again.blocks.added == 0 && again.blocks.updated == 0)
            #expect(again.shifts.added == 0 && again.shifts.updated == 0)
            #expect(again.marks.added == 0)
            #expect(try await RecordStore(db: app.db).maxSeq() == seq)
            #expect(try await RecordModel.query(on: app.db).filter(\.$kind == "shift").count() == 2)
        }
    }

    @Test func keepsTheFarmsSettingsOnceSomeoneChangedThem() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let store = RecordStore(db: app.db)
            var f = try #require(try await store.farm(farm.farmId))
            f.name = "Renamed in the app"
            f.updatedAt = clock.now
            try await store.save(.farm(f), farm: farm.farmId)
            let summary = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: farm.admin.email,
                                                        data: SampleExport.json(start: clock.now.addingTimeInterval(-3 * 24 * 3600)))
            #expect(try await store.farm(farm.farmId)?.name == "Renamed in the app")
            #expect(try await store.farm(farm.farmId)?.weekStart == .monday)
            #expect(summary.warnings.contains { $0.contains("farm’s name") })
        }
    }

    @Test func treesAlreadyShapedOnTheServerAreLeftAlone() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let start = clock.now.addingTimeInterval(-3 * 24 * 3600)
            let blockId = StableID.uuid(farm.farmId, "block:b1")
            let store = RecordStore(db: app.db)
            let block = Block(id: blockId, fieldId: farm.fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 61, treesPerRow: 10, updatedAt: clock.now)
            try await store.save(.block(block), farm: farm.farmId)
            let other = Shift(userId: farm.admin.userId, farmId: farm.farmId, start: start.addingTimeInterval(-24 * 3600), end: start.addingTimeInterval(-20 * 3600), rateCents: 0, updatedAt: clock.now)
            try await store.save(.shift(other), farm: farm.farmId)
            let mark = TreeMark(seasonId: farm.seasonId, tree: TreeRef(blockId: blockId, row: 0, position: 0), shiftId: other.id, userId: farm.admin.userId, markedAt: clock.now)
            let outcome = try await TreeClaims.claim(mark, farm: farm.farmId, on: app.db)
            #expect(outcome == nil)
            try await store.save(.treeMark(mark), farm: farm.farmId)

            let summary = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: farm.admin.email, data: SampleExport.json(start: start))
            #expect(summary.marks.added == 6)
            #expect(summary.marks.skipped == 1)
            let claim = try #require(try await TreeClaimModel.query(on: app.db).filter(\.$blockId == blockId).filter(\.$row == 0).filter(\.$position == 0).first())
            #expect(claim.markId == mark.id)
        }
    }

    @Test func refusesPeopleWhoAreNotOnTheFarm() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let data = SampleExport.json(start: clock.now.addingTimeInterval(-3 * 24 * 3600))
            await #expect(throws: (any Error).self) {
                _ = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: "nobody@example.com", data: data)
            }
            let other = try await FarmFixture.make(app, farmName: "Other", adminEmail: "other@example.com")
            await #expect(throws: (any Error).self) {
                _ = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: other.admin.email, data: data)
            }
            await #expect(throws: (any Error).self) {
                _ = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: farm.admin.email, data: Data("not json".utf8))
            }
        }
    }

    @Test func makesAFieldWhenTheFarmHasNone() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            let store = RecordStore(db: app.db)
            var field = try #require(try await store.field(farm.fieldId, farm: farm.farmId))
            field.deletedAt = clock.now
            try await store.save(.field(field), farm: farm.farmId)
            _ = try await ArtifactImporter.run(app: app, farmId: farm.farmId, email: farm.admin.email,
                                               data: SampleExport.json(start: clock.now.addingTimeInterval(-3 * 24 * 3600)))
            let fields = try await store.all(.field, farm: farm.farmId).compactMap { r -> Field? in
                if case .field(let f) = r.record, f.deletedAt == nil { return f }
                return nil
            }
            #expect(fields.map(\.name) == ["Field 1"])
            let blocks = try await store.all(.block, farm: farm.farmId)
            if case .block(let b) = blocks[0].record { #expect(b.fieldId == fields[0].id) }
        }
    }
}
