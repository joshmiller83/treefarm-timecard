import Fluent
import Foundation
import SQLKit
import Vapor

/// `VACUUM INTO` copies of the database, named `timecard-YYYYMMDD-HHMMSS.sqlite`
/// in the server's local time, keeping the newest `backupsKept`.
enum Backups {
    static let pattern = #"^timecard-\d{8}-\d{6}(-\d+)?\.sqlite$"#

    @discardableResult
    static func run(app: Application) async throws -> URL {
        let dir = URL(fileURLWithPath: app.config.backupDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Self.stamp(app.now)
        var url = dir.appendingPathComponent("timecard-\(stamp).sqlite")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("timecard-\(stamp)-\(n).sqlite")
            n += 1
        }
        guard let sql = app.db as? any SQLDatabase else { throw CommandFailure("The database can’t be backed up.") }
        try await sql.raw("VACUUM INTO \(bind: url.path)").run()
        try prune(dir, keep: app.config.backupsKept)
        return url
    }

    /// Deletes all but the newest `keep` backups. Other files are left alone.
    static func prune(_ dir: URL, keep: Int) throws {
        let names = try backupNames(in: dir)
        for name in names.dropLast(max(keep, 1)) {
            try FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Backup file names, oldest first (the names sort by time).
    static func backupNames(in dir: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.range(of: pattern, options: .regularExpression) != nil }
            .sorted()
    }

    /// When the newest backup was written.
    static func newest(in dir: URL) -> Date? {
        (try? backupNames(in: dir))?.last.flatMap { name in
            (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.modificationDate] as? Date
        }
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}

/// Clears out rows nothing needs anymore: retry answers older than 90 days,
/// sessions that ended, and reset codes that were used or ran out.
enum Maintenance {
    static let keepRetries: TimeInterval = 90 * 86400

    static func prune(db: any Database, now: Date) async throws {
        try await AppliedMutationModel.query(on: db).filter(\.$createdAt < now.addingTimeInterval(-keepRetries)).delete()
        try await SessionModel.query(on: db).group(.or) { $0.filter(\.$revokedAt != nil).filter(\.$expiresAt <= now) }.delete()
        try await ResetCodeModel.query(on: db).group(.or) { $0.filter(\.$usedAt != nil).filter(\.$expiresAt <= now) }.delete()
    }
}

/// While serving: checks every hour and backs up (then tidies) when the newest
/// backup is a day old, so a backup happens at start-up if one is due and about
/// every 24 hours after.
final class BackupScheduler: LifecycleHandler, @unchecked Sendable {
    static let interval: TimeInterval = 24 * 3600
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    static func isDue(newest: Date?, now: Date) -> Bool {
        guard let newest else { return true }
        return now.timeIntervalSince(newest) >= interval - 60
    }

    func didBootAsync(_ app: Application) async throws {
        let dir = URL(fileURLWithPath: app.config.backupDirectory, isDirectory: true)
        let job = Task { [weak app] in
            while !Task.isCancelled {
                guard let app else { return }
                if Self.isDue(newest: Backups.newest(in: dir), now: Date()) {
                    do {
                        let url = try await Backups.run(app: app)
                        try await Maintenance.prune(db: app.db, now: app.now)
                        app.logger.info("Backed up to \(url.path)")
                    } catch {
                        app.logger.error("Backup failed: \(String(reflecting: error))")
                    }
                }
                try? await Task.sleep(nanoseconds: 3600 * 1_000_000_000)
            }
        }
        lock.withLock { task = job }
    }

    func shutdownAsync(_ app: Application) async {
        let job = lock.withLock { task }
        job?.cancel()
        await job?.value
    }
}
