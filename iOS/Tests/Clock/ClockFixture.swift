import Foundation
import TimeCardCore

/// A small farm for the Clock and Settings tests: one field of two 10×10 blocks, one
/// season, and Josh, a trimmer paid $18 an hour. The farm runs on Indianapolis time,
/// weeks start Monday, and "today" is Wednesday, Oct 14, 2026.
struct ClockFixture {
    let farmId = UUID()
    let seasonId = UUID()
    let fieldId = UUID()
    let block1 = UUID()
    let block2 = UUID()
    let userId = UUID()
    let otherUserId = UUID()

    var farm: Farm {
        Farm(id: farmId, name: "Test Tree Farm", timeZoneId: "America/Indiana/Indianapolis", weekStart: .monday,
             activeSeasonId: seasonId, updatedAt: start)
    }

    var calendar: FarmCalendar { FarmCalendar(timeZone: TimeZone(identifier: "America/Indiana/Indianapolis")!, weekStart: .monday) }
    /// When the farm was set up: Sep 1, 2026.
    let start = Date(timeIntervalSince1970: 1_788_264_000)
    var today: DayKey { DayKey(year: 2026, month: 10, day: 14) }

    var season: Season { Season(id: seasonId, farmId: farmId, name: "2026", startedAt: start, updatedAt: start) }
    var field: Field { Field(id: fieldId, farmId: farmId, name: "North Field", updatedAt: start) }
    var blocks: [Block] {
        [Block(id: block1, fieldId: fieldId, name: "1", gridRow: 0, gridColumn: 0, rowCount: 10, treesPerRow: 10, updatedAt: start),
         Block(id: block2, fieldId: fieldId, name: "2", gridRow: 0, gridColumn: 1, rowCount: 10, treesPerRow: 10, updatedAt: start)]
    }

    var me: Member {
        Member(userId: userId, farmId: farmId, displayName: "Josh", email: "josh@example.com", role: .worker,
               jobTitle: "Trimmer", rateCents: 1800, updatedAt: start)
    }

    var other: Member {
        Member(userId: otherUserId, farmId: farmId, displayName: "Sam", email: "", role: .worker, updatedAt: start)
    }

    /// That wall-clock time on the farm.
    func at(_ day: DayKey, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(on: day, hour: hour, minute: minute).addingTimeInterval(TimeInterval(second))
    }

    /// That time today (Wednesday, Oct 14).
    func today(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        at(today, hour, minute, second)
    }

    func day(_ offset: Int) -> DayKey {
        calendar.dayKey(calendar.addDays(today(12, 0), offset))
    }

    func shift(_ startAt: Date, _ endAt: Date? = nil, breaks: [Break] = [], notes: String = "", rateCents: Int = 1800,
               id: UUID = UUID()) -> Shift {
        Shift(id: id, userId: userId, farmId: farmId, start: startAt, end: endAt, breaks: breaks, notes: notes,
              rateCents: rateCents, updatedAt: endAt ?? startAt)
    }

    /// Whole rows shaped on a shift: `rows` count from 0.
    func marks(block: UUID? = nil, rows: ClosedRange<Int>, on shift: Shift, userId: UUID? = nil) -> [TreeMark] {
        rows.flatMap { row in
            (0..<10).map { position in
                TreeMark(seasonId: seasonId, tree: TreeRef(blockId: block ?? block1, row: row, position: position),
                         shiftId: shift.id, userId: userId ?? self.userId, markedAt: shift.start)
            }
        }
    }

    func state(shifts: [Shift] = [], marks: [TreeMark] = [], position: WorkPosition? = nil, me: Member? = nil) -> FieldState {
        FieldState(farm: farm, me: me ?? self.me, season: season, fields: [field], blocks: blocks, myShifts: shifts,
                   marks: marks, members: [me ?? self.me, other], position: position)
    }
}
