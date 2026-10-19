import Foundation

/// Where someone is working: a field, and the row the next-rows list starts from (inclusive).
public struct WorkPosition: Codable, Hashable, Sendable {
    public var fieldId: UUID
    public var next: RowRef?

    public init(fieldId: UUID, next: RowRef? = nil) {
        self.fieldId = fieldId
        self.next = next
    }
}

/// Everything the field actions read, as plain values. The app builds it from its store;
/// tests build it by hand.
public struct FieldState: Sendable {
    public var farm: Farm
    public var me: Member
    /// The farm's active season. Marks outside it are ignored.
    public var season: Season?
    public var fields: [Field]
    public var blocks: [Block]
    /// The signed-in person's shifts.
    public var myShifts: [Shift]
    /// Everyone's marks (only the active season's live marks are used).
    public var marks: [TreeMark]
    public var members: [Member]
    public var position: WorkPosition?
    public var notes: [TreeNote]
    /// Who holds each tree in the active season, when the caller keeps one up to date (the
    /// app's store does). Nil: `index` builds it from `marks` on each read.
    public var seasonIndex: MarkIndex?

    public init(farm: Farm, me: Member, season: Season?, fields: [Field], blocks: [Block], myShifts: [Shift],
                marks: [TreeMark], members: [Member], position: WorkPosition?, notes: [TreeNote] = [], seasonIndex: MarkIndex? = nil) {
        self.farm = farm
        self.me = me
        self.season = season
        self.fields = fields
        self.blocks = blocks
        self.myShifts = myShifts
        self.marks = marks
        self.members = members
        self.position = position
        self.notes = notes
        self.seasonIndex = seasonIndex
    }

    public var calendar: FarmCalendar { FarmCalendar(farm: farm) }
    public var liveShifts: [Shift] { myShifts.filter(\.isLive) }
    public var openShift: Shift? { Clock.openShift(in: liveShifts) }
    public var liveFields: [Field] {
        fields.filter { $0.deletedAt == nil && $0.archivedAt == nil }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    /// Who holds each tree this season.
    public var index: MarkIndex {
        if let seasonIndex { return seasonIndex }
        guard let season else { return MarkIndex(marks: []) }
        return MarkIndex(marks: marks.filter { $0.seasonId == season.id && $0.isLive })
    }

    /// The field being worked: the position's field if it's still there, else the first field.
    public var currentField: Field? {
        let live = liveFields
        if let id = position?.fieldId, let f = live.first(where: { $0.id == id }) { return f }
        return live.first
    }

    public func walker(for field: Field) -> FieldWalker {
        FieldWalker(blocks: blocks.filter { $0.fieldId == field.id && $0.deletedAt == nil })
    }

    public func block(_ id: UUID) -> Block? {
        blocks.first { $0.id == id && $0.deletedAt == nil }
    }

    public func field(_ id: UUID) -> Field? {
        fields.first { $0.id == id && $0.deletedAt == nil }
    }

    public func member(_ userId: UUID) -> Member? {
        members.first { $0.userId == userId }
    }

    public func treeCount(_ shift: Shift, index: MarkIndex? = nil) -> Int {
        (index ?? self.index).count(onShift: shift.id, blocks: blocks)
    }

    /// The next open rows in the current field, starting at the position.
    public func nextRows(_ count: Int, index: MarkIndex? = nil) -> [RowRef] {
        guard let field = currentField else { return [] }
        let walker = walker(for: field)
        return walker.nextRows(from: Self.valid(position?.next, in: walker), count: count, index: index ?? self.index)
    }

    /// A stored position can point at a block that was removed or shrunk since.
    static func valid(_ row: RowRef?, in walker: FieldWalker) -> RowRef? {
        guard let row, let b = walker.block(row.blockId), b.contains(row) else { return nil }
        return row
    }

    /// This state with an action's records and position folded in, the way the store keeps them.
    public func applying(_ outcome: FieldOutcome) -> FieldState {
        var next = applying(outcome.records)
        next.position = outcome.position
        return next
    }

    public func applying(_ records: [SyncRecord]) -> FieldState {
        var s = self
        var markIds = Set<UUID>()
        var newMarks: [TreeMark] = []
        for record in records {
            switch record {
            case .shift(let shift):
                guard shift.userId == me.userId else { continue }
                s.myShifts.removeAll { $0.id == shift.id }
                if shift.isLive { s.myShifts.append(shift) }
            case .treeMark(let mark):
                markIds.insert(mark.id)
                newMarks.removeAll { $0.id == mark.id }
                if mark.isLive { newMarks.append(mark) }
                if mark.seasonId == s.season?.id { s.seasonIndex?.apply(mark) }
            case .treeNote(let note):
                s.notes.removeAll { $0.id == note.id }
                if note.isLive { s.notes.append(note) }
            case .block(let block):
                s.blocks.removeAll { $0.id == block.id }
                if block.deletedAt == nil { s.blocks.append(block) }
            case .field(let field):
                s.fields.removeAll { $0.id == field.id }
                if field.deletedAt == nil { s.fields.append(field) }
            case .member(let member):
                s.members.removeAll { $0.userId == member.userId }
                s.members.append(member)
                if member.userId == me.userId { s.me = member }
            case .farm(let farm):
                if farm.activeSeasonId != s.farm.activeSeasonId { s.seasonIndex = nil }
                s.farm = farm
            case .season(let season):
                if season.id == s.farm.activeSeasonId {
                    if s.season?.id != season.id { s.seasonIndex = nil }
                    s.season = season
                }
            }
        }
        if !markIds.isEmpty {
            s.marks.removeAll { markIds.contains($0.id) }
            s.marks.append(contentsOf: newMarks)
        }
        return s
    }
}
