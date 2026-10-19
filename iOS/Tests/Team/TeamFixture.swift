import Foundation
import TimeCardCore
@testable import TimeCard

/// A small farm for the Team tab's tests: one admin (Alex), one worker (Sam), and Jo,
/// who was removed. It's Wednesday Oct 21, 2026 at noon on the farm; weeks start Monday.
struct TeamFixture {
    let farm: Farm
    let calendar: FarmCalendar
    let now: Date
    let season: Season
    var alex: Member
    var sam: Member
    var jo: Member
    let north: Field
    var snapshot: FarmSnapshot

    init() {
        let farmId = UUID()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let season = Season(farmId: farmId, name: "2026", startedAt: start, updatedAt: start)
        let farm = Farm(id: farmId, name: "Test Tree Farm", timeZoneId: "America/Indiana/Indianapolis", weekStart: .monday,
                        activeSeasonId: season.id, updatedAt: start)
        let calendar = FarmCalendar(farm: farm)
        self.farm = farm
        self.calendar = calendar
        self.season = season
        self.now = calendar.date(on: DayKey(year: 2026, month: 10, day: 21), hour: 12, minute: 0)
        alex = Member(userId: UUID(), farmId: farmId, displayName: "Alex Rivera", email: "alex@example.com", role: .admin,
                      jobTitle: "Crew lead", rateCents: 2000, updatedAt: start)
        sam = Member(userId: UUID(), farmId: farmId, displayName: "Sam Ortiz", email: "sam@example.com", role: .worker,
                     jobTitle: "Trimmer", rateCents: 1650, updatedAt: start)
        jo = Member(userId: UUID(), farmId: farmId, displayName: "Jo Banks", email: "", role: .worker, updatedAt: start,
                    removedAt: start.addingTimeInterval(86400))
        north = Field(farmId: farmId, name: "North Field", sortOrder: 0, updatedAt: start)
        snapshot = FarmSnapshot(farmId: farmId)
        snapshot.apply(.farm(farm))
        snapshot.seasons[season.id] = season
        for m in [alex, sam, jo] { snapshot.members[m.userId] = m }
        snapshot.fields[north.id] = north
    }

    /// That wall-clock time on a day in October 2026, on the farm.
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(on: DayKey(year: 2026, month: 10, day: day), hour: hour, minute: minute)
    }

    @discardableResult
    mutating func addShift(_ member: Member, from start: Date, to end: Date?, breaks: [Break] = []) -> Shift {
        let shift = Shift(userId: member.userId, farmId: farm.id, start: start, end: end, breaks: breaks, rateCents: member.rateCents, updatedAt: start)
        snapshot.shifts[shift.id] = shift
        return shift
    }

    @discardableResult
    mutating func addBlock(_ name: String, row: Int, column: Int, rows: Int = 10, trees: Int = 8,
                           direction: RowDirection = .across, field: Field? = nil) -> Block {
        let block = Block(fieldId: (field ?? north).id, name: name, gridRow: row, gridColumn: column, rowCount: rows,
                          treesPerRow: trees, direction: direction, updatedAt: farm.updatedAt)
        snapshot.blocks[block.id] = block
        return block
    }

    @discardableResult
    mutating func mark(_ block: Block, row: Int, position: Int, shift: Shift, season: Season? = nil) -> TreeMark {
        let mark = TreeMark(seasonId: (season ?? self.season).id, tree: TreeRef(blockId: block.id, row: row, position: position),
                            shiftId: shift.id, userId: shift.userId, markedAt: shift.start.addingTimeInterval(600))
        snapshot.apply(.treeMark(mark))
        return mark
    }

    @discardableResult
    mutating func note(_ block: Block, row: Int, position: Int) -> TreeNote {
        let note = TreeNote(farmId: farm.id, tree: TreeRef(blockId: block.id, row: row, position: position), authorId: alex.userId,
                            authorName: alex.displayName, body: "Leaning", createdAt: farm.updatedAt)
        snapshot.notes[note.id] = note
        return note
    }
}

extension TeamEdit {
    /// The records an edit would save, or nothing.
    var records: [SyncRecord] {
        if case .save(let records) = self { return records }
        return []
    }

    var problem: String? {
        if case .problem(let text) = self { return text }
        return nil
    }
}
