import Fluent
import Foundation
import Testing
import TreeFarmKit
import Vapor
@testable import App

@Suite("Backups and upkeep")
struct BackupTests {
    func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("timecard-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func backups(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("timecard-") }.sorted()
    }

    @Test func backupWritesAWholeCopyOfTheDatabase() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await withTestApp(adjust: { $0.backupDirectory = dir.path }) { app, _ in
            _ = try await FarmFixture.make(app)
            let url = try await Backups.run(app: app)
            #expect(url.lastPathComponent.range(of: #"^timecard-\d{8}-\d{6}\.sqlite$"#, options: .regularExpression) != nil)
            let header = try FileHandle(forReadingFrom: url).readData(ofLength: 16)
            #expect(String(decoding: header, as: UTF8.self).hasPrefix("SQLite format 3"))

            // The copy opens as a server database with the farm in it.
            let copy = try await Application.make(.testing, .shared(TestSupport.eventLoopGroup))
            var config = AppConfig.testing(now: { Date() })
            config.database = .file(url.path)
            try await configure(copy, config: config)
            #expect(try await RecordModel.query(on: copy.db).filter(\.$kind == "farm").count() == 1)
            try await copy.asyncShutdown()
        }
    }

    @Test func onlyTheNewestThirtyAreKept() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for day in 1...32 {
            let name = "timecard-202501\(day < 10 ? "0" : "")\(day)-030000.sqlite"
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("old".utf8))
        }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("notes.txt").path, contents: Data())
        try await withTestApp(adjust: { $0.backupDirectory = dir.path }) { app, _ in
            let url = try await Backups.run(app: app)
            let left = try backups(in: dir)
            #expect(left.count == 30)
            #expect(left.contains(url.lastPathComponent))
            #expect(!left.contains("timecard-20250101-030000.sqlite"))
            #expect(!left.contains("timecard-20250103-030000.sqlite"))
            #expect(left.contains("timecard-20250104-030000.sqlite"))
            #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("notes.txt").path))
        }
    }

    @Test func theBackupCommandPrintsWhereItWrote() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await withTestApp(adjust: { $0.backupDirectory = dir.path }) { app, _ in
            let out = try await runCommand(app, ["backup"])
            #expect(out.contains(dir.path))
            #expect(try backups(in: dir).count == 1)
        }
    }

    /// launchd runs `backup` nightly; the server only steps in when a night was missed.
    @Test func theServerBacksUpWhenANightWasMissed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(BackupScheduler.isDue(newest: nil, now: now))
        #expect(!BackupScheduler.isDue(newest: now.addingTimeInterval(-3600), now: now))
        #expect(!BackupScheduler.isDue(newest: now.addingTimeInterval(-24.5 * 3600), now: now))
        #expect(BackupScheduler.isDue(newest: now.addingTimeInterval(-25 * 3600), now: now))
    }

    @Test func theServerBacksUpWhenItStartsIfNeeded() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try await withTestApp(adjust: {
            $0.database = .file(dir.appendingPathComponent("timecard.sqlite").path)
            $0.backupDirectory = dir.appendingPathComponent("backups").path
            $0.scheduleBackups = true
        }) { app, _ in
            try await app.asyncBoot()
            var found = false
            for _ in 0..<50 where !found {
                try await Task.sleep(nanoseconds: 100_000_000)
                found = (try? backups(in: dir.appendingPathComponent("backups")).count) == 1
            }
            #expect(found)
        }
    }

    @Test func upkeepDropsOldRetryRecordsAndDeadSessions() async throws {
        try await withTestApp { app, clock in
            let farm = try await FarmFixture.make(app)
            try await farm.push(.shift(farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-60))), as: farm.admin)
            let spare = try await farm.login(farm.admin)
            _ = try await app.client2.send(.POST, APIPath.logout, token: spare)

            clock.advance(91 * 86400)
            let fresh = try await farm.login(farm.admin)
            let shift = farm.shift(for: farm.admin, start: clock.now.addingTimeInterval(-60))
            let res = try await app.client2.send(.POST, APIPath.push(farm: farm.farmId), token: fresh, json: PushRequest(mutations: [Mutation(record: .shift(shift))]))
            #expect(res.status == .ok)
            try await Maintenance.prune(db: app.db, now: clock.now)
            #expect(try await AppliedMutationModel.query(on: app.db).count() == 1)
            #expect(try await SessionModel.query(on: app.db).count() == 1)
            #expect(try await ResetCodeModel.query(on: app.db).count() == 0)
        }
    }
}
