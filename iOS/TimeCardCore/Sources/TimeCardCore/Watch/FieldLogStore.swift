import Foundation

/// The field logs the watch sends after each logged workout (docs/gis.md 10), kept on this
/// phone until the person shares them to their Mac. They never sync and never reach the farm.
/// Older than `keepDays`, they're deleted.
public struct FieldLogStore: Sendable {
    public static let keepDays = 30

    public let directory: URL

    public init(directory: URL = FieldLogStore.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "FieldLogs")
    }

    /// Takes a file the watch sent: moves it in under its own name (replacing a resent copy).
    /// Anything that isn't a field log is deleted. Returns where it now lives.
    @discardableResult
    public func accept(_ file: URL, metadata: [String: String]) -> URL? {
        let fm = FileManager.default
        guard metadata[FieldLog.metadataKey] == FieldLog.metadataValue, file.pathExtension == FieldLog.fileExtension else {
            try? fm.removeItem(at: file)
            return nil
        }
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appending(path: file.lastPathComponent)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.moveItem(at: file, to: target)
            return target
        } catch {
            try? fm.removeItem(at: file)
            return nil
        }
    }

    /// The logs kept, newest first (the names start with their UTC start time).
    public func logs() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return names.filter { $0.pathExtension == FieldLog.fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Deletes logs that arrived more than `keepDays` ago.
    public func prune(now: Date = Date()) {
        let fm = FileManager.default
        let limit = now.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        for log in logs() {
            let created = (try? fm.attributesOfItem(atPath: log.path)[.creationDate] as? Date) ?? now
            if created < limit { try? fm.removeItem(at: log) }
        }
    }

    public func deleteAll() {
        for log in logs() { try? FileManager.default.removeItem(at: log) }
    }
}
