import Foundation
import GRDB
import Testing
@testable import TimeCardCore

@Suite("Database")
struct DatabaseTests {
    @Test func migrationsCreateTheTables() throws {
        let db = try AppDatabase.openInMemory()
        func columns(_ table: String) throws -> [String] {
            try db.read { db in try db.columns(in: table).map(\.name) }
        }
        #expect(try columns("records") == ["kind", "id", "farmId", "json", "updatedAt", "deletedAt"])
        #expect(try columns("outbox") == ["seq", "mutationId", "farmId", "kind", "entityId", "json", "createdAt", "attempts", "lastError"])
        #expect(try columns("sync_state") == ["farmId", "cursor"])
        #expect(try columns("kv") == ["key", "value"])
        #expect(try columns("refetch") == ["farmId", "kind", "id"])
    }

    @Test func protectsTheDatabaseAndItsJournalFiles() {
        let url = URL(fileURLWithPath: "/tmp/x/TimeCard.sqlite")
        #expect(AppDatabase.protectedFiles(for: url).map(\.lastPathComponent) == ["TimeCard.sqlite", "TimeCard.sqlite-wal", "TimeCard.sqlite-shm"])
    }

    @Test func livesInTheAppGroupWhenItIsAvailable() throws {
        let group = URL(fileURLWithPath: "/tmp/group-container", isDirectory: true)
        let dir = AppDatabase.directory(appGroup: "group.test", containerURL: { _ in group })
        #expect(dir == group.appendingPathComponent("Database", isDirectory: true))
    }

    @Test func fallsBackToApplicationSupportWithoutTheAppGroup() throws {
        let dir = AppDatabase.directory(appGroup: "group.test", containerURL: { _ in nil })
        #expect(dir.pathComponents.contains("Application Support"))
        #expect(dir.lastPathComponent == "Database")
        let noGroup = AppDatabase.directory(appGroup: nil, containerURL: { _ in Issue.record("not asked"); return nil })
        #expect(noGroup == dir)
    }

    @Test func opensOnDiskWithWriteAheadLogging() throws {
        let dir = try temporaryDirectory()
        let pool = try AppDatabase.open(directory: dir)
        let mode = try pool.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
        let file = dir.appendingPathComponent(AppDatabase.fileName)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: file.path + "-wal"))
    }

    @Test func letsGoOfTheSharedFileWhenTheAppSleeps() {
        // Suspension itself is process-wide, so it isn't exercised here (other tests write in parallel).
        #expect(AppDatabase.configuration().observesSuspensionNotifications)
        #expect(AppDatabase.isSuspension(DatabaseError(resultCode: .SQLITE_ABORT)))
        #expect(AppDatabase.isSuspension(DatabaseError(resultCode: .SQLITE_INTERRUPT)))
        #expect(!AppDatabase.isSuspension(DatabaseError(resultCode: .SQLITE_FULL)))
        #expect(!AppDatabase.isSuspension(APIError.offline))
    }
}
