import Foundation

/// Everything a person can do in the field, by voice, lock screen or tap.
public enum FieldCommand: Hashable, Sendable {
    /// `fieldId` nil keeps the current field.
    case clockIn(fieldId: UUID?)
    case clockOut
    case startBreak(BreakKind, reason: String)
    case endBreak
    /// Mark the next open row shaped (the lock-screen button and "next row").
    case markNextRow
    case markRow(RowRef)
    /// Some trees in one row; positions count from 0.
    case markTrees(RowRef, positions: ClosedRange<Int>)
    /// "I'm in block 3". `row` counts from 0; nil means the block's first open row.
    case moveTo(blockId: UUID, row: Int?)
    case addShiftNote(String)
    case addTreeNote(TreeRef, body: String, flag: NoteFlag)
    case changeStart(Date)
    case undo
}

/// How to take back one action: the earlier copies of what it changed, and where you were.
public struct UndoEntry: Codable, Equatable, Sendable {
    /// Fits "Undid …": "row 14", "lunch".
    public var label: String
    public var restore: [SyncRecord]
    public var position: WorkPosition?

    public init(label: String, restore: [SyncRecord], position: WorkPosition?) {
        self.label = label
        self.restore = restore
        self.position = position
    }

    /// The restore records stamped with the time of the undo, so they win over what they replace.
    public func records(at now: Date) -> [SyncRecord] {
        restore.map { record in
            switch record {
            case .treeMark(var m):
                m.updatedAt = now
                if m.deletedAt != nil { m.deletedAt = now }
                return .treeMark(m)
            case .treeNote(var n):
                n.updatedAt = now
                if n.deletedAt != nil { n.deletedAt = now }
                return .treeNote(n)
            case .shift(var s):
                s.updatedAt = now
                return .shift(s)
            default:
                return record
            }
        }
    }
}

public struct FieldOutcome: Equatable, Sendable {
    /// What to save (to the store and the outbox, in one go).
    public var records: [SyncRecord]
    /// Where you are after the action.
    public var position: WorkPosition?
    /// What was pushed on the undo stack, if anything.
    public var undo: UndoEntry?
    /// What Siri says, and what the app shows as a toast.
    public var speech: String
    /// A few words for the lock screen: "Row 14 marked".
    public var lastAction: String?
}

public struct FieldFailure: Error, Equatable, Sendable {
    public var speech: String

    public init(_ speech: String) {
        self.speech = speech
    }
}

public enum FieldEngine {
    /// Runs one command against the state. On success the undo entry (if any) is pushed on `undo`.
    public static func perform(_ command: FieldCommand, state: FieldState, undo: inout UndoStack<UndoEntry>, now: Date) -> Result<FieldOutcome, FieldFailure> {
        do {
            var outcome = try run(command, state, &undo, now)
            if let entry = outcome.undo { undo.push(entry) }
            if outcome.position == nil { outcome.position = state.position }
            return .success(outcome)
        } catch {
            return .failure(error)
        }
    }

    /// A question to ask out loud before running the command, or nil to just do it.
    /// Clocking out always asks; marking a row far from where you are asks, in case Siri misheard.
    public static func confirmation(for command: FieldCommand, state: FieldState, now: Date) -> String? {
        switch command {
        case .clockOut:
            guard let open = state.openShift else { return nil }
            let cal = state.calendar
            let worked = Hours.bigClock(shifts: state.liveShifts, now: now, calendar: cal)
            let when = Hours.isStale(open, now: now, calendar: cal) ? "this shift" : "today"
            return "You’ve worked \(Fmt.spokenDuration(worked)) \(when). Clock out?"
        case .markRow(let row):
            guard let block = state.block(row.blockId), block.contains(row),
                  let here = state.nextRows(1).first, let hereBlock = state.block(here.blockId) else { return nil }
            if here.blockId != row.blockId {
                return "Row \(row.row + 1) in \(Speech.blockPhrase(block))? You’re in \(Speech.blockPhrase(hereBlock))."
            }
            let distance = row.row - here.row
            guard abs(distance) > 5 else { return nil }
            return "Row \(row.row + 1) in \(Speech.blockPhrase(block))? That’s \(abs(distance)) rows \(distance > 0 ? "ahead" : "behind")."
        default:
            return nil
        }
    }

    // MARK: - Commands

    private static func run(_ command: FieldCommand, _ state: FieldState, _ undo: inout UndoStack<UndoEntry>, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        switch command {
        case .clockIn(let fieldId): return try clockIn(fieldId, state, now)
        case .clockOut: return try clockOut(state, now)
        case .startBreak(let kind, let reason): return try startBreak(kind, reason, state, now)
        case .endBreak: return try endBreak(state, now)
        case .markNextRow: return try markNextRow(state, now)
        case .markRow(let row): return try markRow(row, state, now)
        case .markTrees(let row, let positions): return try markTrees(row, positions, state, now)
        case .moveTo(let blockId, let row): return try moveTo(blockId, row, state, now)
        case .addShiftNote(let text): return try addShiftNote(text, state, now)
        case .addTreeNote(let tree, let body, let flag): return try addTreeNote(tree, body, flag, state, now)
        case .changeStart(let start): return try changeStart(start, state, now)
        case .undo:
            guard let entry = undo.pop() else { throw FieldFailure(Speech.nothingToUndo) }
            return FieldOutcome(records: entry.records(at: now), position: entry.position, undo: nil,
                                speech: "Undid \(entry.label).", lastAction: "Undid \(entry.label)")
        }
    }

    private static func clockIn(_ fieldId: UUID?, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        let cal = state.calendar
        if let open = state.openShift {
            throw FieldFailure("You’re already clocked in since \(Fmt.spokenTime(open.start, cal)).")
        }
        let shift: Shift
        do {
            shift = try Clock.clockIn(userId: state.me.userId, farmId: state.farm.id, rateCents: state.me.rateCents, at: now, shifts: state.liveShifts)
        } catch {
            throw FieldFailure(error.message)
        }
        var speech = "Clocked in at \(Fmt.spokenTime(now, cal))."
        var position = state.position
        let field = fieldId.flatMap { id in state.liveFields.first { $0.id == id } } ?? state.currentField
        if let field {
            if position?.fieldId != field.id { position = WorkPosition(fieldId: field.id) }
            let walker = state.walker(for: field)
            if !walker.blocks.isEmpty {
                if let row = walker.nextRows(from: FieldState.valid(position?.next, in: walker), count: 1, index: state.index).first,
                   let block = walker.block(row.blockId) {
                    position?.next = row
                    speech += " You’re on \(Speech.place(row, block))."
                } else {
                    speech += " Every row in \(field.name) is shaped."
                }
            }
        }
        return FieldOutcome(records: [.shift(shift)], position: position, undo: nil, speech: speech, lastAction: "Clocked in")
    }

    private static func clockOut(_ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        guard let open = state.openShift else { throw FieldFailure(Speech.notClockedIn) }
        let closed: Shift
        do { closed = try Clock.clockOut(at: now, shift: open) } catch { throw FieldFailure(error.message) }
        let trees = state.treeCount(closed)
        var speech = "Clocked out at \(Fmt.spokenTime(now, state.calendar)). \(Fmt.spokenDuration(closed.workedTime(at: now)))"
        speech += trees > 0 ? ", \(Fmt.plural(trees, "tree"))." : "."
        return FieldOutcome(records: [.shift(closed)], position: nil, undo: nil, speech: speech, lastAction: "Clocked out")
    }

    private static func startBreak(_ kind: BreakKind, _ reason: String, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        let cal = state.calendar
        guard let open = state.openShift else { throw FieldFailure(Speech.notClockedIn) }
        if let b = open.openBreak {
            throw FieldFailure("You’re already on \(b.kind == .lunch ? "lunch" : "a break") since \(Fmt.spokenTime(b.start, cal)). Say \"back to work\" when you’re done.")
        }
        let why = Limits.clampReason(reason)
        let updated: Shift
        do { updated = try Clock.startBreak(kind, reason: why, at: now, in: open) } catch { throw FieldFailure(error.message) }
        let at = Fmt.spokenTime(now, cal)
        let speech: String
        switch kind {
        case .lunch: speech = "Lunch started at \(at)."
        case .break: speech = why.isEmpty ? "Break started at \(at)." : "Break for \(why) started at \(at)."
        }
        let label = kind == .lunch ? "lunch" : "the break"
        return FieldOutcome(records: [.shift(updated)], position: nil,
                            undo: UndoEntry(label: label, restore: [.shift(open)], position: state.position),
                            speech: speech, lastAction: kind == .lunch ? "Lunch started" : "Break started")
    }

    private static func endBreak(_ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        guard let open = state.openShift else { throw FieldFailure(Speech.notClockedIn) }
        guard let b = open.openBreak else { throw FieldFailure("You’re not on a break.") }
        let updated: Shift
        do { updated = try Clock.endBreak(at: now, in: open) } catch { throw FieldFailure(error.message) }
        let what = b.kind == .lunch ? "Lunch" : "The break"
        let speech = "Back at \(Fmt.spokenTime(now, state.calendar)). \(what) was \(Fmt.spokenDuration(now.timeIntervalSince(b.start)))."
        let label = b.kind == .lunch ? "the end of lunch" : "the end of the break"
        return FieldOutcome(records: [.shift(updated)], position: nil,
                            undo: UndoEntry(label: label, restore: [.shift(open)], position: state.position),
                            speech: speech, lastAction: "Back to work")
    }

    // MARK: rows

    /// What marking needs: a shift on the clock and an active season.
    private static func marking(_ state: FieldState, _ now: Date) throws(FieldFailure) -> MarkContext {
        guard let open = state.openShift else { throw FieldFailure(Speech.notClockedIn) }
        guard let season = state.season else { throw FieldFailure(Speech.noSeason) }
        return MarkContext(shiftId: open.id, userId: state.me.userId, seasonId: season.id, now: now)
    }

    private static func markNextRow(_ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        let ctx = try marking(state, now)
        guard let field = state.currentField else { throw FieldFailure(Speech.noField) }
        let walker = state.walker(for: field)
        guard !walker.blocks.isEmpty else { throw FieldFailure("\(field.name) has no blocks yet. Add them in the Trees tab.") }
        let index = state.index
        guard let row = walker.nextRows(from: FieldState.valid(state.position?.next, in: walker), count: 1, index: index).first else {
            throw FieldFailure("Every row in \(field.name) is shaped.")
        }
        return markWholeRow(row, field: field, walker: walker, index: index, ctx: ctx, state: state, now: now)
    }

    private static func markRow(_ row: RowRef, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        let ctx = try marking(state, now)
        guard let block = state.block(row.blockId), let field = state.field(block.fieldId) else { throw FieldFailure(Speech.blockGone) }
        guard block.contains(row) else { throw FieldFailure(Speech.rowsRange(block)) }
        let walker = state.walker(for: field)
        let index = state.index
        if index.freePositions(in: row, block: block).isEmpty {
            let holders = (0..<block.treesPerRow).compactMap { index.mark(at: TreeRef(blockId: block.id, row: row.row, position: $0)) }
            if holders.allSatisfy({ $0.shiftId == ctx.shiftId }) {
                throw FieldFailure("Row \(row.row + 1) is already marked.")
            }
            let other = holders.first { $0.shiftId != ctx.shiftId }!
            let who = other.userId == state.me.userId ? "you" : (state.member(other.userId)?.displayName ?? "someone else")
            var speech = "Row \(row.row + 1) was shaped by \(who) on \(Fmt.monthDay(other.markedAt, state.calendar))."
            if let open = state.nextRows(1, index: index).first {
                speech += " Next open row is \(open.blockId == row.blockId ? String(open.row + 1) : Speech.relative(open, from: nil, blocks: state.block))."
            }
            throw FieldFailure(speech)
        }
        let here = state.nextRows(1, index: index).first
        return markWholeRow(row, field: field, walker: walker, index: index, ctx: ctx, state: state, now: now,
                            sayBlock: here != nil && here?.blockId != row.blockId)
    }

    private static func markWholeRow(_ row: RowRef, field: Field, walker: FieldWalker, index: MarkIndex, ctx: MarkContext,
                                     state: FieldState, now: Date, sayBlock: Bool = false) -> FieldOutcome {
        let block = walker.block(row.blockId)!
        let change = MarkOps.markRow(row, block: block, ctx: ctx, index: index)
        let added = change.added.count
        let already = block.treesPerRow - added
        let after = index.applying(change)
        let nextOpen = walker.nextRows(from: walker.row(after: row), count: 1, index: after).first

        let name = sayBlock ? "Row \(row.row + 1) in \(Speech.blockPhrase(block))" : "Row \(row.row + 1)"
        var speech = "\(name) marked, \(Fmt.plural(added, "tree"))."
        if already > 0 { speech += already == 1 ? " 1 was already shaped." : " \(already) were already shaped." }
        if let nextOpen {
            speech += " Next is \(Speech.relative(nextOpen, from: row, blocks: walker.block))."
        } else {
            speech += " That was the last open row in \(field.name)."
        }
        let records = change.added.map(SyncRecord.treeMark) + change.removed.map(SyncRecord.treeMark)
        let undoRecords = change.inverse(now: now)
        return FieldOutcome(
            records: records,
            position: WorkPosition(fieldId: field.id, next: nextOpen ?? walker.row(after: row)),
            undo: UndoEntry(label: "row \(row.row + 1)", restore: (undoRecords.added + undoRecords.removed).map(SyncRecord.treeMark),
                            position: state.position),
            speech: speech,
            lastAction: "Row \(row.row + 1) marked")
    }

    private static func markTrees(_ row: RowRef, _ positions: ClosedRange<Int>, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        let ctx = try marking(state, now)
        guard let block = state.block(row.blockId), let field = state.field(block.fieldId) else { throw FieldFailure(Speech.blockGone) }
        guard block.contains(row) else { throw FieldFailure(Speech.rowsRange(block)) }
        guard positions.lowerBound >= 0, positions.upperBound < block.treesPerRow else { throw FieldFailure(Speech.treesRange(block)) }
        let index = state.index
        let change = MarkOps.range(block: block, rows: row.row...row.row, positions: positions, add: true, ctx: ctx, index: index)
        guard !change.added.isEmpty else { throw FieldFailure("Those trees were already shaped.") }
        let what = positions.count == 1 ? "tree \(positions.lowerBound + 1)" : "trees \(positions.lowerBound + 1) to \(positions.upperBound + 1)"
        var speech = "Marked \(what) in row \(row.row + 1)."
        let skipped = positions.count - change.added.count
        if skipped > 0 { speech += skipped == 1 ? " 1 was already shaped." : " \(skipped) were already shaped." }

        var position = state.position
        let after = index.applying(change)
        if position?.next == row, after.freePositions(in: row, block: block).isEmpty {
            let walker = state.walker(for: field)
            position?.next = walker.nextRows(from: walker.row(after: row), count: 1, index: after).first
        }
        let inverse = change.inverse(now: now)
        return FieldOutcome(records: change.added.map(SyncRecord.treeMark), position: position,
                            undo: UndoEntry(label: "\(what) in row \(row.row + 1)", restore: (inverse.added + inverse.removed).map(SyncRecord.treeMark), position: state.position),
                            speech: speech, lastAction: "Marked \(what)")
    }

    private static func moveTo(_ blockId: UUID, _ row: Int?, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        guard let block = state.block(blockId), let field = state.field(block.fieldId) else { throw FieldFailure(Speech.blockGone) }
        let start = RowRef(blockId: blockId, row: row ?? 0)
        guard block.contains(start) else { throw FieldFailure(Speech.rowsRange(block)) }
        let walker = state.walker(for: field)
        guard let next = walker.nextRows(from: start, count: 1, index: state.index).first else {
            throw FieldFailure("Every row in \(field.name) is shaped.")
        }
        let speech: String
        if next == start {
            speech = "Okay, \(Speech.place(next, block)) is next."
        } else if let row {
            let say = next.blockId == blockId ? String(next.row + 1) : Speech.relative(next, from: nil, blocks: walker.block)
            speech = "Row \(row + 1) in \(Speech.blockPhrase(block)) is already shaped. Next open row is \(say)."
        } else if next.blockId == blockId {
            speech = "Okay, \(Speech.place(next, block)) is next."
        } else {
            speech = "\(Speech.blockTitle(block)) is all shaped. Next open row is \(Speech.relative(next, from: nil, blocks: walker.block))."
        }
        return FieldOutcome(records: [], position: WorkPosition(fieldId: field.id, next: next),
                            undo: UndoEntry(label: "the move", restore: [], position: state.position),
                            speech: speech, lastAction: "Moved to \(Speech.blockTitle(block))")
    }

    // MARK: notes and times

    private static func addShiftNote(_ text: String, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        let cal = state.calendar
        let target = state.openShift ?? state.liveShifts.filter { cal.isSameDay($0.start, now) }.max { $0.start < $1.start }
        guard let target else { throw FieldFailure(Speech.notClockedIn) }
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { throw FieldFailure(Speech.emptyNote) }
        let combined = target.notes.isEmpty ? note : target.notes + "\n" + note
        let kept = String(combined.prefix(Limits.notes))
        guard kept != target.notes else { throw FieldFailure("Today’s notes are full, so nothing was added.") }
        var updated = target
        updated.notes = kept
        updated.updatedAt = now
        let speech = kept.count < combined.count ? "Added to today’s notes, but it was cut short to fit." : "Added to today’s notes."
        return FieldOutcome(records: [.shift(updated)], position: nil,
                            undo: UndoEntry(label: "the note", restore: [.shift(target)], position: state.position),
                            speech: speech, lastAction: "Note added")
    }

    private static func addTreeNote(_ tree: TreeRef, _ body: String, _ flag: NoteFlag, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        guard let block = state.block(tree.blockId) else { throw FieldFailure(Speech.blockGone) }
        guard block.contains(tree.rowRef) else { throw FieldFailure(Speech.rowsRange(block)) }
        guard block.contains(tree) else { throw FieldFailure(Speech.treesRange(block)) }
        let text = Limits.clampNotes(body)
        guard !text.isEmpty else { throw FieldFailure(Speech.emptyNote) }
        let note = TreeNote(farmId: state.farm.id, tree: tree, authorId: state.me.userId, authorName: state.me.displayName,
                            body: text, flag: flag, createdAt: now)
        var gone = note
        gone.deletedAt = now
        let place = "\(Speech.place(tree.rowRef, block)), tree \(tree.position + 1)"
        return FieldOutcome(records: [.treeNote(note)], position: nil,
                            undo: UndoEntry(label: "the note on row \(tree.row + 1), tree \(tree.position + 1)", restore: [.treeNote(gone)], position: state.position),
                            speech: "Noted on \(place).", lastAction: "Tree note saved")
    }

    private static func changeStart(_ start: Date, _ state: FieldState, _ now: Date) throws(FieldFailure) -> FieldOutcome {
        guard let open = state.openShift else { throw FieldFailure(Speech.notClockedIn) }
        let others = state.liveShifts.filter { $0.id != open.id }
        if let problem = ShiftRules.validateNewStart(start, for: open, others: others, now: now, calendar: state.calendar) {
            throw FieldFailure(problem.message)
        }
        var updated = open
        updated.start = start
        updated.updatedAt = now
        return FieldOutcome(records: [.shift(updated)], position: nil,
                            undo: UndoEntry(label: "the start time", restore: [.shift(open)], position: state.position),
                            speech: "Start time changed to \(Fmt.spokenTime(start, state.calendar)).", lastAction: "Start time changed")
    }
}
