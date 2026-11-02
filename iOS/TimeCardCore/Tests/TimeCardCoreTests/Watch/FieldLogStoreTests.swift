import Foundation
import Testing
@testable import TimeCardCore

/// The phone keeps the watch's field logs until they're shared (docs/gis.md 10).
@Suite("Field log store")
struct FieldLogStoreTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "FieldLogStoreTests-\(UUID().uuidString)")
    var store: FieldLogStore { FieldLogStore(directory: root.appending(path: "FieldLogs")) }

    func incoming(_ name: String, _ text: String = "{}\n") throws -> URL {
        let inbox = root.appending(path: "Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appending(path: name)
        try Data(text.utf8).write(to: file)
        return file
    }

    @Test func aFieldLogIsKeptAndListedNewestFirst() throws {
        let older = try #require(store.accept(try incoming("2026-11-02T1202Z-AAAAAAAA.jsonl"), metadata: FieldLog.transferMetadata))
        store.accept(try incoming("2026-11-03T1158Z-BBBBBBBB.jsonl"), metadata: FieldLog.transferMetadata)
        #expect(FileManager.default.fileExists(atPath: older.path))
        #expect(store.logs().map(\.lastPathComponent) == ["2026-11-03T1158Z-BBBBBBBB.jsonl", "2026-11-02T1202Z-AAAAAAAA.jsonl"])
    }

    @Test func aResentLogReplacesTheCopy() throws {
        store.accept(try incoming("2026-11-02T1202Z-AAAAAAAA.jsonl", "first\n"), metadata: FieldLog.transferMetadata)
        let kept = try #require(store.accept(try incoming("2026-11-02T1202Z-AAAAAAAA.jsonl", "second\n"), metadata: FieldLog.transferMetadata))
        #expect(try String(contentsOf: kept, encoding: .utf8) == "second\n")
        #expect(store.logs().count == 1)
    }

    @Test func anythingElseIsDeleted() throws {
        let stray = try incoming("photo.jpg")
        #expect(store.accept(stray, metadata: FieldLog.transferMetadata) == nil)
        let unlabeled = try incoming("2026-11-02T1202Z-AAAAAAAA.jsonl")
        #expect(store.accept(unlabeled, metadata: [:]) == nil)
        #expect(!FileManager.default.fileExists(atPath: stray.path) && !FileManager.default.fileExists(atPath: unlabeled.path))
        #expect(store.logs().isEmpty)
    }

    @Test func oldLogsArePrunedAndAllCanBeDeleted() throws {
        let kept = try #require(store.accept(try incoming("2026-11-02T1202Z-AAAAAAAA.jsonl"), metadata: FieldLog.transferMetadata))
        store.prune(now: Date())
        #expect(store.logs().count == 1)
        store.prune(now: Date().addingTimeInterval(31 * 86_400))
        #expect(store.logs().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: kept.path))
        store.accept(try incoming("2026-11-03T1158Z-BBBBBBBB.jsonl"), metadata: FieldLog.transferMetadata)
        store.deleteAll()
        #expect(store.logs().isEmpty)
    }
}
