import Foundation
@testable import TimeCardCore

/// A small farm to build records against: one field, one 61×10 block, one season.
struct Fixtures {
    let farmId = UUID()
    let seasonId = UUID()
    let fieldId = UUID()
    let blockId = UUID()
    let userId = UUID()
    let shiftId = UUID()
    let otherUserId = UUID()

    static let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    var farm: Farm {
        Farm(id: farmId, name: "Test Tree Farm", timeZoneId: "America/Indiana/Indianapolis", activeSeasonId: seasonId, updatedAt: Self.t0)
    }

    var season: Season { Season(id: seasonId, farmId: farmId, name: "2026", startedAt: Self.t0, updatedAt: Self.t0) }
    var field: Field { Field(id: fieldId, farmId: farmId, name: "North", updatedAt: Self.t0) }
    var block: Block {
        Block(id: blockId, fieldId: fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 61, treesPerRow: 10, updatedAt: Self.t0)
    }

    var member: Member {
        Member(userId: userId, farmId: farmId, displayName: "Josh", email: "josh@example.com", role: .admin, rateCents: 1800, updatedAt: Self.t0)
    }

    func shift(notes: String = "", updatedAt: Date = Fixtures.t0, deletedAt: Date? = nil) -> Shift {
        Shift(id: shiftId, userId: userId, farmId: farmId, start: Self.t0, notes: notes, rateCents: 1800, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    func mark(id: UUID = UUID(), row: Int, position: Int, userId: UUID? = nil, shiftId: UUID? = nil, at: Date = Fixtures.t0, deletedAt: Date? = nil) -> TreeMark {
        TreeMark(id: id, seasonId: seasonId, tree: TreeRef(blockId: blockId, row: row, position: position),
                 shiftId: shiftId ?? self.shiftId, userId: userId ?? self.userId, markedAt: at, deletedAt: deletedAt)
    }

    /// The farm's layout as the server would send it on a first pull.
    var layout: [SyncRecord] { [.farm(farm), .member(member), .season(season), .field(field), .block(block)] }

    func changes(_ records: [SyncRecord], from seq: Int64 = 1) -> [Change] {
        records.enumerated().map { Change(seq: seq + Int64($0.offset), record: $0.element) }
    }
}

func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("TimeCardCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
