import Foundation
@testable import TreeFarmKit

/// A small farm for field-action tests: one field "North" with block 1 (5 rows × 4 trees)
/// and block 2 (3 rows × 4 trees) side by side, Josh (worker) and Sam (worker), in Indiana time.
struct FieldFixture {
    let tz = TimeZone(identifier: "America/Indiana/Indianapolis")!
    let farm: Farm
    let season: Season
    let field: Field
    let block1: Block
    let block2: Block
    let josh: Member
    let sam: Member
    var state: FieldState

    /// Monday, Oct 19 2026, 9:00 AM in Indiana.
    let monday9: Date

    init() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        monday9 = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 9))!
        let farmId = UUID()
        season = Season(farmId: farmId, name: "2026", startedAt: monday9.addingTimeInterval(-30 * 86400), updatedAt: monday9)
        farm = Farm(id: farmId, name: "Dull's Tree Farm", timeZoneId: tz.identifier, weekStart: .monday, activeSeasonId: season.id, updatedAt: monday9)
        field = Field(farmId: farmId, name: "North", sortOrder: 0, updatedAt: monday9)
        block1 = Block(fieldId: field.id, name: "1", gridRow: 0, gridColumn: 0, rowCount: 5, treesPerRow: 4, updatedAt: monday9)
        block2 = Block(fieldId: field.id, name: "2", gridRow: 0, gridColumn: 1, rowCount: 3, treesPerRow: 4, updatedAt: monday9)
        josh = Member(userId: UUID(), farmId: farmId, displayName: "Josh", email: "josh@example.com", role: .worker, jobTitle: "Tree trimming", rateCents: 1500, updatedAt: monday9)
        sam = Member(userId: UUID(), farmId: farmId, displayName: "Sam", email: "", role: .worker, updatedAt: monday9)
        state = FieldState(farm: farm, me: josh, season: season, fields: [field], blocks: [block1, block2],
                           myShifts: [], marks: [], members: [josh, sam], position: nil)
    }

    func at(_ minutesAfter9: Double) -> Date { monday9.addingTimeInterval(minutesAfter9 * 60) }

    func row(_ block: Block, _ oneBasedRow: Int) -> RowRef { RowRef(blockId: block.id, row: oneBasedRow - 1) }

    /// A finished shift of Sam's that marked the given whole rows of a block.
    func samShaped(_ block: Block, rows: [Int], on date: Date) -> [TreeMark] {
        let shiftId = UUID()
        return rows.flatMap { r in
            (0..<block.treesPerRow).map { p in
                TreeMark(seasonId: season.id, tree: TreeRef(blockId: block.id, row: r - 1, position: p), shiftId: shiftId, userId: sam.userId, markedAt: date)
            }
        }
    }
}

extension FieldEngine {
    /// Run a command and fold its records into the state, like the app's store would.
    static func run(_ command: FieldCommand, _ state: inout FieldState, _ undo: inout UndoStack<UndoEntry>, at now: Date) -> Result<FieldOutcome, FieldFailure> {
        let result = perform(command, state: state, undo: &undo, now: now)
        if case .success(let outcome) = result { state = state.applying(outcome) }
        return result
    }
}

extension Result where Failure == FieldFailure {
    var speech: String {
        switch self {
        case .success(let o): (o as? FieldOutcome)?.speech ?? ""
        case .failure(let f): f.speech
        }
    }
}
