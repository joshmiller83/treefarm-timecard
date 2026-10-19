import Foundation

// What the Apple Watch and the iPhone say to each other over WatchConnectivity.
//
// The phone is the hub: it holds the farm, runs every command through FieldEngine and
// syncs. The watch sends requests (a tap, a question) and keeps the latest WatchState the
// phone sent. When the phone is out of reach, taps wait in the watch's WatchOutbox and are
// applied later at the time they were made.

/// A request from the watch. `issuedAt` is when the person tapped, so a queued tap is
/// applied at that time rather than when it finally reaches the phone.
public struct WatchRequest: Codable, Hashable, Sendable, Identifiable {
    public enum Body: Codable, Hashable, Sendable {
        case command(FieldCommand)
        case question(FieldQuestion)
        /// "Send me the current state" (the watch app opened, or the phone came back in reach).
        case refresh
    }

    public var id: UUID
    public var body: Body
    public var issuedAt: Date

    public init(id: UUID = UUID(), body: Body, issuedAt: Date) {
        self.id = id
        self.body = body
        self.issuedAt = issuedAt
    }

    public var isCommand: Bool {
        if case .command = body { return true }
        return false
    }
}

/// The phone's answer to one request: the same sentence Siri would say.
public struct WatchReply: Codable, Hashable, Sendable {
    public var requestId: UUID
    public var speech: String
    public var succeeded: Bool
    public var lastAction: String?

    public init(requestId: UUID, speech: String, succeeded: Bool, lastAction: String? = nil) {
        self.requestId = requestId
        self.speech = speech
        self.succeeded = succeeded
        self.lastAction = lastAction
    }
}

/// Everything the watch shows, sent by the phone after every change (as the
/// WatchConnectivity application context, so the watch always has the latest).
public struct WatchState: Codable, Hashable, Sendable {
    public var signedIn: Bool
    public var farmName: String
    public var fieldName: String
    /// The shift on the clock; nil when off the clock.
    public var snapshot: LiveSnapshot?
    /// Where you'd start: the next open rows, also when off the clock.
    public var nextRows: [RowChip]
    public var todayWorked: TimeInterval
    public var todayTrees: Int
    public var canUndo: Bool
    /// Whether clocking in also starts a workout on the watch.
    public var recordWorkouts: Bool
    public var updatedAt: Date

    public init(signedIn: Bool, farmName: String, fieldName: String, snapshot: LiveSnapshot?, nextRows: [RowChip],
                todayWorked: TimeInterval, todayTrees: Int, canUndo: Bool, recordWorkouts: Bool, updatedAt: Date) {
        self.signedIn = signedIn
        self.farmName = farmName
        self.fieldName = fieldName
        self.snapshot = snapshot
        self.nextRows = nextRows
        self.todayWorked = todayWorked
        self.todayTrees = todayTrees
        self.canUndo = canUndo
        self.recordWorkouts = recordWorkouts
        self.updatedAt = updatedAt
    }

    public var isClockedIn: Bool { snapshot != nil }
}

/// WatchConnectivity carries property-list dictionaries; each message is one JSON blob under a key.
public protocol WatchPayload: Codable {
    static var payloadKey: String { get }
}

extension WatchPayload {
    public func encoded() throws -> [String: Any] {
        [Self.payloadKey: try JSONCoding.encoder().encode(self)]
    }

    public static func decode(_ dictionary: [String: Any]) throws -> Self {
        guard let data = dictionary[payloadKey] as? Data else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "No \(payloadKey) in the message"))
        }
        return try JSONCoding.decoder().decode(Self.self, from: data)
    }
}

extension WatchRequest: WatchPayload { public static let payloadKey = "tc.request" }
extension WatchReply: WatchPayload { public static let payloadKey = "tc.reply" }
extension WatchState: WatchPayload { public static let payloadKey = "tc.state" }

/// Taps made while the phone is out of reach, oldest first. Only commands wait; questions and
/// refreshes only make sense right away. Past `limit` the oldest taps are dropped and counted.
public struct WatchOutbox: Codable, Hashable, Sendable {
    public private(set) var pending: [WatchRequest] = []
    public private(set) var dropped = 0
    public let limit: Int

    public init(limit: Int = 200) {
        self.limit = max(1, limit)
    }

    public var next: WatchRequest? { pending.first }
    public var count: Int { pending.count }
    public var isEmpty: Bool { pending.isEmpty }

    public mutating func add(_ request: WatchRequest) {
        guard request.isCommand, !pending.contains(where: { $0.id == request.id }) else { return }
        pending.append(request)
        if pending.count > limit {
            let extra = pending.count - limit
            pending.removeFirst(extra)
            dropped += extra
        }
    }

    /// The phone has the request (whatever it answered), so it never goes again.
    public mutating func delivered(_ id: UUID) {
        pending.removeAll { $0.id == id }
    }
}

public enum WatchTiming {
    /// The time a watch tap counts at: when it was made, but never later than when the phone got it
    /// (a watch clock running ahead can't put a tap in the future).
    public static func effectiveTime(issuedAt: Date, receivedAt: Date) -> Date {
        min(issuedAt, receivedAt)
    }
}
