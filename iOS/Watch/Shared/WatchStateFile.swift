import Foundation
import TreeFarmKit

/// What the watch app shares with its complications: the **displayed** `WatchState` (with
/// waiting taps applied) and the waiting count, as one JSON file in the App Group container.
/// The widget extension never touches WCSession; it reads only this.
///
/// The app writes it after every change it handled, then reloads the complications when
/// `ComplicationReload.needsReload(old:new:)` says something shown changed.
enum WatchStateFile {
    struct Contents: Codable, Equatable, Sendable {
        var displayed: WatchState?
        /// Taps waiting for the phone (not in flight).
        var waitingCount: Int
        /// A watch clock-out waits for the phone ("Clock-out waiting for iPhone").
        var clockOutWaiting: Bool

        init(displayed: WatchState?, waitingCount: Int = 0, clockOutWaiting: Bool = false) {
            self.displayed = displayed
            self.waitingCount = waitingCount
            self.clockOutWaiting = clockOutWaiting
        }

        static let empty = Contents(displayed: nil)

        private enum CodingKeys: String, CodingKey { case displayed, waitingCount, clockOutWaiting }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            displayed = try c.decodeIfPresent(WatchState.self, forKey: .displayed)
            waitingCount = try c.decodeIfPresent(Int.self, forKey: .waitingCount) ?? 0
            clockOutWaiting = try c.decodeIfPresent(Bool.self, forKey: .clockOutWaiting) ?? false
        }
    }

    static let fileName = "watch-state.json"

    /// The App Group container named by the target's `TimeCardAppGroup` Info.plist key, shared
    /// by the watch app and its widget extension. Without one (an unsigned build), the app's
    /// own Application Support folder.
    static var directory: URL {
        if let group = Bundle.main.object(forInfoDictionaryKey: "TimeCardAppGroup") as? String,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return url
        }
        return URL.applicationSupportDirectory
    }

    /// What was last written, or `.empty` (nothing yet, or unreadable).
    static func read(from directory: URL = directory) -> Contents {
        guard let data = try? Data(contentsOf: directory.appending(path: fileName)),
              let contents = try? JSONCoding.decoder().decode(Contents.self, from: data) else { return .empty }
        return contents
    }

    static func write(_ contents: Contents, to directory: URL = directory) {
        guard let data = try? JSONCoding.encoder().encode(contents) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: fileName), options: [.atomic])
    }
}
