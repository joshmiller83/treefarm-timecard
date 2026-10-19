import Foundation
import GRDB

/// Opens the app's SQLite database and keeps its schema.
///
/// The file lives in the App Group container so the widget extension can read it,
/// and it is protected `completeUntilFirstUserAuthentication`: lock-screen buttons
/// and Siri must read and write it while the phone is locked in a pocket.
public enum AppDatabase {
    public static let fileName = "TimeCard.sqlite"

    /// The folder for the database: `<App Group>/Database`, or `Application Support/Database`
    /// when there's no App Group (tests, or a build without the entitlement).
    public static func directory(
        appGroup: String?,
        containerURL: (String) -> URL? = { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    ) -> URL {
        if let appGroup, let group = containerURL(appGroup) {
            return group.appendingPathComponent("Database", isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Database", isDirectory: true)
    }

    /// The database file and the journal files SQLite keeps beside it in WAL mode.
    public static func protectedFiles(for databaseURL: URL) -> [URL] {
        let path = databaseURL.path
        return [databaseURL, URL(fileURLWithPath: path + "-wal"), URL(fileURLWithPath: path + "-shm")]
    }

    /// Opens (creating if needed) the database in `directory`, migrated and protected.
    public static func open(directory: URL) throws -> DatabasePool {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: protectionAttributes)
        let url = directory.appendingPathComponent(fileName)
        let pool = try DatabasePool(path: url.path, configuration: configuration())
        try migrator.migrate(pool)
        // New files inherit the folder's class; set it on each file too in case they predate it.
        applyProtection(to: [directory] + protectedFiles(for: url))
        return pool
    }

    /// Lets go of the database before iOS suspends the app (going to the background, or a
    /// background task running out). Writes until `resume()` fail with SQLITE_ABORT, which
    /// syncing treats as "try again later".
    public static func suspend() {
        NotificationCenter.default.post(name: Database.suspendNotification, object: nil)
    }

    /// The app (or an intent, or a background refresh) is running again.
    public static func resume() {
        NotificationCenter.default.post(name: Database.resumeNotification, object: nil)
    }

    /// True for the errors a suspended database gives: wait and try again.
    public static func isSuspension(_ error: any Error) -> Bool {
        guard let error = error as? DatabaseError else { return false }
        return error.resultCode == .SQLITE_INTERRUPT || error.resultCode == .SQLITE_ABORT
    }

    /// A private in-memory database, for tests and UI-test runs.
    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: configuration())
        try migrator.migrate(queue)
        return queue
    }

    static func configuration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        // Siri and lock-screen intents may write while the app is also syncing.
        config.busyMode = .timeout(5)
        // The file sits in a shared container: iOS kills an app suspended while holding a
        // lock on it (0xdead10cc). The app posts `Database.suspendNotification` when it goes
        // to the background and `resumeNotification` when it (or an intent) runs again.
        config.observesSuspensionNotifications = true
        return config
    }

    private static var protectionAttributes: [FileAttributeKey: Any]? {
        #if os(iOS)
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        nil
        #endif
    }

    private static func applyProtection(to urls: [URL]) {
        #if os(iOS)
        let fm = FileManager.default
        for url in urls where fm.fileExists(atPath: url.path) {
            try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        }
        #endif
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // Every synced record, as the JSON the server sends. Tombstones stay so a
            // delete that hasn't synced yet isn't forgotten.
            try db.execute(sql: """
                CREATE TABLE records (
                    kind TEXT NOT NULL,
                    id TEXT NOT NULL,
                    farmId TEXT NOT NULL,
                    json BLOB NOT NULL,
                    updatedAt INTEGER NOT NULL,
                    deletedAt INTEGER,
                    PRIMARY KEY (farmId, kind, id)
                );
                CREATE INDEX records_live ON records (farmId, deletedAt);

                CREATE TABLE outbox (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    mutationId TEXT NOT NULL UNIQUE,
                    farmId TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    entityId TEXT NOT NULL,
                    json BLOB NOT NULL,
                    createdAt INTEGER NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    lastError TEXT
                );
                CREATE INDEX outbox_entity ON outbox (farmId, kind, entityId);

                CREATE TABLE sync_state (
                    farmId TEXT PRIMARY KEY NOT NULL,
                    cursor INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE kv (
                    key TEXT PRIMARY KEY NOT NULL,
                    value BLOB NOT NULL
                );

                -- Records the server refused without sending its own copy. The next pull
                -- starts over from 0; whatever it doesn't bring back is dropped locally.
                CREATE TABLE refetch (
                    farmId TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    id TEXT NOT NULL,
                    PRIMARY KEY (farmId, kind, id)
                );
                """)
        }
        return migrator
    }
}
