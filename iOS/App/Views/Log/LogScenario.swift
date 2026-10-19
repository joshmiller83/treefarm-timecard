import Foundation
import TimeCardCore

/// Ready-made Log and Report states for UI tests and screenshots, on the demo farm only.
///
/// Launch with `-UITestInMemory -UITestLog <name>`:
/// - `weeks`: the demo admin (Alex) worked last week Monday to Friday and three days the week
///   before, one of them a night shift past midnight, with lunches, a fuel-run break, notes
///   and rows of trees; Sam worked four days last week. On days after the first of this
///   week, Alex also has a shift on the week's first day.
/// - `empty`: nothing added (the demo farm has no shifts for Alex).
///
/// `-UITestOpenShift last` opens the editor on Alex's latest shift, and `-UITestOpenShift new`
/// opens "Add a Shift", for screenshots. Live launches ignore all of these. Records go
/// through `session.save`, the path the app uses.
@MainActor
enum LogScenario: String {
    case weeks, empty

    static let argument = "-UITestLog"
    private static var applied = false

    static var requested: LogScenario? {
        value(after: argument).flatMap(LogScenario.init(rawValue:))
    }

    /// `-UITestOpenShift last|new`, handed out once per launch.
    static func takeEditorRequest(_ model: AppModel) -> String? {
        guard model.mode != .live, !editorTaken, let which = value(after: "-UITestOpenShift") else { return nil }
        editorTaken = true
        return which
    }
    private static var editorTaken = false

    /// `-UITestReportPeriod lastWeek|thisMonth|…` picks the Report's range at launch.
    static var reportPeriod: String? {
        AppModel.shared.mode == .live ? nil : value(after: "-UITestReportPeriod")
    }

    private static func value(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Sets the scenario up once per launch.
    static func applyIfRequested(_ model: AppModel) async {
        guard !applied, model.mode != .live, let scenario = requested else { return }
        applied = true
        // The demo farm's layout arrives with the first pull.
        for _ in 0..<100 {
            if let state = model.actions.state(), state.season != nil, !state.blocks.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let state = model.actions.state() else { return }
        let records = scenario.records(state: state, now: Date())
        if !records.isEmpty { try? model.save(records) }
    }

    func records(state: FieldState, now: Date) -> [SyncRecord] {
        guard self == .weeks, let season = state.season, let field = state.currentField else { return [] }
        let cal = state.calendar
        let walker = state.walker(for: field)
        var open = walker.nextRows(from: nil, count: 60, index: state.index)[...]
        var records: [SyncRecord] = []
        let me = state.me
        let sam = state.members.first { $0.userId != me.userId && $0.role == .worker }

        let thisWeek = cal.startOfWeek(containing: now)
        func day(_ weekOffset: Int, _ weekday: Int) -> DayKey {
            cal.dayKey(cal.addDays(cal.date(on: cal.dayKey(thisWeek), hour: 12, minute: 0), weekOffset * 7 + weekday))
        }
        func at(_ d: DayKey, _ h: Int, _ m: Int) -> Date { cal.date(on: d, hour: h, minute: m) }

        func shaped(rows: Int, partial: Int = 0, on shift: Shift, by userId: UUID) {
            var minute = 0.0
            for row in open.prefix(rows) {
                guard let block = walker.block(row.blockId) else { continue }
                for position in 0..<block.treesPerRow {
                    let tree = TreeRef(blockId: row.blockId, row: row.row, position: position)
                    records.append(.treeMark(TreeMark(seasonId: season.id, tree: tree, shiftId: shift.id, userId: userId,
                                                      markedAt: shift.start.addingTimeInterval(1800 + minute * 60))))
                    minute += 1.5
                }
            }
            open = open.dropFirst(rows)
            if partial > 0, let row = open.first, let block = walker.block(row.blockId) {
                for position in 0..<min(partial, block.treesPerRow) {
                    let tree = TreeRef(blockId: row.blockId, row: row.row, position: position)
                    records.append(.treeMark(TreeMark(seasonId: season.id, tree: tree, shiftId: shift.id, userId: userId,
                                                      markedAt: shift.start.addingTimeInterval(1800 + minute * 60))))
                    minute += 1.5
                }
                open = open.dropFirst()
            }
        }

        func add(_ member: Member, _ d: DayKey, from: (Int, Int), to: (Int, Int), nextDay: Bool = false,
                 lunch: Bool = true, fuelRun: Bool = false, notes: String = "", rows: Int = 0, partial: Int = 0) {
            let start = at(d, from.0, from.1)
            let endDay = nextDay ? cal.dayKey(cal.addDays(at(d, 12, 0), 1)) : d
            let end = at(endDay, to.0, to.1)
            guard end <= now else { return }
            var breaks: [Break] = []
            if fuelRun { breaks.append(Break(kind: .break, start: at(d, 9, 40), end: at(d, 9, 52), reason: "Fuel run")) }
            if lunch { breaks.append(Break(kind: .lunch, start: at(d, 12, 0), end: at(d, 12, 30))) }
            let shift = Shift(userId: member.userId, farmId: state.farm.id, start: start, end: end, breaks: breaks, notes: notes,
                              rateCents: member.rateCents, updatedAt: end)
            records.append(.shift(shift))
            if rows > 0 || partial > 0 { shaped(rows: rows, partial: partial, on: shift, by: member.userId) }
        }

        // Two weeks ago: three days, the last a night shift loading trucks.
        add(me, day(-2, 1), from: (7, 0), to: (15, 30), rows: 3)
        add(me, day(-2, 2), from: (7, 5), to: (15, 45), fuelRun: true, rows: 3)
        add(me, day(-2, 4), from: (18, 0), to: (1, 30), nextDay: true, lunch: false,
            notes: "Loaded trucks for the lot sale.")
        // Last week, Monday to Friday.
        add(me, day(-1, 0), from: (7, 2), to: (15, 31), rows: 3, partial: 4)
        add(me, day(-1, 1), from: (6, 55), to: (15, 30), fuelRun: true,
            notes: "Finished the last rows of block 1 before the rain. Two trees in row 12 need a second look.", rows: 4)
        add(me, day(-1, 2), from: (7, 0), to: (16, 10), rows: 4)
        add(me, day(-1, 3), from: (7, 15), to: (15, 0), notes: "Shears sharpened at lunch.", rows: 3)
        add(me, day(-1, 4), from: (7, 0), to: (12, 0), lunch: false, rows: 2)
        if let sam {
            for (weekday, rows) in [(0, 2), (1, 3), (2, 2), (3, 3)] {
                add(sam, day(-1, weekday), from: (7, 30), to: (16, 0), rows: rows)
            }
        }
        // This week, when its first day is already over.
        if cal.dayKey(now) > cal.dayKey(thisWeek) {
            add(me, day(0, 0), from: (7, 0), to: (15, 30), rows: 3)
        }
        return records
    }
}
