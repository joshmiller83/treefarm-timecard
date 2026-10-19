import Foundation

// The sync protocol is upsert-only. A device pushes whole records (deletes are
// records with `deletedAt` set) and pulls everything that changed after the
// last server sequence number it saw.

public enum RecordKind: String, Codable, Sendable, CaseIterable {
    case farm, member, season, field, block, shift, treeMark, treeNote
}

/// A record's identity: its kind and the id of the thing it describes.
public struct RecordKey: Hashable, Codable, Sendable {
    public var kind: RecordKind
    public var id: UUID

    public init(_ kind: RecordKind, _ id: UUID) {
        self.kind = kind
        self.id = id
    }
}

public enum SyncRecord: Hashable, Sendable {
    case farm(Farm)
    case member(Member)
    case season(Season)
    case field(Field)
    case block(Block)
    case shift(Shift)
    case treeMark(TreeMark)
    case treeNote(TreeNote)

    public var kind: RecordKind {
        switch self {
        case .farm: .farm
        case .member: .member
        case .season: .season
        case .field: .field
        case .block: .block
        case .shift: .shift
        case .treeMark: .treeMark
        case .treeNote: .treeNote
        }
    }

    public var key: RecordKey { RecordKey(kind, entityId) }

    /// The id of the thing this record describes (a member is keyed by its user).
    public var entityId: UUID {
        switch self {
        case .farm(let r): r.id
        case .member(let r): r.userId
        case .season(let r): r.id
        case .field(let r): r.id
        case .block(let r): r.id
        case .shift(let r): r.id
        case .treeMark(let r): r.id
        case .treeNote(let r): r.id
        }
    }
}

extension SyncRecord: Codable {
    private enum CodingKeys: String, CodingKey { case kind, data }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(RecordKind.self, forKey: .kind) {
        case .farm: self = .farm(try c.decode(Farm.self, forKey: .data))
        case .member: self = .member(try c.decode(Member.self, forKey: .data))
        case .season: self = .season(try c.decode(Season.self, forKey: .data))
        case .field: self = .field(try c.decode(Field.self, forKey: .data))
        case .block: self = .block(try c.decode(Block.self, forKey: .data))
        case .shift: self = .shift(try c.decode(Shift.self, forKey: .data))
        case .treeMark: self = .treeMark(try c.decode(TreeMark.self, forKey: .data))
        case .treeNote: self = .treeNote(try c.decode(TreeNote.self, forKey: .data))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .farm(let r): try c.encode(r, forKey: .data)
        case .member(let r): try c.encode(r, forKey: .data)
        case .season(let r): try c.encode(r, forKey: .data)
        case .field(let r): try c.encode(r, forKey: .data)
        case .block(let r): try c.encode(r, forKey: .data)
        case .shift(let r): try c.encode(r, forKey: .data)
        case .treeMark(let r): try c.encode(r, forKey: .data)
        case .treeNote(let r): try c.encode(r, forKey: .data)
        }
    }
}

/// One change a device wants the server to keep. `id` makes retries safe:
/// the server applies a mutation id once and answers repeats with the first result.
public struct Mutation: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var record: SyncRecord

    public init(id: UUID = UUID(), record: SyncRecord) {
        self.id = id
        self.record = record
    }
}

public struct PushRequest: Codable, Hashable, Sendable {
    public var mutations: [Mutation]

    public init(mutations: [Mutation]) {
        self.mutations = mutations
    }
}

public enum RejectReason: String, Codable, Sendable {
    /// The caller may not change this record.
    case forbidden
    /// The record breaks a rule (bad times, sizes out of range, ...). `message` says which.
    case invalid
    /// Someone else already shaped this tree this season.
    case treeTaken
    /// The user already has a shift on the clock.
    case openShiftExists
    /// The block still has marks or notes that a resize, move or delete would strand.
    case blockInUse
    /// The record points at something that doesn't exist.
    case notFound
}

public struct MutationResult: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable { case applied, rejected }

    public var mutationId: UUID
    public var status: Status
    /// The server sequence number the record was stored at, when applied.
    public var seq: Int64?
    public var reason: RejectReason?
    /// A sentence the app can show or speak as-is.
    public var message: String?
    /// The server's copy, when a rejection means the device should replace its own.
    public var current: SyncRecord?

    public init(mutationId: UUID, status: Status, seq: Int64? = nil, reason: RejectReason? = nil, message: String? = nil, current: SyncRecord? = nil) {
        self.mutationId = mutationId
        self.status = status
        self.seq = seq
        self.reason = reason
        self.message = message
        self.current = current
    }

    public static func applied(_ id: UUID, seq: Int64) -> MutationResult {
        MutationResult(mutationId: id, status: .applied, seq: seq)
    }

    public static func rejected(_ id: UUID, _ reason: RejectReason, _ message: String, current: SyncRecord? = nil) -> MutationResult {
        MutationResult(mutationId: id, status: .rejected, reason: reason, message: message, current: current)
    }
}

public struct PushResponse: Codable, Hashable, Sendable {
    public var results: [MutationResult]

    public init(results: [MutationResult]) {
        self.results = results
    }
}

public struct Change: Codable, Hashable, Sendable {
    public var seq: Int64
    public var record: SyncRecord

    public init(seq: Int64, record: SyncRecord) {
        self.seq = seq
        self.record = record
    }
}

public struct PullResponse: Codable, Hashable, Sendable {
    public var changes: [Change]
    /// Pass this back as `since` on the next pull.
    public var cursor: Int64
    public var hasMore: Bool

    public init(changes: [Change], cursor: Int64, hasMore: Bool) {
        self.changes = changes
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

/// The JSON settings both ends use. Dates travel as milliseconds since 1970.
public enum JSONCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
