import Foundation
import Testing
@testable import TreeFarmKit

@Suite("Record times, rounding and saved undo")
struct RecordMetadataTests {
    @Test(arguments: SyncRecordSamples.all)
    func everyRecordHasAnUpdatedAt(record: SyncRecord) {
        #expect(record.updatedAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(record.deletedAt == nil)
    }

    @Test func deletesCarryTheirDeletedAt() {
        let gone = Date(timeIntervalSince1970: 1_760_000_100)
        var field = Field(farmId: UUID(), name: "North", updatedAt: gone)
        field.deletedAt = gone
        #expect(SyncRecord.field(field).deletedAt == gone)
        let mark = TreeMark(seasonId: UUID(), tree: TreeRef(blockId: UUID(), row: 0, position: 0), shiftId: UUID(), userId: UUID(),
                            markedAt: gone, deletedAt: gone)
        #expect(SyncRecord.treeMark(mark).deletedAt == gone)
    }

    @Test func farmsMembersAndSeasonsAreNeverDeleted() {
        let farm = Farm(name: "F", timeZoneId: "UTC")
        #expect(SyncRecord.farm(farm).deletedAt == nil)
    }

    @Test func roundingToTheMillisecondSurvivesTheWire() throws {
        let raw = Date(timeIntervalSince1970: 1_760_000_000.123_456_7)
        let rounded = raw.roundedToMillisecond
        #expect(rounded.timeIntervalSince1970 == 1_760_000_000.123)
        let shift = Shift(userId: UUID(), farmId: UUID(), start: rounded, rateCents: 0, updatedAt: rounded)
        let back = try JSONCoding.decoder().decode(Shift.self, from: JSONCoding.encoder().encode(shift))
        #expect(back == shift)
        #expect(Date(timeIntervalSince1970: 1_760_000_000.123_6).roundedToMillisecond == Date(timeIntervalSince1970: 1_760_000_000.124))
    }

    @Test func undoStacksKeepTheirEntriesAndDepth() throws {
        var stack = UndoStack<String>(depth: 3, entries: ["a", "b", "c", "d"])
        #expect(stack.entries == ["b", "c", "d"])
        stack.push("e")
        #expect(stack.entries == ["c", "d", "e"])
        let back = try JSONDecoder().decode(UndoStack<String>.self, from: JSONEncoder().encode(stack))
        #expect(back.entries == ["c", "d", "e"])
        #expect(back.depth == 3)
    }

    @Test func undoEntriesSurviveJSON() throws {
        let block = UUID()
        let mark = TreeMark(seasonId: UUID(), tree: TreeRef(blockId: block, row: 3, position: 1), shiftId: UUID(), userId: UUID(),
                            markedAt: Date(timeIntervalSince1970: 10))
        let entry = UndoEntry(label: "row 4", restore: [.treeMark(mark)], position: WorkPosition(fieldId: UUID(), next: RowRef(blockId: block, row: 4)))
        let back = try JSONCoding.decoder().decode(UndoEntry.self, from: JSONCoding.encoder().encode(entry))
        #expect(back == entry)
    }
}
