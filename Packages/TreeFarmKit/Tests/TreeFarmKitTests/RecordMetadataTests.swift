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

@Suite("Edit stamps and rate changes")
struct EditStampTests {
    let t = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func anEditIsAlwaysAfterWhatItReplaces() {
        #expect(RecordMetadata.stamp(t + 60, after: t) == (t + 60).roundedToMillisecond)
        // This phone's clock is behind the last writer's.
        #expect(RecordMetadata.stamp(t - 60, after: t) == t.addingTimeInterval(0.001).roundedToMillisecond)
        #expect(RecordMetadata.stamp(t, after: t) == t.addingTimeInterval(0.001).roundedToMillisecond)
    }

    @Test func aNewRateRepricesTheShiftOnTheClockOnly() throws {
        let userId = UUID(), farmId = UUID()
        let old = Member(userId: userId, farmId: farmId, displayName: "Sam", email: "", role: .worker, rateCents: 1800, updatedAt: t)
        var raised = old
        raised.rateCents = 2000
        let open = Shift(userId: userId, farmId: farmId, start: t, rateCents: 1800, updatedAt: t)
        let records = RateChange.records(member: raised, from: old, openShift: open, now: t + 120)
        #expect(records.count == 2)
        guard case .shift(let repriced) = records[1] else { Issue.record("no shift"); return }
        #expect(repriced.rateCents == 2000)
        // Only the job title changed: no shift is touched.
        var retitled = old
        retitled.jobTitle = "Crew lead"
        #expect(RateChange.records(member: retitled, from: old, openShift: open, now: t + 120).count == 1)
        // A finished shift keeps its rate.
        var closed = open
        closed.end = t + 3600
        #expect(RateChange.records(member: raised, from: old, openShift: closed, now: t + 120).count == 1)
        #expect(RateChange.outOfRange == "The pay rate has to be between $0 and $10,000 an hour.")
    }
}
