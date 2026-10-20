import Foundation
import TreeFarmKit

/// A tap the phone refused after it waited on the watch. The Queue sheet lists it for an hour
/// with the phone's sentence, so the person sees what didn't apply (docs/watch.md 3.7).
struct RefusedTap: Codable, Equatable, Identifiable, Sendable {
    static let keptFor: TimeInterval = 3600

    var request: WatchRequest
    var speech: String
    var at: Date

    var id: UUID { request.id }
}

/// What the model keeps between launches, beside the outbox: the phone's last state (so a
/// relaunch out of reach still shows the shift), refused taps, refused watch clock-ins (for
/// the workout), the Undo clock-in window and the summary already seen.
struct WatchModelMemory: Codable, Equatable, Sendable {
    static let fileName = "watch-model.json"

    var confirmed: WatchState?
    var refused: [RefusedTap] = []
    var refusedClockIns: [UUID] = []
    /// The shift the watch minted at its last clock-in, and until when Undo clock-in shows.
    var watchClockIn: UUID?
    var undoClockInUntil: Date?
    var dismissedSummaryId: UUID?

    static func read(from directory: URL?) -> WatchModelMemory {
        guard let directory, let data = try? Data(contentsOf: directory.appending(path: fileName)),
              let memory = try? JSONCoding.decoder().decode(WatchModelMemory.self, from: data) else { return WatchModelMemory() }
        return memory
    }

    func write(to directory: URL?) {
        guard let directory, let data = try? JSONCoding.encoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appending(path: Self.fileName), options: [.atomic])
    }
}
