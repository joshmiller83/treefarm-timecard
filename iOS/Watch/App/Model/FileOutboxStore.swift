import Foundation
import TreeFarmKit

// STUB: slice a replaces
//
// The courier's outbox, saved as JSON in the App Group container after every change.
final class FileOutboxStore: WatchOutboxStore {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func load() -> WatchOutbox? { nil }

    func save(_ outbox: WatchOutbox) {}
}
