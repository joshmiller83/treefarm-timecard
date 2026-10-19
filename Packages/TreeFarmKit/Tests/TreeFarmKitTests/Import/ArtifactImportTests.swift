import Foundation
import Testing
@testable import TreeFarmKit

/// A made-up export in the original web artifact's shape. Never real data.
/// Times are milliseconds since 1970. Trees are row * 1000 + tree, both from 0.
enum ArtifactFixture {
    static let day: Double = 86_400_000
    static let hour: Double = 3_600_000
    static let t: Double = 1_760_000_000_000

    static let json = """
    {
      "settings": { "name": "Pat Example", "job": "Tree trimming", "farm": "Example Tree Farm", "rate": 15.5, "weekStart": 0 },
      "field": { "batches": [
        { "id": "b1", "name": "Block 1", "rows": 3, "trees": 4 },
        { "id": "b2", "name": " North ", "rows": 2, "trees": 5, "dir": "down" },
        { "id": "b3", "name": "", "rows": 500, "trees": 0, "dir": "across" },
        { "id": "b1", "name": "Copy of block 1", "rows": 9, "trees": 9 }
      ] },
      "shifts": [
        { "id": "s2", "start": \(t + day), "end": \(t + day + 8 * hour),
          "breaks": [ { "type": "lunch", "start": \(t + day + 4 * hour), "end": \(t + day + 4.5 * hour), "reason": "" } ],
          "notes": "Rows 2 and 3", "trees": { "b1": [0, 1, 2000, 1001], "b2": [0, 4, 1003, 9] }, "updatedAt": \(t + day + 9 * hour) },
        { "id": "s1", "start": \(t), "end": \(t + 8 * hour),
          "breaks": [ { "type": "break", "start": \(t + hour), "end": \(t + 1.25 * hour), "reason": "Fuel run" } ],
          "trees": { "b1": [3, 2, 1, 0, 5, 1000, 1000], "gone": [0, 1] } },
        { "id": "s3", "start": \(t + 2 * day), "end": null,
          "breaks": [ { "type": "lunch", "start": \(t + 2 * day + hour), "end": null } ],
          "notes": "Still going", "trees": { "b1": [2002] } }
      ]
    }
    """

    static func export() throws -> ArtifactExport {
        try JSONDecoder().decode(ArtifactExport.self, from: Data(json.utf8))
    }

    static func date(_ ms: Double) -> Date { Date(timeIntervalSince1970: ms / 1000) }
}

@Suite("ArtifactImport")
struct ArtifactImportTests {
    typealias A = ArtifactFixture
    let farm = UUID(uuidString: "FA000000-0000-0000-0000-000000000001")!
    let field = UUID(uuidString: "F1E1D000-0000-0000-0000-000000000001")!
    let user = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    let season = UUID(uuidString: "5EA50000-0000-0000-0000-000000000001")!
    let now = Date(timeIntervalSince1970: 1_770_000_000)

    func run(_ export: ArtifactExport? = nil, now: Date? = nil) throws -> ArtifactImportResult {
        ArtifactImport.run(try export ?? A.export(), farmId: farm, fieldId: field, userId: user, seasonId: season, now: now ?? self.now)
    }

    @Test func settingsComeAcross() throws {
        let r = try run()
        #expect(r.displayName == "Pat Example")
        #expect(r.jobTitle == "Tree trimming")
        #expect(r.farmName == "Example Tree Farm")
        #expect(r.rateCents == 1550)
        #expect(r.weekStart == .sunday)
    }

    @Test func weekStartAndRateVariants() throws {
        var export = try A.export()
        export.settings?.weekStart = 1
        export.settings?.rate = 15.555
        let r = try run(export)
        #expect(r.weekStart == .monday)
        #expect(r.rateCents == 1556)
        export.settings = nil
        let bare = try run(export)
        #expect(bare.displayName == nil && bare.rateCents == nil && bare.weekStart == nil)
        #expect(bare.shifts.allSatisfy { $0.rateCents == 0 })
    }

    @Test func blocksGoInOneStripInOrder() throws {
        let blocks = try run().blocks
        #expect(blocks.map(\.name) == ["Block 1", "North", "Block 3"])
        #expect(blocks.map(\.gridRow) == [0, 0, 0])
        #expect(blocks.map(\.gridColumn) == [0, 1, 2])
        #expect(blocks.map(\.direction) == [.across, .down, .across])
        #expect(blocks.map(\.rowCount) == [3, 2, 300])
        #expect(blocks.map(\.treesPerRow) == [4, 5, 1])
        #expect(blocks.allSatisfy { $0.fieldId == field && $0.deletedAt == nil && $0.updatedAt == now })
        #expect(blocks[0].id == StableID.uuid(farm, "block:b1"))
        #expect(blocks[1].id == StableID.uuid(farm, "block:b2"))
    }

    @Test func shiftsKeepTheirTimesBreaksAndNotes() throws {
        let shifts = try run().shifts
        #expect(shifts.map(\.id) == ["s1", "s2", "s3"].map { StableID.uuid(farm, "shift:\($0)") })
        let s1 = shifts[0], s2 = shifts[1], s3 = shifts[2]
        #expect(s1.start == A.date(A.t))
        #expect(s1.end == A.date(A.t + 8 * A.hour))
        #expect(s1.userId == user && s1.farmId == farm)
        #expect(s1.rateCents == 1550)
        #expect(s1.notes == "")
        #expect(s1.breaks.count == 1)
        #expect(s1.breaks[0].kind == .break)
        #expect(s1.breaks[0].reason == "Fuel run")
        #expect(s1.breaks[0].start == A.date(A.t + A.hour))
        #expect(s1.breaks[0].end == A.date(A.t + 1.25 * A.hour))
        #expect(s1.breaks[0].id == StableID.uuid(farm, "break:s1:0"))
        #expect(s1.updatedAt == now)
        #expect(s2.notes == "Rows 2 and 3")
        #expect(s2.breaks.map(\.kind) == [.lunch])
        #expect(s2.updatedAt == A.date(A.t + A.day + 9 * A.hour))
        #expect(s3.isOpen)
        #expect(s3.openBreak?.kind == .lunch)
        #expect(s3.breaks[0].end == nil)
    }

    @Test func treesBecomeMarksOnTheEarliestShift() throws {
        let r = try run()
        func trees(_ shift: String) -> [[Int]] {
            let id = StableID.uuid(farm, "shift:\(shift)")
            return r.marks.filter { $0.shiftId == id }.map { m in [r.blocks.firstIndex { $0.id == m.blockId }! + 1, m.row, m.position] }
        }
        #expect(trees("s1") == [[1, 0, 0], [1, 0, 1], [1, 0, 2], [1, 0, 3], [1, 1, 0]])
        #expect(trees("s2") == [[1, 1, 1], [1, 2, 0], [2, 0, 0], [2, 0, 4], [2, 1, 3]])
        #expect(trees("s3") == [[1, 2, 2]])
        #expect(r.marks.count == 11)
        #expect(Set(r.marks.map(\.tree)).count == 11)
    }

    @Test func marksCarryTheSeasonUserAndShiftTime() throws {
        let r = try run()
        let s1 = StableID.uuid(farm, "shift:s1"), s3 = StableID.uuid(farm, "shift:s3")
        #expect(r.marks.allSatisfy { $0.seasonId == season && $0.userId == user && $0.isLive })
        #expect(r.marks.filter { $0.shiftId == s1 }.allSatisfy { $0.markedAt == A.date(A.t + 8 * A.hour) })
        #expect(r.marks.filter { $0.shiftId == s3 }.allSatisfy { $0.markedAt == A.date(A.t + 2 * A.day) })
        let first = try #require(r.marks.first)
        #expect(first.id == StableID.uuid(farm, "mark:\(season.uuidString):b1:0"))
    }

    @Test func problemsComeBackAsWarnings() throws {
        let warnings = try run().warnings
        #expect(warnings.contains("Skipped a second block with the id b1."))
        #expect(warnings.contains("Block 3 was 500 rows × 0 trees, so it is now 300 × 1."))
        #expect(warnings.contains("Skipped 2 trees in a block that isn’t in the field (gone)."))
        #expect(warnings.contains("Skipped 1 tree outside Block 1."))
        #expect(warnings.contains("Skipped 1 tree outside North."))
        #expect(warnings.contains("2 trees were marked on more than one shift. The earliest shift keeps each one."))
        #expect(warnings.count == 6)
    }

    @Test func runningTwiceGivesTheSameIds() throws {
        let first = try run()
        let second = try run(now: now.addingTimeInterval(86_400))
        #expect(first.blocks.map(\.id) == second.blocks.map(\.id))
        #expect(first.shifts.map(\.id) == second.shifts.map(\.id))
        #expect(first.shifts.flatMap(\.breaks).map(\.id) == second.shifts.flatMap(\.breaks).map(\.id))
        #expect(first.marks.map(\.id) == second.marks.map(\.id))
        #expect(first.marks == second.marks)
        let again = try run()
        #expect(first.blocks == again.blocks && first.shifts == again.shifts && first.marks == again.marks)
        #expect(first.warnings == again.warnings)
    }

    @Test func anotherFarmGetsOtherIds() throws {
        let other = ArtifactImport.run(try A.export(), farmId: UUID(), fieldId: field, userId: user, seasonId: season, now: now)
        #expect(Set(other.blocks.map(\.id)).isDisjoint(with: try run().blocks.map(\.id)))
    }

    @Test func emptyExportImportsNothing() throws {
        let export = try JSONDecoder().decode(ArtifactExport.self, from: Data(#"{"shifts":[]}"#.utf8))
        let r = try run(export)
        #expect(r.blocks.isEmpty && r.shifts.isEmpty && r.marks.isEmpty && r.warnings.isEmpty)
    }

    @Test func longNotesAndReasonsAreTrimmed() throws {
        let long = String(repeating: "n", count: 2500)
        let export = ArtifactExport(settings: nil, field: nil, shifts: [
            .init(id: "s", start: A.t, end: A.t + A.hour, breaks: [.init(type: "break", start: A.t, end: A.t + 1, reason: long)], notes: long, trees: nil, updatedAt: nil),
        ])
        let shift = try #require(try run(export).shifts.first)
        #expect(shift.notes.count == Limits.notes)
        #expect(shift.breaks[0].reason.count == Limits.reason)
    }

    @Test func importedMarksFeedTheIndex() throws {
        let r = try run()
        let index = MarkIndex(marks: r.marks)
        let walker = FieldWalker(blocks: r.blocks)
        #expect(walker.progress(index: index) == (11, 12 + 10 + 300))
        #expect(index.isRowComplete(RowRef(blockId: r.blocks[0].id, row: 0), block: r.blocks[0]))
        #expect(TreeSummary.text(marks: index.marks(onShift: StableID.uuid(farm, "shift:s1")), blocks: r.blocks) == "Block 1: row 1, row 2 (tree 1)")
    }
}
