import Foundation

/// Tree marks by id, split into small buckets. Snapshots are copied freely (the session, the
/// field actions and the map each hold one), so a change copies one bucket rather than every
/// mark of the season; comparing two snapshots skips buckets that share storage.
public struct MarkTable: Equatable, Sendable {
    static let bucketCount = 64
    private var buckets: [[UUID: TreeMark]] = Array(repeating: [:], count: MarkTable.bucketCount)
    public private(set) var count = 0

    public init() {}

    private static func bucket(_ id: UUID) -> Int { Int(id.uuid.15) & (bucketCount - 1) }

    public subscript(id: UUID) -> TreeMark? {
        get { buckets[Self.bucket(id)][id] }
        set {
            let b = Self.bucket(id)
            if let newValue {
                if buckets[b].updateValue(newValue, forKey: id) == nil { count += 1 }
            } else if buckets[b].removeValue(forKey: id) != nil {
                count -= 1
            }
        }
    }

    public var isEmpty: Bool { count == 0 }

    /// Every mark, in no particular order.
    public var values: FlattenSequence<[Dictionary<UUID, TreeMark>.Values]> {
        buckets.map(\.values).joined()
    }

    /// What changed since `old`: marks that are new or different, and marks that are gone.
    /// Buckets that still share storage with `old` are skipped without looking inside.
    public func changes(since old: MarkTable) -> (upserted: [TreeMark], removed: [TreeMark]) {
        var upserted: [TreeMark] = [], removed: [TreeMark] = []
        for i in 0..<Self.bucketCount where buckets[i] != old.buckets[i] {
            for (id, mark) in buckets[i] where old.buckets[i][id] != mark { upserted.append(mark) }
            for (id, mark) in old.buckets[i] where buckets[i][id] == nil { removed.append(mark) }
        }
        return (upserted, removed)
    }
}

/// Everything the app shows for one farm, held in memory and kept in step with the
/// database on every write. Only live records are here: a record with `deletedAt`
/// set drops out. Members stay after removal (their hours still count).
///
/// Lookups are by id. Thousands of marks are fine: applying a change is O(1), and
/// copying a snapshot is cheap until one side changes.
public struct FarmSnapshot: Equatable, Sendable {
    public var farmId: UUID
    public private(set) var farm: Farm?
    public var members: [UUID: Member] = [:]
    public var seasons: [UUID: Season] = [:]
    public var fields: [UUID: Field] = [:]
    public var blocks: [UUID: Block] = [:]
    public var shifts: [UUID: Shift] = [:]
    public private(set) var marks = MarkTable()
    public var notes: [UUID: TreeNote] = [:]

    /// Who holds each tree in the active season, kept up to date mark by mark, so nothing
    /// rebuilds it from thousands of marks on each read.
    public private(set) var seasonIndex = MarkIndex(marks: [])
    /// Which snapshot this is (a new one per `activate` or wipe) and how many changes it has
    /// had: together they say when something derived from it (the field actions' state) is
    /// still current.
    public private(set) var generation = UUID()
    public private(set) var revision = 0

    public init(farmId: UUID) {
        self.farmId = farmId
    }

    /// Upserts a live record or removes a deleted one.
    public mutating func apply(_ record: SyncRecord) {
        revision += 1
        let live = record.deletedAt == nil
        switch record {
        case .farm(let r):
            let season = farm?.activeSeasonId
            farm = r
            if r.activeSeasonId != season { rebuildIndex() }
        case .member(let r): members[r.userId] = r
        case .season(let r): seasons[r.id] = r
        case .field(let r): fields[r.id] = live ? r : nil
        case .block(let r): blocks[r.id] = live ? r : nil
        case .shift(let r): shifts[r.id] = live ? r : nil
        case .treeMark(let r):
            if let previous = marks[r.id], previous.seasonId != r.seasonId || previous.tree != r.tree { unindex(previous) }
            marks[r.id] = live ? r : nil
            if r.seasonId == farm?.activeSeasonId { seasonIndex.apply(r) }
        case .treeNote(let r): notes[r.id] = live ? r : nil
        }
    }

    /// Forgets a record entirely (used when the server says it never existed).
    public mutating func remove(kind: RecordKind, id: UUID) {
        revision += 1
        switch kind {
        case .farm: if farm?.id == id { farm = nil; rebuildIndex() }
        case .member: members[id] = nil
        case .season: seasons[id] = nil
        case .field: fields[id] = nil
        case .block: blocks[id] = nil
        case .shift: shifts[id] = nil
        case .treeMark:
            if let mark = marks[id] { unindex(mark) }
            marks[id] = nil
        case .treeNote: notes[id] = nil
        }
    }

    private mutating func unindex(_ mark: TreeMark) {
        guard mark.seasonId == farm?.activeSeasonId else { return }
        var gone = mark
        gone.deletedAt = gone.deletedAt ?? gone.updatedAt
        seasonIndex.apply(gone)
    }

    private mutating func rebuildIndex() {
        guard let season = farm?.activeSeasonId else {
            seasonIndex = MarkIndex(marks: [])
            return
        }
        seasonIndex = MarkIndex(marks: marks.values.filter { $0.seasonId == season })
    }

    /// The records, not the bookkeeping (index, generation, revision).
    public static func == (a: FarmSnapshot, b: FarmSnapshot) -> Bool {
        a.farmId == b.farmId && a.farm == b.farm && a.members == b.members && a.seasons == b.seasons && a.fields == b.fields
            && a.blocks == b.blocks && a.shifts == b.shifts && a.marks == b.marks && a.notes == b.notes
    }

    public var activeSeason: Season? {
        farm?.activeSeasonId.flatMap { seasons[$0] }
    }

    /// The shift `userId` has on the clock, if any.
    public func openShift(for userId: UUID) -> Shift? {
        shifts.values.first { $0.userId == userId && $0.isOpen }
    }
}
