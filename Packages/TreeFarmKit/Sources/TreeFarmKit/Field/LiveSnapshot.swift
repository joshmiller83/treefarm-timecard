import Foundation

/// One of the next-row buttons on the lock screen.
public struct RowChip: Codable, Hashable, Sendable, Identifiable {
    public var blockId: UUID
    /// Counts from 0.
    public var row: Int
    /// "Row 14"
    public var title: String
    /// "Block 2"
    public var blockName: String
    /// The trees marking this row would shape (its unshaped ones), when the sender counted them.
    /// The watch adds them to "Block 2 · 38 trees" while a mark waits for the phone.
    public var openTrees: Int?

    public init(blockId: UUID, row: Int, title: String, blockName: String, openTrees: Int? = nil) {
        self.blockId = blockId
        self.row = row
        self.title = title
        self.blockName = blockName
        self.openTrees = openTrees
    }

    public var id: String { "\(blockId.uuidString)-\(row)" }
    public var rowRef: RowRef { RowRef(blockId: blockId, row: row) }
}

/// What the Live Activity shows. It's the activity's content state, so it stays small and Codable.
/// While working, the timer ticks on its own from `timerStart` with no updates needed.
public struct LiveSnapshot: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case working, lunch, onBreak
    }

    public var phase: Phase
    /// Worked time so far = now - timerStart, while working.
    public var timerStart: Date
    /// Worked time when the snapshot was made; shown frozen during breaks.
    public var workedSoFar: TimeInterval
    /// "worked today", or "worked this shift" for a shift that started on an earlier day.
    public var workedLabel: String
    public var breakStart: Date?
    public var breakReason: String
    public var fieldName: String
    public var nextRows: [RowChip]
    public var shiftTrees: Int
    public var fieldShaped: Int
    public var fieldTotal: Int
    public var lastAction: String?
    public var canUndo: Bool

    public init(phase: Phase, timerStart: Date, workedSoFar: TimeInterval, workedLabel: String, breakStart: Date?, breakReason: String,
                fieldName: String, nextRows: [RowChip], shiftTrees: Int, fieldShaped: Int, fieldTotal: Int, lastAction: String?, canUndo: Bool) {
        self.phase = phase
        self.timerStart = timerStart
        self.workedSoFar = workedSoFar
        self.workedLabel = workedLabel
        self.breakStart = breakStart
        self.breakReason = breakReason
        self.fieldName = fieldName
        self.nextRows = nextRows
        self.shiftTrees = shiftTrees
        self.fieldShaped = fieldShaped
        self.fieldTotal = fieldTotal
        self.lastAction = lastAction
        self.canUndo = canUndo
    }

    /// The snapshot for the open shift, or nil when off the clock.
    public static func build(state: FieldState, now: Date, lastAction: String? = nil, canUndo: Bool = false) -> LiveSnapshot? {
        guard let open = state.openShift else { return nil }
        let cal = state.calendar
        let worked = Hours.bigClock(shifts: state.liveShifts, now: now, calendar: cal)
        let phase: Phase = switch open.openBreak?.kind {
        case .lunch?: .lunch
        case .break?: .onBreak
        case nil: .working
        }
        let index = state.index
        let chips = state.nextRows(3, index: index).compactMap { row -> RowChip? in
            guard let block = state.block(row.blockId) else { return nil }
            return RowChip(blockId: row.blockId, row: row.row, title: "Row \(row.row + 1)", blockName: Speech.blockTitle(block))
        }
        var shaped = 0, total = 0
        if let field = state.currentField {
            (shaped, total) = state.walker(for: field).progress(index: index)
        }
        return LiveSnapshot(
            phase: phase,
            timerStart: now.addingTimeInterval(-worked),
            workedSoFar: worked,
            workedLabel: Hours.isStale(open, now: now, calendar: cal) ? "worked this shift" : "worked today",
            breakStart: open.openBreak?.start,
            breakReason: open.openBreak?.reason ?? "",
            fieldName: state.currentField?.name ?? "",
            nextRows: chips,
            shiftTrees: state.treeCount(open, index: index),
            fieldShaped: shaped,
            fieldTotal: total,
            lastAction: lastAction,
            canUndo: canUndo)
    }
}
