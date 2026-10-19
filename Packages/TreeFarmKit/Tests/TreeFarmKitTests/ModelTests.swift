import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Model")
struct ModelTests {
    let farmId = UUID()
    let fieldId = UUID()
    let blockId = UUID()
    let userId = UUID()

    @Test func blockCountsItsTrees() {
        let block = Block(id: blockId, fieldId: fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 61, treesPerRow: 10)
        #expect(block.treeCount == 610)
        #expect(block.contains(TreeRef(blockId: blockId, row: 60, position: 9)))
        #expect(!block.contains(TreeRef(blockId: blockId, row: 61, position: 0)))
        #expect(!block.contains(TreeRef(blockId: blockId, row: 0, position: 10)))
        #expect(!block.contains(TreeRef(blockId: UUID(), row: 0, position: 0)))
        #expect(!block.contains(TreeRef(blockId: blockId, row: -1, position: 0)))
    }

    @Test func treeMarkExposesItsTreeAndRow() {
        let shiftId = UUID()
        let mark = TreeMark(seasonId: UUID(), tree: TreeRef(blockId: blockId, row: 4, position: 2), shiftId: shiftId, userId: userId, markedAt: Date(timeIntervalSince1970: 100))
        #expect(mark.tree == TreeRef(blockId: blockId, row: 4, position: 2))
        #expect(mark.tree.rowRef == RowRef(blockId: blockId, row: 4))
        #expect(mark.isLive)
        var gone = mark
        gone.deletedAt = Date(timeIntervalSince1970: 200)
        #expect(!gone.isLive)
    }

    @Test func breakIsOpenUntilItEnds() {
        let open = Break(kind: .lunch, start: Date(timeIntervalSince1970: 0))
        #expect(open.isOpen)
        let closed = Break(kind: .break, start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60), reason: "Fuel")
        #expect(!closed.isOpen)
    }

    @Test func shiftKnowsItsOpenBreak() {
        var shift = Shift(userId: userId, farmId: farmId, start: Date(timeIntervalSince1970: 0), rateCents: 1500)
        #expect(shift.isOpen)
        #expect(shift.openBreak == nil)
        shift.breaks.append(Break(kind: .lunch, start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 20)))
        shift.breaks.append(Break(kind: .break, start: Date(timeIntervalSince1970: 30)))
        #expect(shift.openBreak?.kind == .break)
        shift.end = Date(timeIntervalSince1970: 40)
        #expect(!shift.isOpen)
    }

    @Test func datesEncodeAsMillisecondsSince1970() throws {
        let shift = Shift(id: UUID(), userId: userId, farmId: farmId, start: Date(timeIntervalSince1970: 1_760_000_000.123), rateCents: 1500, updatedAt: Date(timeIntervalSince1970: 1_760_000_000))
        let data = try JSONCoding.encoder().encode(shift)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["start"] as? NSNumber)?.int64Value == 1_760_000_000_123)
        let back = try JSONCoding.decoder().decode(Shift.self, from: data)
        #expect(abs(back.start.timeIntervalSince1970 - 1_760_000_000.123) < 0.001)
    }

    @Test(arguments: SyncRecordSamples.all)
    func syncRecordsRoundTripWithAKindTag(record: SyncRecord) throws {
        let data = try JSONCoding.encoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["kind"] as? String == record.kind.rawValue)
        #expect(object["data"] != nil)
        let back = try JSONCoding.decoder().decode(SyncRecord.self, from: data)
        #expect(back == record)
        #expect(back.entityId == record.entityId)
    }

    @Test func unknownRecordKindsFailToDecode() {
        let json = #"{"kind":"tractor","data":{}}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) { try JSONCoding.decoder().decode(SyncRecord.self, from: json) }
    }

    @Test func textLimitsClampLongInput() {
        #expect(Limits.clampNotes(String(repeating: "a", count: 2500)).count == 2000)
        #expect(Limits.clampReason("  Fuel run  ") == "Fuel run")
        #expect(Limits.clampReason(String(repeating: "b", count: 100)).count == 80)
        #expect(Limits.clampName("  North field ") == "North field")
    }

    @Test func blockSizesMustFitTheLimits() {
        #expect(Limits.blockRows.contains(1))
        #expect(Limits.blockRows.contains(300))
        #expect(!Limits.blockRows.contains(0))
        #expect(!Limits.treesPerRow.contains(301))
    }
}

/// One of every record kind, for the round-trip test.
enum SyncRecordSamples {
    static let all: [SyncRecord] = {
        let t = Date(timeIntervalSince1970: 1_760_000_000)
        let farm = Farm(id: UUID(), name: "Dull's Tree Farm", timeZoneId: "America/Indiana/Indianapolis", weekStart: .monday, activeSeasonId: UUID(), updatedAt: t)
        let block = Block(id: UUID(), fieldId: UUID(), name: "1", gridRow: 1, gridColumn: 2, rowCount: 61, treesPerRow: 10, direction: .down, updatedAt: t)
        let shift = Shift(id: UUID(), userId: UUID(), farmId: farm.id, start: t, end: t.addingTimeInterval(3600),
                          breaks: [Break(kind: .lunch, start: t.addingTimeInterval(600), end: t.addingTimeInterval(1200), reason: "Lunch")],
                          notes: "Rows 1–12", rateCents: 1500, updatedAt: t)
        return [
            .farm(farm),
            .member(Member(userId: UUID(), farmId: farm.id, displayName: "Josh", email: "josh@example.com", role: .admin, jobTitle: "Tree trimming", rateCents: 1500, updatedAt: t)),
            .season(Season(id: UUID(), farmId: farm.id, name: "2026", startedAt: t, updatedAt: t)),
            .field(Field(id: UUID(), farmId: farm.id, name: "North", sortOrder: 0, updatedAt: t)),
            .block(block),
            .shift(shift),
            .treeMark(TreeMark(id: UUID(), seasonId: UUID(), tree: TreeRef(blockId: block.id, row: 3, position: 4), shiftId: shift.id, userId: shift.userId, markedAt: t, updatedAt: t)),
            .treeNote(TreeNote(id: UUID(), farmId: farm.id, tree: TreeRef(blockId: block.id, row: 3, position: 4), authorId: shift.userId, authorName: "Josh", body: "Leader is broken", flag: .attention, createdAt: t, updatedAt: t)),
        ]
    }()
}
