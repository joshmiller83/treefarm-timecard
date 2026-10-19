import CoreGraphics
import Foundation
import TimeCardCore
@testable import TimeCard

/// A small farm for the map's tests, saved into a plain snapshot the way the session would.
///
/// North field: block 1 and block 2 side by side (20 rows × 12 trees, rows across), and
/// block 3 below them (6 rows × 4 trees, rows down). Sam shaped rows 1–2 of block 1 on
/// Sep 22; I shaped row 3 on my Oct 18 shift and I'm clocked in now (Oct 19, 7:00).
@MainActor
final class TreeMapFixture {
    let calendar = FarmCalendar(timeZone: TimeZone(identifier: "America/Indiana/Indianapolis")!, weekStart: .monday)
    let farm: Farm
    let season: Season
    let me: Member
    let sam: Member
    let north: Field
    let creek: Field
    let block1: Block
    let block2: Block
    let block3: Block
    let samShift: Shift
    let earlier: Shift
    var open: Shift?
    var snapshot: FarmSnapshot
    var now: Date

    var saved: [[SyncRecord]] = []
    var commands: [FieldCommand] = []
    var failSaves = false
    var reply = FieldReply(speech: "Noted.", succeeded: true)

    private(set) lazy var model: TreeMapModel = {
        let model = TreeMapModel(
            save: { [unowned self] records in
                if failSaves { throw CocoaError(.fileWriteUnknown) }
                saved.append(records)
                for record in records { snapshot.apply(record) }
            },
            perform: { [unowned self] command in
                commands.append(command)
                return reply
            },
            now: { [unowned self] in now })
        model.viewportWidth = 360
        model.update(snapshot: snapshot, farm: farm, me: me)
        return model
    }()

    init(role: Role = .admin, clockedIn: Bool = true, withSeason: Bool = true) {
        let farmId = UUID()
        let seasonStart = calendar.date(on: DayKey(year: 2026, month: 3, day: 1), hour: 8, minute: 0)
        season = Season(farmId: farmId, name: "2026", startedAt: seasonStart, updatedAt: seasonStart)
        farm = Farm(id: farmId, name: "Pine Hollow", timeZoneId: "America/Indiana/Indianapolis", weekStart: .monday,
                    activeSeasonId: withSeason ? season.id : nil, updatedAt: seasonStart)
        me = Member(userId: UUID(), farmId: farmId, displayName: "Alex Rivera", email: "alex@example.com", role: role, rateCents: 2000)
        sam = Member(userId: UUID(), farmId: farmId, displayName: "Sam Ortiz", email: "sam@example.com", role: .worker, rateCents: 1800)
        north = Field(farmId: farmId, name: "North Field", sortOrder: 0)
        creek = Field(farmId: farmId, name: "Creek Field", sortOrder: 1)
        block1 = Block(fieldId: north.id, name: "1", gridRow: 0, gridColumn: 0, rowCount: 20, treesPerRow: 12)
        block2 = Block(fieldId: north.id, name: "2", gridRow: 0, gridColumn: 1, rowCount: 20, treesPerRow: 12)
        block3 = Block(fieldId: north.id, name: "3", gridRow: 1, gridColumn: 0, rowCount: 6, treesPerRow: 4, direction: .down)
        let creekBlock = Block(fieldId: creek.id, name: "1", gridRow: 0, gridColumn: 0, rowCount: 10, treesPerRow: 8)

        let sep22 = calendar.date(on: DayKey(year: 2026, month: 9, day: 22), hour: 8, minute: 0)
        samShift = Shift(userId: sam.userId, farmId: farmId, start: sep22, end: sep22.addingTimeInterval(8 * 3600), rateCents: 1800)
        let oct18 = calendar.date(on: DayKey(year: 2026, month: 10, day: 18), hour: 8, minute: 0)
        earlier = Shift(userId: me.userId, farmId: farmId, start: oct18, end: oct18.addingTimeInterval(2 * 3600), rateCents: 2000)
        now = calendar.date(on: DayKey(year: 2026, month: 10, day: 19), hour: 9, minute: 0)

        snapshot = FarmSnapshot(farmId: farmId)
        var records: [SyncRecord] = [.farm(farm), .season(season), .member(me), .member(sam), .field(north), .field(creek),
                                     .block(block1), .block(block2), .block(block3), .block(creekBlock), .shift(samShift), .shift(earlier)]
        for row in 0..<2 {
            for position in 0..<12 {
                records.append(.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: block1.id, row: row, position: position),
                                                  shiftId: samShift.id, userId: sam.userId, markedAt: sep22.addingTimeInterval(3600))))
            }
        }
        for position in 0..<12 {
            records.append(.treeMark(TreeMark(seasonId: season.id, tree: TreeRef(blockId: block1.id, row: 2, position: position),
                                              shiftId: earlier.id, userId: me.userId, markedAt: oct18.addingTimeInterval(1800))))
        }
        if clockedIn {
            let shift = Shift(userId: me.userId, farmId: farmId, start: calendar.date(on: DayKey(year: 2026, month: 10, day: 19), hour: 7, minute: 0),
                              rateCents: 2000)
            open = shift
            records.append(.shift(shift))
        }
        for record in records { snapshot.apply(record) }
    }

    /// Hands the model whatever the session would see now.
    func sync() {
        model.update(snapshot: snapshot, farm: farm, me: me)
    }

    func tree(_ block: Block, row: Int, tree: Int) -> TreeRef {
        TreeRef(blockId: block.id, row: row - 1, position: tree - 1)
    }

    /// The middle of a tree on the map at the model's zoom.
    func point(_ block: Block, row: Int, tree: Int) -> CGPoint {
        let rect = model.layout.cellRect(self.tree(block, row: row, tree: tree))!
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    /// The middle of a row's number.
    func rowNumber(_ block: Block, row: Int) -> CGPoint {
        let rect = model.layout.rowHeaderRect(RowRef(blockId: block.id, row: row - 1))!
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    var savedMarks: [TreeMark] {
        saved.flatMap { $0 }.compactMap { if case .treeMark(let m) = $0 { m } else { nil } }
    }

    func live(_ tree: TreeRef) -> TreeMark? {
        snapshot.marks.values.first { $0.tree == tree && $0.isLive && $0.seasonId == season.id }
    }

    func note(on tree: TreeRef, by author: Member, body: String, flag: NoteFlag = .none, daysAgo: Double = 1) -> TreeNote {
        TreeNote(farmId: farm.id, tree: tree, authorId: author.userId, authorName: author.displayName, body: body, flag: flag,
                 createdAt: now.addingTimeInterval(-daysAgo * 86400))
    }
}
