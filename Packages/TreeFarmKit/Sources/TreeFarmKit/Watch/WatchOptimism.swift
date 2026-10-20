import Foundation

/// The state the watch predicts a tap leads to, shown at once while the phone answers (or
/// while the tap waits out of reach). A mark drops the chip it marked, a break changes the
/// phase, a clock-in opens a shift under the minted id, `cancelShift` goes back off the clock.
/// The phone's next state replaces the prediction; `epoch` and `revision` never change here.
///
/// A shift-scoped command only applies to the shift it was made in (`shiftId`), as on the phone.
public enum WatchOptimism {
    public static func apply(_ command: FieldCommand, shiftId: UUID?, to state: WatchState, at time: Date) -> WatchState {
        guard state.signedIn else { return state }
        var s = state
        let onThisShift = shiftId != nil && shiftId == state.shiftId && state.snapshot != nil

        switch command {
        case .clockIn:
            guard state.snapshot == nil, let shiftId else { return state }
            let earlier = state.calendar.isSameDay(state.updatedAt, time) ? state.todayWorked : 0
            s.shiftId = shiftId
            s.shiftStart = time
            s.snapshot = LiveSnapshot(phase: .working, timerStart: time.addingTimeInterval(-earlier), workedSoFar: earlier,
                                      workedLabel: "worked today", breakStart: nil, breakReason: "", fieldName: state.fieldName,
                                      nextRows: Array(state.nextRows.prefix(3)), shiftTrees: 0, fieldShaped: 0, fieldTotal: 0,
                                      lastAction: "Clocked in", canUndo: false)
            s.canUndo = false

        case .clockOut:
            guard onThisShift, let snapshot = state.snapshot, let id = state.shiftId else { return state }
            let total = worked(snapshot, at: time)
            // The snapshot's timer counts today's earlier shifts too.
            let earlier = state.lastClosedShift.flatMap { closed in
                closed.shiftId != id && state.calendar.isSameDay(closed.start, time) ? closed.worked : nil
            } ?? 0
            let start = state.shiftStart ?? snapshot.timerStart
            let shiftWorked = state.calendar.isSameDay(start, time) ? max(0, total - earlier) : total
            s.lastClosedShift = ClosedShift(shiftId: id, start: start, end: time, worked: shiftWorked, trees: snapshot.shiftTrees)
            if state.calendar.isSameDay(start, time) { s.todayWorked = total }
            s.snapshot = nil
            s.shiftId = nil
            s.shiftStart = nil
            s.canUndo = false

        case .cancelShift(let id):
            guard onThisShift, id == state.shiftId else { return state }
            s.snapshot = nil
            s.shiftId = nil
            s.shiftStart = nil
            s.canUndo = false

        case .startBreak(let kind, let reason):
            guard onThisShift, var snapshot = state.snapshot, snapshot.phase == .working else { return state }
            snapshot.workedSoFar = worked(snapshot, at: time)
            snapshot.phase = kind == .lunch ? .lunch : .onBreak
            snapshot.breakStart = time
            snapshot.breakReason = Limits.clampReason(reason)
            s.snapshot = done(snapshot, kind == .lunch ? "Lunch started" : "Break started")
            if kind == .lunch { s.hadLunchToday = true }
            s.canUndo = true

        case .endBreak:
            guard onThisShift, var snapshot = state.snapshot, snapshot.phase != .working else { return state }
            snapshot.phase = .working
            snapshot.timerStart = time.addingTimeInterval(-snapshot.workedSoFar)
            snapshot.breakStart = nil
            snapshot.breakReason = ""
            s.snapshot = done(snapshot, "Back to work")
            s.canUndo = true

        case .markRow(let row):
            guard onThisShift, let snapshot = state.snapshot else { return state }
            let trees = state.nextRows.first { $0.rowRef == row }?.openTrees ?? 0
            s.nextRows.removeAll { $0.rowRef == row }
            s.snapshot = counted(done(snapshot, "Row \(row.row + 1) marked", rows: s.nextRows), trees)
            s.todayTrees += trees
            s.canUndo = true

        case .markNextRow:
            guard onThisShift, let snapshot = state.snapshot, let first = state.nextRows.first else { return state }
            let trees = first.openTrees ?? 0
            s.nextRows.removeFirst()
            s.snapshot = counted(done(snapshot, "Row \(first.row + 1) marked", rows: s.nextRows), trees)
            s.todayTrees += trees
            s.canUndo = true

        case .markTrees(_, let positions):
            guard onThisShift, let snapshot = state.snapshot else { return state }
            let what = positions.count == 1 ? "tree \(positions.lowerBound + 1)" : "trees \(positions.lowerBound + 1) to \(positions.upperBound + 1)"
            s.snapshot = done(snapshot, "Marked \(what)")
            s.canUndo = true

        case .addShiftNote:
            guard onThisShift, let snapshot = state.snapshot else { return state }
            s.snapshot = done(snapshot, "Note added")
            s.canUndo = true

        case .undo, .moveTo, .addTreeNote, .changeStart:
            return state
        }
        return s
    }

    /// The confirmed state with every waiting tap applied, oldest first, each once, leaving out
    /// the ones the phone lists as applied. A clock-in the phone will refuse because a shift is
    /// already open is aliased to that shift, as the phone does, so taps tagged with its minted
    /// id still show on the open shift.
    public static func displayed(confirmed: WatchState?, pending: [WatchRequest]) -> WatchState? {
        guard let confirmed else { return nil }
        let applied = Set(confirmed.appliedRequestIds)
        var seen = Set<UUID>()
        let ordered = pending.enumerated()
            .sorted { ($0.element.issuedAt, $0.offset) < ($1.element.issuedAt, $1.offset) }
            .map(\.element)
            .filter { !applied.contains($0.id) && seen.insert($0.id).inserted }

        var state = confirmed
        var aliases: [UUID: UUID] = [:]
        for request in ordered {
            guard let command = request.command else { continue }
            if case .clockIn = command, let minted = request.shiftId, state.snapshot != nil, let open = state.shiftId {
                aliases[minted] = open
                continue
            }
            let shiftId = request.shiftId.map { aliases[$0] ?? $0 }
            state = apply(command, shiftId: shiftId, to: state, at: request.issuedAt)
        }
        return state
    }

    // MARK: Helpers

    /// Worked time at `time` by the snapshot's own clock (frozen during a break).
    private static func worked(_ snapshot: LiveSnapshot, at time: Date) -> TimeInterval {
        snapshot.phase == .working ? max(0, time.timeIntervalSince(snapshot.timerStart)) : snapshot.workedSoFar
    }

    /// A marked row's trees, counted on the shift and in the field (never past its total).
    private static func counted(_ snapshot: LiveSnapshot, _ trees: Int) -> LiveSnapshot {
        guard trees > 0 else { return snapshot }
        var s = snapshot
        s.shiftTrees += trees
        s.fieldShaped = s.fieldTotal > 0 ? min(s.fieldTotal, s.fieldShaped + trees) : s.fieldShaped + trees
        return s
    }

    private static func done(_ snapshot: LiveSnapshot, _ lastAction: String, rows: [RowChip]? = nil) -> LiveSnapshot {
        var s = snapshot
        if let rows { s.nextRows = Array(rows.prefix(3)) }
        s.lastAction = lastAction
        s.canUndo = true
        return s
    }
}
