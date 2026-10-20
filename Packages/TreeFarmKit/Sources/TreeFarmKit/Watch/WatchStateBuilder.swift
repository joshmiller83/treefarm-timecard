import Foundation

/// Builds the `WatchState` the phone sends, from the same `FieldState` Siri and the lock screen
/// read, so the watch shows exactly what they would. Pay is never part of it.
public enum WatchStateBuilder {
    /// How many recent shifts `usualStart` looks at, and how many it needs.
    public static let usualStartShifts = 10
    public static let usualStartMinimum = 3

    public static func build(state: FieldState, now: Date, epoch: UUID, revision: Int, recordWorkouts: Bool,
                             appliedRequestIds: [UUID], lastAction: String?, canUndo: Bool) -> WatchState {
        let cal = state.calendar
        let index = state.index
        let shifts = state.liveShifts
        let open = state.openShift
        let today = shifts.filter { cal.isSameDay($0.start, now) }
        let count: (Shift) -> Int = { state.treeCount($0, index: index) }

        let chips = state.nextRows(WatchState.maxRows, index: index).compactMap { row -> RowChip? in
            guard let block = state.block(row.blockId) else { return nil }
            return RowChip(blockId: row.blockId, row: row.row, title: "Row \(row.row + 1)", blockName: Speech.blockTitle(block),
                           openTrees: index.freePositions(in: row, block: block).count)
        }
        let pace = Pace.stats(today, now: now, treeCount: count)
        // The lock screen's snapshot, with the same chips (and their tree counts) as `nextRows`.
        var snapshot = LiveSnapshot.build(state: state, now: now, lastAction: lastAction, canUndo: canUndo)
        snapshot?.nextRows = Array(chips.prefix(3))

        return WatchState(
            signedIn: true,
            farmName: state.farm.name,
            fieldName: state.currentField?.name ?? "",
            snapshot: snapshot,
            nextRows: chips,
            todayWorked: Hours.summary(shifts: shifts, now: now, calendar: cal).today,
            todayTrees: today.reduce(0) { $0 + count($1) },
            canUndo: canUndo,
            recordWorkouts: recordWorkouts,
            updatedAt: now,
            epoch: epoch,
            revision: revision,
            userId: state.me.userId,
            shiftId: open?.id,
            shiftStart: open?.start,
            lastClosedShift: lastClosed(shifts, count: count),
            appliedRequestIds: Array(appliedRequestIds.suffix(WatchState.maxAppliedIds)),
            hadLunchToday: today.contains { $0.breaks.contains { $0.kind == .lunch } },
            pacePerHour: pace.hasRate ? pace.treesPerHour : nil,
            farmTimeZone: state.farm.timeZoneId,
            usualStart: usualStart(shifts, calendar: cal))
    }

    /// The shift that ended last.
    static func lastClosed(_ shifts: [Shift], count: (Shift) -> Int) -> ClosedShift? {
        guard let last = shifts.filter({ $0.end != nil }).max(by: { $0.end! < $1.end! }), let end = last.end else { return nil }
        return ClosedShift(shiftId: last.id, start: last.start, end: end, worked: last.workedTime(at: end), trees: count(last))
    }

    /// The median start (hour and minute, farm time) of the last `usualStartShifts` shifts,
    /// or nil with fewer than `usualStartMinimum`. With an even count it's halfway between the
    /// middle two, to the minute.
    static func usualStart(_ shifts: [Shift], calendar: FarmCalendar) -> DateComponents? {
        let recent = shifts.sorted { $0.start > $1.start }.prefix(usualStartShifts)
        guard recent.count >= usualStartMinimum else { return nil }
        let minutes = recent.map { shift -> Int in
            let c = calendar.calendar.dateComponents([.hour, .minute], from: shift.start)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }.sorted()
        let mid = minutes.count / 2
        let median = minutes.count.isMultiple(of: 2) ? (minutes[mid - 1] + minutes[mid]) / 2 : minutes[mid]
        return DateComponents(hour: median / 60, minute: median % 60)
    }
}
