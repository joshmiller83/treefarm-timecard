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

extension Date {
    /// This instant as it comes back from the wire, which carries milliseconds.
    /// Stamp records with it so a saved copy equals the one read back.
    public var roundedToMillisecond: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}
