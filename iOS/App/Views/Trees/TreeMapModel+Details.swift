import Foundation
import TimeCardCore

/// What the tree card shows.
struct TreeCardInfo: Equatable {
    enum State: Equatable {
        case notShaped, thisShift, earlier
    }

    struct Note: Identifiable, Equatable {
        var id: UUID
        var author: String
        /// "Oct 19, 9:14 AM", plus "· edited" after a change.
        var when: String
        var flag: NoteFlag
        var body: String
        var canEdit: Bool
    }

    var tree: TreeRef
    /// "Block 1, row 3, tree 6"
    var title: String
    var state: State
    /// "Shaped by Sam Ortiz on Tue, Sep 22 at 9:14 AM."
    var status: String
    var notes: [Note]
    /// Whether the marking shift can take or give up this tree.
    var canToggle: Bool
}

/// The field card: how much is shaped and how long the rest might take.
struct FieldProgress: Equatable {
    var shaped: Int
    var total: Int
    /// 0...100, rounded down so 99.6 % never reads as done.
    var percent: Int
    /// "48 of 960 trees shaped."
    var summary: String
    /// "At 26.7 trees an hour, the rest takes about 34 hours." Nil without a pace or when done.
    var timeLeft: String?

    var fraction: Double { total > 0 ? Double(shaped) / Double(total) : 0 }
}

/// One row for the VoiceOver list.
struct RowSummary: Identifiable, Equatable {
    var row: RowRef
    /// "Row 5"
    var title: String
    /// "12 of 12 shaped, 12 on this shift, 1 note"
    var value: String
    var shaped: Int
    var mine: Int
    var total: Int
    var notes: Int

    var id: RowRef { row }
}

extension TreeMapModel {
    // MARK: Tree card

    func treeInfo(_ tree: TreeRef) -> TreeCardInfo? {
        guard let data, let block = data.block(tree.blockId), block.contains(tree) else { return nil }
        let cal = data.calendar
        let held = data.index.mark(at: tree)
        let marking = markingShift
        let state: TreeCardInfo.State
        let status: String
        if let held {
            let when = "\(Fmt.day(held.markedAt, cal)) at \(Fmt.time(held.markedAt, cal))"
            if held.shiftId == marking?.id {
                state = .thisShift
                status = cal.isSameDay(held.markedAt, currentTime())
                    ? "Shaped on this shift at \(Fmt.time(held.markedAt, cal))."
                    : "Shaped on this shift on \(when)."
            } else {
                state = .earlier
                status = held.userId == data.me.userId ? "Shaped by you on \(when)." : "Shaped by \(data.name(of: held.userId)) on \(when)."
            }
        } else {
            state = .notShaped
            status = data.season == nil ? Speech.noSeason : "Not shaped yet this season."
        }
        let notes = (data.notesByTree[tree] ?? []).map { note in
            var when = "\(Fmt.monthDay(note.createdAt, cal)), \(Fmt.time(note.createdAt, cal))"
            if note.updatedAt.timeIntervalSince(note.createdAt) > 1 { when += " · edited" }
            let author = note.authorId == data.me.userId ? "You" : (data.members[note.authorId]?.displayName ?? note.authorName)
            return TreeCardInfo.Note(id: note.id, author: author, when: when, flag: note.flag, body: note.body,
                                     canEdit: note.authorId == data.me.userId || data.isAdmin)
        }
        return TreeCardInfo(tree: tree, title: block.label(tree), state: state, status: status, notes: notes,
                            canToggle: marking != nil && data.season != nil && (held == nil || held?.shiftId == marking?.id))
    }

    // MARK: Notes

    /// A new note goes through FieldActions, like "Note a tree" by voice. Returns what to show.
    @discardableResult
    func addNote(_ tree: TreeRef, body: String, flag: NoteFlag) -> FieldReply {
        performCommand(.addTreeNote(tree, body: body, flag: flag))
    }

    /// Saves changes to a note. Nil when saved, else what went wrong.
    func editNote(_ id: UUID, body: String, flag: NoteFlag) -> String? {
        guard let data, var note = data.notes[id] else { return Speech.blockGone }
        guard note.authorId == data.me.userId || data.isAdmin else { return "Only the person who wrote a note, or an admin, can change it." }
        let text = Limits.clampNotes(body)
        guard !text.isEmpty else { return Speech.emptyNote }
        guard text != note.body || flag != note.flag else { return nil }
        note.body = text
        note.flag = flag
        note.updatedAt = currentTime()
        return saveNote(note)
    }

    /// Removes a note (it syncs as deleted). Nil when done, else what went wrong.
    func deleteNote(_ id: UUID) -> String? {
        guard let data, var note = data.notes[id] else { return nil }
        guard note.authorId == data.me.userId || data.isAdmin else { return "Only the person who wrote a note, or an admin, can delete it." }
        let at = currentTime()
        note.deletedAt = at
        note.updatedAt = at
        return saveNote(note)
    }

    private func saveNote(_ note: TreeNote) -> String? {
        saveRecords([.treeNote(note)]) ? nil : Self.saveFailed
    }

    // MARK: Field progress

    var progress: FieldProgress? {
        guard let data, let field else { return nil }
        let walker = FieldWalker(blocks: data.blocks(in: field.id))
        guard !walker.blocks.isEmpty else { return nil }
        let (shaped, total) = walker.progress(index: data.index)
        let percent = total > 0 ? shaped * 100 / total : 0
        let left = total - shaped
        if left <= 0 {
            return FieldProgress(shaped: shaped, total: total, percent: 100, summary: "Every row in \(field.name) is shaped.", timeLeft: nil)
        }
        let pace = Pace.stats(data.myShifts, now: currentTime(), treeCount: data.treeCount)
        var timeLeft: String?
        if pace.trees > 0, let hours = Pace.hoursLeft(treesLeft: left, treesPerHour: pace.treesPerHour) {
            timeLeft = "At \(Pace.rateText(pace.treesPerHour)) trees an hour, the rest takes about \(Pace.hoursWords(hours))."
        }
        return FieldProgress(shaped: shaped, total: total, percent: percent,
                             summary: "\(Fmt.count(shaped)) of \(Fmt.plural(total, "tree")) shaped.", timeLeft: timeLeft)
    }

    /// "48 of 240 shaped" for a block heading.
    func blockSummary(_ block: Block) -> String {
        guard let data else { return "" }
        return "\(Fmt.count(data.index.shapedCount(in: block))) of \(Fmt.count(block.treeCount)) shaped"
    }

    // MARK: Rows, for VoiceOver

    func rowSummary(_ row: RowRef) -> RowSummary? {
        guard let data, let block = data.block(row.blockId), block.contains(row) else { return nil }
        let marking = markingShift?.id
        var shaped = 0, mine = 0, notes = 0
        for position in 0..<block.treesPerRow {
            let tree = TreeRef(blockId: block.id, row: row.row, position: position)
            if let mark = data.index.mark(at: tree) {
                shaped += 1
                if mark.shiftId == marking { mine += 1 }
            }
            notes += data.notesByTree[tree]?.count ?? 0
        }
        var parts: [String] = [shaped == 0 ? "Not shaped" : "\(shaped) of \(block.treesPerRow) shaped"]
        if mine > 0 { parts.append("\(mine) on this shift") }
        if notes > 0 { parts.append(Fmt.plural(notes, "note")) }
        return RowSummary(row: row, title: "Row \(row.row + 1)", value: parts.joined(separator: ", "),
                          shaped: shaped, mine: mine, total: block.treesPerRow, notes: notes)
    }

    /// Swipe up on a row: marks its next free tree. Swipe down: unmarks this shift's last tree in it.
    func adjust(_ row: RowRef, up: Bool) {
        guard let data, let block = data.block(row.blockId), block.contains(row) else { return }
        if up {
            guard let free = data.index.freePositions(in: row, block: block).first else {
                if let summary = rowSummary(row) { show(MapMessage("\(block.label(row: row.row)): \(summary.value).", tone: .hint)) }
                return
            }
            toggle(TreeRef(blockId: block.id, row: row.row, position: free))
        } else {
            let marking = markingShift?.id
            let last = (0..<block.treesPerRow).reversed().first { position in
                data.index.mark(at: TreeRef(blockId: block.id, row: row.row, position: position))?.shiftId == marking
            }
            guard let last, marking != nil else {
                show(MapMessage(MarkMessages.rowTap(MarkChange(), row: row, block: block, mode: .erase), tone: .warning))
                return
            }
            toggle(TreeRef(blockId: block.id, row: row.row, position: last), erase: true)
        }
    }

    /// Trees in one row, for the row's detail list.
    func trees(in row: RowRef) -> [TreeRef] {
        guard let block = data?.block(row.blockId), block.contains(row) else { return [] }
        return (0..<block.treesPerRow).map { TreeRef(blockId: block.id, row: row.row, position: $0) }
    }

    /// "Tree 3: shaped on this shift, 1 note"
    func treeLine(_ tree: TreeRef) -> String {
        guard let data else { return "" }
        var parts: [String] = []
        if let mark = data.index.mark(at: tree) {
            parts.append(mark.shiftId == markingShift?.id ? "shaped on this shift" : "shaped earlier")
        } else {
            parts.append("not shaped")
        }
        let notes = data.notesByTree[tree]?.count ?? 0
        if notes > 0 { parts.append(Fmt.plural(notes, "note")) }
        return "Tree \(tree.position + 1): " + parts.joined(separator: ", ")
    }
}
