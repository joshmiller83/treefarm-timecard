import Foundation

extension SyncRecord {
    /// When this version of the record was written.
    public var updatedAt: Date {
        switch self {
        case .farm(let r): r.updatedAt
        case .member(let r): r.updatedAt
        case .season(let r): r.updatedAt
        case .field(let r): r.updatedAt
        case .block(let r): r.updatedAt
        case .shift(let r): r.updatedAt
        case .treeMark(let r): r.updatedAt
        case .treeNote(let r): r.updatedAt
        }
    }

    /// Set when the record is a delete. Farms, members and seasons are never deleted.
    public var deletedAt: Date? {
        switch self {
        case .farm, .member, .season: nil
        case .field(let r): r.deletedAt
        case .block(let r): r.deletedAt
        case .shift(let r): r.deletedAt
        case .treeMark(let r): r.deletedAt
        case .treeNote(let r): r.deletedAt
        }
    }
}

public enum RecordMetadata {
    /// The `updatedAt` for an edit of a record last written at `previous`: now, to the
    /// millisecond, but always after `previous`. A phone whose clock is behind the last writer
    /// would otherwise stamp an older time, and the server keeps the newer copy and refuses
    /// the edit after the person was told it was saved.
    public static func stamp(_ now: Date, after previous: Date) -> Date {
        max(now.roundedToMillisecond, previous.roundedToMillisecond.addingTimeInterval(0.001)).roundedToMillisecond
    }
}

extension Date {
    /// This instant as it comes back from the wire, which carries milliseconds.
    /// Stamp records with it so a saved copy equals the one read back.
    public var roundedToMillisecond: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}
