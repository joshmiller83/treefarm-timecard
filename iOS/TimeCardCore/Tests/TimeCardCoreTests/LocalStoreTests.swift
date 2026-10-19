import Foundation
import Testing
@testable import TimeCardCore

@Suite("Local store")
struct LocalStoreTests {
    let f = Fixtures()

    func makeStore() throws -> LocalStore {
        let store = try LocalStore.inMemory()
        try store.activate(farmId: f.farmId)
        return store
    }

    // MARK: Local saves

    @Test func saveWritesRecordsAndQueuesMutationsTogether() throws {
        let store = try makeStore()
        let mark = f.mark(row: 3, position: 4)
        let mutations = try store.save([.shift(f.shift()), .treeMark(mark)])

        #expect(store.snapshot.shifts[f.shiftId] == f.shift())
        #expect(store.snapshot.marks[mark.id] == mark)

        let outbox = try store.outbox(farmId: f.farmId, limit: 10)
        #expect(outbox.map(\.record) == [.shift(f.shift()), .treeMark(mark)])
        #expect(outbox.map(\.mutationId) == mutations.map(\.id))
        #expect(outbox.allSatisfy { $0.attempts == 0 && $0.lastError == nil })
        #expect(try store.pendingCount() == 2)
    }

    @Test func saveNeedsAnActiveFarm() throws {
        let store = try LocalStore.inMemory()
        #expect(throws: StoreError.noActiveFarm) {
            try store.save([.shift(f.shift())])
        }
    }

    @Test func aSecondEditToAnUnsentRecordReplacesItsQueuedMutation() throws {
        let store = try makeStore()
        let first = try store.save([.shift(f.shift(notes: "a"))])
        let mark = f.mark(row: 0, position: 0)
        try store.save([.treeMark(mark)])
        let second = try store.save([.shift(f.shift(notes: "ab", updatedAt: Fixtures.t0 + 5))])

        let outbox = try store.outbox(farmId: f.farmId, limit: 10)
        // Still two rows, and the shift keeps its place ahead of the mark that refers to it.
        #expect(outbox.map(\.entityId) == [f.shiftId, mark.id])
        #expect(outbox[0].record == .shift(f.shift(notes: "ab", updatedAt: Fixtures.t0 + 5)))
        // A fresh mutation id, so a reply to the old one can't clear the new edit.
        #expect(outbox[0].mutationId == second[0].id)
        #expect(outbox[0].mutationId != first[0].id)
    }

    @Test func deletingARecordTakesItOutOfTheSnapshot() throws {
        let store = try makeStore()
        let mark = f.mark(row: 1, position: 1)
        try store.save([.treeMark(mark)])
        var gone = mark
        gone.deletedAt = Fixtures.t0 + 60
        gone.updatedAt = Fixtures.t0 + 60
        try store.save([.treeMark(gone)])

        #expect(store.snapshot.marks.isEmpty)
        #expect(try store.outbox(farmId: f.farmId, limit: 10).map(\.record) == [.treeMark(gone)])
    }

    @Test func theSnapshotComesBackAfterARestart() throws {
        let dir = try temporaryDirectory()
        let marks = (0..<500).map { f.mark(row: $0 / 10, position: $0 % 10) }
        do {
            let store = try LocalStore.onDisk(directory: dir)
            try store.activate(farmId: f.farmId)
            try store.applyRemote(f.changes(f.layout), farmId: f.farmId, cursor: 5)
            try store.save([.shift(f.shift())] + marks.map(SyncRecord.treeMark))
        }
        let reopened = try LocalStore.onDisk(directory: dir)
        try reopened.activate(farmId: f.farmId)
        let snap = reopened.snapshot
        #expect(snap.farm == f.farm)
        #expect(snap.members[f.userId] == f.member)
        #expect(snap.seasons[f.seasonId] == f.season)
        #expect(snap.fields[f.fieldId] == f.field)
        #expect(snap.blocks[f.blockId] == f.block)
        #expect(snap.shifts[f.shiftId] == f.shift())
        #expect(snap.marks.count == 500)
        #expect(try reopened.pendingCount() == 501)
        #expect(try reopened.cursor(farmId: f.farmId) == 5)
    }

    @Test func theSnapshotHoldsOnlyTheActiveFarm() throws {
        let store = try makeStore()
        let other = Farm(name: "Elsewhere", timeZoneId: "UTC", updatedAt: Fixtures.t0)
        try store.applyRemote([Change(seq: 1, record: .farm(other))], farmId: other.id, cursor: 1)
        #expect(store.snapshot.farm == nil)
        try store.activate(farmId: other.id)
        #expect(store.snapshot.farm == other)
        #expect(store.snapshot.farmId == other.id)
    }

    // MARK: Pulled records

    @Test func pulledRecordsReplaceLocalOnesAndMoveTheCursor() throws {
        let store = try makeStore()
        try store.applyRemote(f.changes([.shift(f.shift(notes: "old"))]), farmId: f.farmId, cursor: 1)
        try store.applyRemote(f.changes([.shift(f.shift(notes: "new", updatedAt: Fixtures.t0 + 9))], from: 2), farmId: f.farmId, cursor: 2)

        #expect(store.snapshot.shifts[f.shiftId]?.notes == "new")
        #expect(try store.cursor(farmId: f.farmId) == 2)
        #expect(try store.pendingCount() == 0)
    }

    @Test func pendingLocalEditsWinOverPulledCopies() throws {
        let store = try makeStore()
        let mutations = try store.save([.shift(f.shift(notes: "mine", updatedAt: Fixtures.t0 + 10))])
        try store.applyRemote(f.changes([.shift(f.shift(notes: "server", updatedAt: Fixtures.t0 + 20))]), farmId: f.farmId, cursor: 3)
        #expect(store.snapshot.shifts[f.shiftId]?.notes == "mine")
        #expect(try store.cursor(farmId: f.farmId) == 3)

        // Once the edit has been pushed, the server's copy is the truth again.
        _ = try store.applyPushResults([.applied(mutations[0].id, seq: 4)], farmId: f.farmId)
        try store.applyRemote(f.changes([.shift(f.shift(notes: "server", updatedAt: Fixtures.t0 + 20))], from: 5), farmId: f.farmId, cursor: 5)
        #expect(store.snapshot.shifts[f.shiftId]?.notes == "server")
    }

    @Test func pulledDeletesRemoveRecords() throws {
        let store = try makeStore()
        let mark = f.mark(row: 2, position: 2)
        try store.applyRemote(f.changes([.treeMark(mark)]), farmId: f.farmId, cursor: 1)
        #expect(store.snapshot.marks[mark.id] != nil)
        var gone = mark
        gone.deletedAt = Fixtures.t0 + 1
        try store.applyRemote(f.changes([.treeMark(gone)], from: 2), farmId: f.farmId, cursor: 2)
        #expect(store.snapshot.marks[mark.id] == nil)
    }

    // MARK: Push results

    @Test func appliedMutationsLeaveTheOutbox() throws {
        let store = try makeStore()
        let mutations = try store.save([.shift(f.shift()), .treeMark(f.mark(row: 0, position: 1))])
        let rejections = try store.applyPushResults([.applied(mutations[0].id, seq: 1)], farmId: f.farmId)
        #expect(rejections.isEmpty)
        #expect(try store.outbox(farmId: f.farmId, limit: 10).map(\.mutationId) == [mutations[1].id])
    }

    @Test func aRejectionWithTheServerCopyKeepsTheServerCopy() throws {
        let store = try makeStore()
        let mutations = try store.save([.shift(f.shift(notes: "mine"))])
        let theirs = f.shift(notes: "theirs", updatedAt: Fixtures.t0 + 30)
        let rejections = try store.applyPushResults(
            [.rejected(mutations[0].id, .invalid, "Clock-out has to be after clock-in.", current: .shift(theirs))], farmId: f.farmId)

        #expect(rejections == [Rejection(mutationId: mutations[0].id, kind: .shift, entityId: f.shiftId, reason: .invalid,
                                         message: "Clock-out has to be after clock-in.", restoredFromServer: true)])
        #expect(store.snapshot.shifts[f.shiftId] == theirs)
        #expect(try store.pendingCount() == 0)
    }

    @Test func aTakenTreeSwapsOurMarkForTheWinningOne() throws {
        let store = try makeStore()
        let ours = f.mark(row: 11, position: 3)
        let mutations = try store.save([.treeMark(ours)])
        let winner = f.mark(row: 11, position: 3, userId: f.otherUserId, shiftId: UUID())
        let rejections = try store.applyPushResults(
            [.rejected(mutations[0].id, .treeTaken, "Row 12, tree 4 was shaped by Sam on Oct 16.", current: .treeMark(winner))], farmId: f.farmId)

        #expect(rejections.first?.message == "Row 12, tree 4 was shaped by Sam on Oct 16.")
        #expect(store.snapshot.marks[ours.id] == nil)
        #expect(store.snapshot.marks[winner.id] == winner)
    }

    @Test func aRejectionWithoutACopyRefetchesFromTheStart() throws {
        let store = try makeStore()
        try store.applyRemote(f.changes(f.layout), farmId: f.farmId, cursor: 40)
        let note = TreeNote(farmId: f.farmId, tree: TreeRef(blockId: f.blockId, row: 0, position: 0), authorId: f.userId,
                            authorName: "Josh", body: "Leaning", createdAt: Fixtures.t0)
        let mutations = try store.save([.treeNote(note), .shift(f.shift())])
        let rejections = try store.applyPushResults([
            .rejected(mutations[0].id, .forbidden, "You can't change that note."),
            .rejected(mutations[1].id, .notFound, "That farm is gone."),
        ], farmId: f.farmId)

        #expect(rejections.map(\.restoredFromServer) == [false, false])
        #expect(try store.cursor(farmId: f.farmId) == 0)
        #expect(try store.pendingCount() == 0)

        // The pull from 0 brings back the shift (so it stays) but not the note.
        try store.applyRemote(f.changes(f.layout + [.shift(f.shift(notes: "server"))]), farmId: f.farmId, cursor: 41)
        try store.finishPull(farmId: f.farmId)
        #expect(store.snapshot.shifts[f.shiftId]?.notes == "server")
        #expect(store.snapshot.notes[note.id] == nil)
        #expect(try store.refetchCount(farmId: f.farmId) == 0)
    }

    @Test func aReplyToAReplacedMutationIsIgnored() throws {
        let store = try makeStore()
        let first = try store.save([.shift(f.shift(notes: "a"))])
        try store.save([.shift(f.shift(notes: "ab"))])
        let rejections = try store.applyPushResults([.rejected(first[0].id, .invalid, "No.")], farmId: f.farmId)
        #expect(rejections.isEmpty)
        #expect(store.snapshot.shifts[f.shiftId]?.notes == "ab")
        #expect(try store.pendingCount() == 1)
        #expect(try store.cursor(farmId: f.farmId) == 0)
    }

    @Test func failedAttemptsAreCounted() throws {
        let store = try makeStore()
        let mutations = try store.save([.shift(f.shift())])
        try store.recordAttempt(mutationIds: mutations.map(\.id), error: "You're offline.")
        try store.recordAttempt(mutationIds: mutations.map(\.id), error: "You're offline.")
        let entry = try #require(try store.outbox(farmId: f.farmId, limit: 1).first)
        #expect(entry.attempts == 2)
        #expect(entry.lastError == "You're offline.")
    }

    @Test func theOutboxPagesOldestFirst() throws {
        let store = try makeStore()
        let marks = (0..<25).map { f.mark(row: 0, position: $0 % 10, at: Fixtures.t0 + Double($0)) }
        try store.save(marks.map(SyncRecord.treeMark))
        let page1 = try store.outbox(farmId: f.farmId, limit: 10)
        let page2 = try store.outbox(farmId: f.farmId, after: page1.last!.seq, limit: 10)
        #expect(page1.map(\.entityId) == marks[0..<10].map(\.id))
        #expect(page2.map(\.entityId) == marks[10..<20].map(\.id))
    }

    // MARK: Small values, observation, wipe

    @Test func keepsSmallValues() throws {
        let store = try makeStore()
        #expect(try store.value(forKey: "k") == nil)
        try store.setValue(Data("v".utf8), forKey: "k")
        #expect(try store.value(forKey: "k") == Data("v".utf8))
        try store.setValue(nil, forKey: "k")
        #expect(try store.value(forKey: "k") == nil)
    }

    @Test func tellsObserversAboutWrites() async throws {
        let store = try makeStore()
        let events = store.events()
        try store.save([.shift(f.shift())])
        try store.applyRemote(f.changes(f.layout), farmId: f.farmId, cursor: 5)
        var iterator = events.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first == StoreChange(origin: .local, pendingCount: 1))
        #expect(second == StoreChange(origin: .remote, pendingCount: 1))
    }

    @Test func wipeForgetsEverything() throws {
        let store = try makeStore()
        try store.applyRemote(f.changes(f.layout), farmId: f.farmId, cursor: 5)
        try store.save([.shift(f.shift())])
        try store.setValue(Data([1]), forKey: "me")
        try store.wipe()
        #expect(store.snapshot == FarmSnapshot(farmId: f.farmId))
        #expect(try store.pendingCount() == 0)
        #expect(try store.cursor(farmId: f.farmId) == 0)
        #expect(try store.value(forKey: "me") == nil)
    }
}
