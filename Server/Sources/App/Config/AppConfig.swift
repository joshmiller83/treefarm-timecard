import Foundation
import Vapor

/// Everything the server reads from its environment, plus the clock, so tests can
/// run on an in-memory database at a fixed time with cheap password hashing.
public struct AppConfig: Sendable {
    public enum DatabaseLocation: Equatable, Sendable {
        case memory
        case file(String)
    }

    public var host = "127.0.0.1"
    public var port = 8790
    public var database: DatabaseLocation = .file("./data/timecard.sqlite")
    public var backupDirectory = "./data/backups"
    public var bcryptCost = 12
    /// Run a backup at start (when the newest is a day old) and every 24 hours while serving.
    public var scheduleBackups = false
    /// How many backups `backup` keeps.
    public var backupsKept = 30

    /// Sign-in, sign-up and reset requests allowed per client address in `ipWindow`.
    public var ipAttempts = 20
    public var ipWindow: TimeInterval = 15 * 60
    /// Wrong passwords (or reset codes) allowed per email before the account locks for `lockout`.
    public var emailFailures = 5
    public var lockout: TimeInterval = 15 * 60

    public var now: @Sendable () -> Date = { Date() }

    public init() {}

    public static func fromEnvironment(_ env: [String: String]) -> AppConfig {
        var c = AppConfig()
        if let v = env["TIMECARD_HOST"], !v.isEmpty { c.host = v }
        if let v = env["TIMECARD_PORT"].flatMap(Int.init) { c.port = v }
        if let v = env["TIMECARD_DB"], !v.isEmpty { c.database = v == ":memory:" ? .memory : .file(v) }
        if let v = env["TIMECARD_BACKUP_DIR"], !v.isEmpty {
            c.backupDirectory = v
        } else if case .file(let path) = c.database {
            c.backupDirectory = (path as NSString).deletingLastPathComponent + "/backups"
        }
        if let v = env["TIMECARD_BCRYPT_COST"].flatMap(Int.init) { c.bcryptCost = min(max(v, 4), 31) }
        return c
    }

    /// In-memory database, the lowest bcrypt cost and an injectable clock.
    public static func testing(now: @escaping @Sendable () -> Date) -> AppConfig {
        var c = AppConfig()
        c.database = .memory
        c.bcryptCost = 4
        c.backupDirectory = NSTemporaryDirectory()
        c.now = now
        return c
    }
}

extension Application {
    private struct ConfigKey: StorageKey {
        typealias Value = AppConfig
    }

    public var config: AppConfig {
        get { storage[ConfigKey.self] ?? AppConfig() }
        set { storage[ConfigKey.self] = newValue }
    }

    /// The server's idea of now. Tests move it.
    var now: Date { config.now() }
}

extension Request {
    var now: Date { application.now }
}
