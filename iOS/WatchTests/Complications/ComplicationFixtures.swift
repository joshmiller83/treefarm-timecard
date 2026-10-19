import Foundation
import TreeFarmKit

/// Watch states for the complication tests: a shift on Monday, Oct 19 2026 at a farm in Indiana.
enum ComplicationFixtures {
    static let zone = "America/Indiana/Indianapolis"
    static let calendar = FarmCalendar(timeZone: TimeZone(identifier: zone)!, weekStart: .monday)
    static let block2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let block3 = UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!
    static let shift = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
    static let epoch = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!

    /// That farm-local time on Oct 19 (or another day).
    static func at(_ hour: Int, _ minute: Int, day: Int = 19) -> Date {
        calendar.date(on: DayKey(year: 2026, month: 10, day: day), hour: hour, minute: minute)
    }

    static func chips(_ rows: [Int], block: UUID = block2, name: String = "Block 2") -> [RowChip] {
        rows.map { RowChip(blockId: block, row: $0 - 1, title: "Row \($0)", blockName: name) }
    }

    /// Clocked in at 7:01, 3 h 41 min worked by 10:42, rows 14, 15 and 16 next.
    static func snapshot(_ phase: LiveSnapshot.Phase = .working, rows: [Int] = [14, 15, 16], trees: Int = 38,
                         worked: TimeInterval = 3 * 3600 + 41 * 60, shaped: Int = 120, total: Int = 400) -> LiveSnapshot {
        let madeAt = at(10, 42)
        return LiveSnapshot(phase: phase, timerStart: madeAt.addingTimeInterval(-worked), workedSoFar: worked, workedLabel: "worked today",
                            breakStart: phase == .working ? nil : at(10, 30), breakReason: "", fieldName: "North",
                            nextRows: Array(chips(rows).prefix(3)), shiftTrees: trees, fieldShaped: shaped, fieldTotal: total,
                            lastAction: nil, canUndo: false)
    }

    static func working(rows: [Int] = Array(14...30), trees: Int = 38) -> WatchState {
        state(snapshot(.working, rows: rows, trees: trees), rows: rows)
    }

    static func onBreak(_ phase: LiveSnapshot.Phase = .lunch) -> WatchState {
        state(snapshot(phase), rows: Array(14...30))
    }

    static func offClock(todayWorked: TimeInterval = 0, usualStart: DateComponents? = DateComponents(hour: 7, minute: 0)) -> WatchState {
        var s = state(nil, rows: Array(14...30), todayWorked: todayWorked)
        s.usualStart = usualStart
        return s
    }

    static func state(_ snapshot: LiveSnapshot?, rows: [Int], todayWorked: TimeInterval = 0, signedIn: Bool = true) -> WatchState {
        WatchState(signedIn: signedIn, farmName: "Dull’s Tree Farm", fieldName: "North", snapshot: snapshot, nextRows: chips(rows),
                   todayWorked: todayWorked, todayTrees: 212, canUndo: false, recordWorkouts: true, updatedAt: at(10, 42),
                   epoch: epoch, revision: 7, userId: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
                   shiftId: snapshot == nil ? nil : shift, shiftStart: snapshot == nil ? nil : at(7, 1),
                   farmTimeZone: zone, usualStart: DateComponents(hour: 7, minute: 0))
    }
}
