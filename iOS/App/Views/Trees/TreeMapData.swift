import CoreGraphics
import Foundation
import TimeCardCore

/// What a tap on a tree does on the map.
enum MapMode: String, CaseIterable, Identifiable, Sendable {
    case one, fill, erase, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: "One"
        case .fill: "Fill"
        case .erase: "Erase"
        case .notes: "Notes"
        }
    }

    /// What VoiceOver says for the segment.
    var spokenTitle: String {
        switch self {
        case .one: "One tree"
        case .fill: "Fill between"
        case .erase: "Erase"
        case .notes: "Tree notes"
        }
    }

    var systemImage: String {
        switch self {
        case .one: "hand.tap"
        case .fill: "arrow.down.right.and.arrow.up.left"
        case .erase: "eraser"
        case .notes: "note.text"
        }
    }

    /// The `MarkOps` mode for taps. Notes mode never marks a tree, but a row tap reads as "one".
    var tapMode: TapMode {
        switch self {
        case .one, .notes: .one
        case .fill: .fill
        case .erase: .erase
        }
    }

    /// The line under the modes before anything has been tapped.
    var hint: String {
        switch self {
        case .one: "Tap a tree to mark it shaped, or a row number to mark the whole row. Tap again to unmark."
        case .fill: "Tap the first tree, then the last. Every tree between them, row by row, gets marked."
        case .erase: "Tap a tree to unmark it. Tap a row number to clear that row."
        case .notes: "Tap a tree to see who shaped it and read or add notes."
        }
    }
}

/// The map sizes: the whole field at a glance, then four tree sizes (the artifact's zooms).
enum MapZoom: String, CaseIterable, Identifiable, Sendable {
    case all, xs, s, m, l

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .xs: "XS"
        case .s: "S"
        case .m: "M"
        case .l: "L"
        }
    }

    var spokenTitle: String {
        switch self {
        case .all: "Whole field"
        case .xs: "Extra small"
        case .s: "Small"
        case .m: "Medium"
        case .l: "Large"
        }
    }

    /// The four tree sizes, smallest first.
    static let presets: [MapZoom] = [.xs, .s, .m, .l]

    func metrics(blocks: [Block], width: CGFloat) -> MapMetrics {
        switch self {
        case .all: MapMetrics.overview(blocks: blocks, width: width)
        case .xs: .xs
        case .s: .s
        case .m: .m
        case .l: .l
        }
    }

    /// After a pinch: the zoom whose trees are closest to `cellWidth` wide (compared on a log
    /// scale, so halving and doubling count the same). `overviewWidth` is the whole field's tree size.
    static func nearest(cellWidth: CGFloat, overviewWidth: CGFloat) -> MapZoom {
        let target = log(max(0.5, cellWidth))
        var options: [(MapZoom, CGFloat)] = presets.map { ($0, $0.metrics(blocks: [], width: 0).cell.width) }
        // The overview only counts when it really is smaller than the smallest tree size.
        if overviewWidth < MapMetrics.xs.cell.width * 0.8 { options.insert((.all, overviewWidth), at: 0) }
        return options.min { abs(log(max(0.5, $0.1)) - target) < abs(log(max(0.5, $1.1)) - target) }?.0 ?? .m
    }
}

/// The farm as the map needs it, built from the session's snapshot. The mark index covers the
/// active season only; notes are grouped by tree (they follow the tree, not the season).
struct TreeMapData {
    var farm: Farm
    var me: Member
    var season: Season?
    /// Live, not archived, in display order.
    var fields: [Field]
    /// Every live block on the farm.
    var blocks: [Block]
    /// The snapshot's live marks (every season), kept to spot what changed.
    var allMarks: [UUID: TreeMark]
    var index: MarkIndex
    var notes: [UUID: TreeNote]
    var notesByTree: [TreeRef: [TreeNote]]
    /// My live shifts, newest first.
    var myShifts: [Shift]
    var members: [UUID: Member]

    var calendar: FarmCalendar { FarmCalendar(farm: farm) }
    var isAdmin: Bool { me.role == .admin }
    /// My shift on the clock (the latest open one, should there ever be two).
    var openShift: Shift? { myShifts.first(where: \.isOpen) }

    init(snapshot: FarmSnapshot, farm: Farm, me: Member) {
        self.init(header: snapshot, farm: farm, me: me)
        allMarks = snapshot.marks
        index = Self.index(snapshot.marks, season: season?.id)
        notes = snapshot.notes
        notesByTree = Self.group(snapshot.notes)
    }

    func block(_ id: UUID) -> Block? {
        blocks.first { $0.id == id }
    }

    func blocks(in fieldId: UUID?) -> [Block] {
        guard let fieldId else { return [] }
        return blocks.filter { $0.fieldId == fieldId }
    }

    func shift(_ id: UUID) -> Shift? {
        myShifts.first { $0.id == id }
    }

    func name(of userId: UUID) -> String {
        userId == me.userId ? "you" : (members[userId]?.displayName ?? "someone else")
    }

    /// Trees this shift holds on the farm's current blocks.
    func treeCount(_ shift: Shift) -> Int {
        index.count(onShift: shift.id, blocks: blocks)
    }

    // MARK: Keeping up with the snapshot

    /// Folds a newer snapshot in. Returns the rows whose drawing changed, or nil when
    /// everything should be redrawn (a new season, a new person, lots of changes).
    @discardableResult
    mutating func update(snapshot: FarmSnapshot, farm: Farm, me: Member) -> Set<RowRef>? {
        let next = TreeMapData(header: snapshot, farm: farm, me: me)
        var dirty: Set<RowRef>? = []
        if next.season?.id != season?.id || next.me.userId != self.me.userId {
            index = Self.index(snapshot.marks, season: next.season?.id)
            dirty = nil
        } else if let change = Self.diff(allMarks, snapshot.marks, season: next.season?.id) {
            if change.removed.isEmpty && change.added.isEmpty {
                // Equal values in different storage: nothing to redraw.
            } else if change.added.count + change.removed.count > 600 {
                index = Self.index(snapshot.marks, season: next.season?.id)
                dirty = nil
            } else {
                index = index.applying(MarkChange(removed: change.removed))
                index = index.applying(MarkChange(added: change.added))
                dirty?.formUnion(change.rows)
            }
        }
        if notes != snapshot.notes {
            let rows = Self.changedNoteRows(notes, snapshot.notes)
            dirty?.formUnion(rows)
            notesByTree = Self.group(snapshot.notes)
        }
        allMarks = snapshot.marks
        notes = snapshot.notes
        self.farm = next.farm
        self.me = next.me
        season = next.season
        fields = next.fields
        blocks = next.blocks
        myShifts = next.myShifts
        members = next.members
        return dirty
    }

    /// Applies records saved on this phone right away, before the snapshot catches up.
    /// Returns the rows to redraw.
    mutating func apply(_ records: [SyncRecord]) -> Set<RowRef> {
        var rows = Set<RowRef>()
        var removed: [TreeMark] = []
        var added: [TreeMark] = []
        var notesChanged = false
        for record in records {
            switch record {
            case .treeMark(let mark):
                rows.insert(mark.tree.rowRef)
                if let old = allMarks[mark.id] { removed.append(old) }
                if mark.isLive {
                    allMarks[mark.id] = mark
                    if mark.seasonId == season?.id { added.append(mark) }
                } else {
                    allMarks[mark.id] = nil
                    removed.append(mark)
                }
            case .treeNote(let note):
                rows.insert(note.tree.rowRef)
                notes[note.id] = note.isLive ? note : nil
                notesChanged = true
            default:
                continue
            }
        }
        if !removed.isEmpty { index = index.applying(MarkChange(removed: removed)) }
        if !added.isEmpty { index = index.applying(MarkChange(added: added)) }
        if notesChanged { notesByTree = Self.group(notes) }
        return rows
    }

    // MARK: Building

    /// Everything but the marks and notes, which `update` handles with care.
    private init(header snapshot: FarmSnapshot, farm: Farm, me: Member) {
        let farm = snapshot.farm ?? farm
        self.farm = farm
        self.me = snapshot.members[me.userId] ?? me
        season = farm.activeSeasonId.flatMap { snapshot.seasons[$0] }
        fields = Self.liveFields(snapshot)
        blocks = snapshot.blocks.values.filter { $0.deletedAt == nil }.sorted { $0.id.uuidString < $1.id.uuidString }
        allMarks = [:]
        index = MarkIndex(marks: [])
        notes = [:]
        notesByTree = [:]
        myShifts = Self.shifts(snapshot, of: me.userId)
        members = snapshot.members
    }

    private static func liveFields(_ snapshot: FarmSnapshot) -> [Field] {
        snapshot.fields.values
            .filter { $0.deletedAt == nil && $0.archivedAt == nil }
            .sorted { ($0.sortOrder, $0.name, $0.id.uuidString) < ($1.sortOrder, $1.name, $1.id.uuidString) }
    }

    private static func shifts(_ snapshot: FarmSnapshot, of userId: UUID) -> [Shift] {
        snapshot.shifts.values.filter { $0.userId == userId && $0.isLive }.sorted { $0.start > $1.start }
    }

    private static func index(_ marks: [UUID: TreeMark], season: UUID?) -> MarkIndex {
        guard let season else { return MarkIndex(marks: []) }
        return MarkIndex(marks: marks.values.filter { $0.seasonId == season && $0.isLive })
    }

    static func group(_ notes: [UUID: TreeNote]) -> [TreeRef: [TreeNote]] {
        var byTree: [TreeRef: [TreeNote]] = [:]
        for note in notes.values where note.isLive {
            byTree[note.tree, default: []].append(note)
        }
        for key in byTree.keys {
            byTree[key]?.sort { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
        }
        return byTree
    }

    /// What changed between two sets of live marks: the old copies to take out of the index,
    /// the new season marks to put in, and every row touched. Nil when nothing changed.
    static func diff(_ old: [UUID: TreeMark], _ new: [UUID: TreeMark], season: UUID?) -> (removed: [TreeMark], added: [TreeMark], rows: Set<RowRef>)? {
        if old == new { return nil }
        var removed: [TreeMark] = []
        var added: [TreeMark] = []
        var rows = Set<RowRef>()
        for (id, mark) in new {
            let before = old[id]
            guard before != mark else { continue }
            if let before {
                removed.append(before)
                rows.insert(before.tree.rowRef)
            }
            if mark.seasonId == season { added.append(mark) }
            rows.insert(mark.tree.rowRef)
        }
        for (id, mark) in old where new[id] == nil {
            removed.append(mark)
            rows.insert(mark.tree.rowRef)
        }
        return (removed, added, rows)
    }

    private static func changedNoteRows(_ old: [UUID: TreeNote], _ new: [UUID: TreeNote]) -> Set<RowRef> {
        var rows = Set<RowRef>()
        for (id, note) in new where old[id] != note {
            rows.insert(note.tree.rowRef)
            if let before = old[id] { rows.insert(before.tree.rowRef) }
        }
        for (id, note) in old where new[id] == nil { rows.insert(note.tree.rowRef) }
        return rows
    }
}
