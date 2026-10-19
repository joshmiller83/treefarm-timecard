import Foundation

/// Everything the app shows for one farm, held in memory and kept in step with the
/// database on every write. Only live records are here: a record with `deletedAt`
/// set drops out. Members stay after removal (their hours still count).
///
/// Lookups are by id. Thousands of marks are fine: applying a change is O(1), and
/// copying a snapshot is cheap until one side changes.
public struct FarmSnapshot: Equatable, Sendable {
    public var farmId: UUID
    public var farm: Farm?
    public var members: [UUID: Member] = [:]
    public var seasons: [UUID: Season] = [:]
    public var fields: [UUID: Field] = [:]
    public var blocks: [UUID: Block] = [:]
    public var shifts: [UUID: Shift] = [:]
    public var marks: [UUID: TreeMark] = [:]
    public var notes: [UUID: TreeNote] = [:]

    public init(farmId: UUID) {
        self.farmId = farmId
    }

    /// Upserts a live record or removes a deleted one.
    public mutating func apply(_ record: SyncRecord) {
        let live = record.deletedAt == nil
        switch record {
        case .farm(let r): farm = r
        case .member(let r): members[r.userId] = r
        case .season(let r): seasons[r.id] = r
        case .field(let r): fields[r.id] = live ? r : nil
        case .block(let r): blocks[r.id] = live ? r : nil
        case .shift(let r): shifts[r.id] = live ? r : nil
        case .treeMark(let r): marks[r.id] = live ? r : nil
        case .treeNote(let r): notes[r.id] = live ? r : nil
        }
    }

    /// Forgets a record entirely (used when the server says it never existed).
    public mutating func remove(kind: RecordKind, id: UUID) {
        switch kind {
        case .farm: if farm?.id == id { farm = nil }
        case .member: members[id] = nil
        case .season: seasons[id] = nil
        case .field: fields[id] = nil
        case .block: blocks[id] = nil
        case .shift: shifts[id] = nil
        case .treeMark: marks[id] = nil
        case .treeNote: notes[id] = nil
        }
    }

    public var activeSeason: Season? {
        farm?.activeSeasonId.flatMap { seasons[$0] }
    }

    /// The shift `userId` has on the clock, if any.
    public func openShift(for userId: UUID) -> Shift? {
        shifts.values.first { $0.userId == userId && $0.isOpen }
    }
}
