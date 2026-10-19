import Foundation

extension SyncRecord {
    /// The same record written at `updatedAt` (to the millisecond, as the wire carries it).
    ///
    /// A watch tap that waited out of reach is saved with its event times (a shift's start, a
    /// break's start, a mark's `markedAt`) at the moment it was tapped, but stamped with the
    /// time the phone received it, so the sync rule "the newest `updatedAt` wins" isn't fooled
    /// by a backdated tap. A delete keeps its `deletedAt`.
    public func stamped(updatedAt: Date) -> SyncRecord {
        let stamp = updatedAt.roundedToMillisecond
        switch self {
        case .farm(var r): r.updatedAt = stamp; return .farm(r)
        case .member(var r): r.updatedAt = stamp; return .member(r)
        case .season(var r): r.updatedAt = stamp; return .season(r)
        case .field(var r): r.updatedAt = stamp; return .field(r)
        case .block(var r): r.updatedAt = stamp; return .block(r)
        case .shift(var r): r.updatedAt = stamp; return .shift(r)
        case .treeMark(var r): r.updatedAt = stamp; return .treeMark(r)
        case .treeNote(var r): r.updatedAt = stamp; return .treeNote(r)
        }
    }
}
