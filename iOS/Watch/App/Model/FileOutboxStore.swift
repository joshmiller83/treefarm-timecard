import Foundation
import TreeFarmKit

/// The courier's outbox, saved as JSON in the App Group container after every change, so taps
/// made out of reach survive the app being closed or the watch restarting.
final class FileOutboxStore: WatchOutboxStore {
    static let fileName = "watch-outbox.json"

    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// The file beside the complications' state file.
    convenience init(directory: URL = WatchStateFile.directory) {
        self.init(url: directory.appending(path: Self.fileName))
    }

    func load() -> WatchOutbox? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder().decode(WatchOutbox.self, from: data)
    }

    func save(_ outbox: WatchOutbox) {
        guard let data = try? JSONCoding.encoder().encode(outbox) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }
}
