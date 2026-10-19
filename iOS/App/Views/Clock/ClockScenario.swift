import Foundation
import TimeCardCore

/// Ready-made Clock tab states for UI tests and screenshots, on the demo farm only.
///
/// Launch with `-UITestInMemory -UITestClock <name>`:
/// - `working`: three earlier days of shifts and rows this week, and a shift on the clock
///   since a little over three hours ago with a short break, four rows marked and notes.
/// - `lunch`: the same, on lunch for the last 14 minutes.
/// - `stale`: still clocked in since 7:00 AM yesterday (forgot to clock out).
///
/// `-UITestScrollTo <card>` and `-UITestOpen <sheet>` (below) help take screenshots.
/// Live launches ignore all of these. Records go through `session.save` and rows through
/// `FieldActions`, the same paths the app uses.
@MainActor
enum ClockScenario: String {
    case working, lunch, stale

    static let argument = "-UITestClock"
    private static var applied = false

    /// `-UITestScrollTo <card>` scrolls the Clock tab to a card (status, now, trees, pace,
    /// notes, hours) for screenshots.
    static var scrollTarget: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UITestScrollTo"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `-UITestOpen settings|break|start` opens that sheet, for screenshots.
    static var sheetToOpen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-UITestOpen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var requested: ClockScenario? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: argument), i + 1 < args.count else { return nil }
        return ClockScenario(rawValue: args[i + 1])
    }

    /// Sets the scenario up once per launch. True when something changed.
    static func applyIfRequested(_ model: AppModel) async -> Bool {
        guard !applied, model.mode != .live, let scenario = requested else { return false }
        applied = true
        // The demo farm's layout arrives with the first pull.
        for _ in 0..<100 {
            if let state = model.actions.state(), state.season != nil, !state.blocks.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let state = model.actions.state() else { return false }
        scenario.apply(state: state, model: model, now: Date())
        return true
    }

    private func apply(state: FieldState, model: AppModel, now: Date) {
        guard let season = state.season, let field = state.currentField else { return }
        let cal = state.calendar
        let me = state.me
        let walker = state.walker(for: field)
        var open = walker.nextRows(from: nil, count: 40, index: state.index)[...]
        var records: [SyncRecord] = []

        func day(_ offset: Int) -> DayKey { cal.dayKey(cal.addDays(now, offset)) }
        func at(_ d: DayKey, _ h: Int, _ m: Int) -> Date { cal.date(on: d, hour: h, minute: m) }
        func shaped(_ count: Int, on shift: Shift) {
            for row in open.prefix(count) {
                guard let block = walker.block(row.blockId) else { continue }
                for position in 0..<block.treesPerRow {
                    let tree = TreeRef(blockId: row.blockId, row: row.row, position: position)
                    let when = shift.start.addingTimeInterval(TimeInterval(records.count % 400) * 50)
                    records.append(.treeMark(TreeMark(seasonId: season.id, tree: tree, shiftId: shift.id, userId: me.userId, markedAt: when)))
                }
            }
            open = open.dropFirst(count)
        }
        func past(_ offset: Int, from: (Int, Int), to: (Int, Int), rows: Int, extra: [Break] = [], notes: String = "") {
            let d = day(offset)
            let lunch = Break(kind: .lunch, start: at(d, 12, 0), end: at(d, 12, 30))
            let shift = Shift(userId: me.userId, farmId: state.farm.id, start: at(d, from.0, from.1), end: at(d, to.0, to.1),
                              breaks: (extra + [lunch]).sorted { $0.start < $1.start }, notes: notes, rateCents: me.rateCents,
                              updatedAt: at(d, to.0, to.1))
            records.append(.shift(shift))
            shaped(rows, on: shift)
        }

        switch self {
        case .working, .lunch:
            past(-3, from: (7, 0), to: (15, 30), rows: 6)
            past(-2, from: (7, 15), to: (15, 45), rows: 8, notes: "Rain until 9. Started on block 2.")
            past(-1, from: (6, 50), to: (14, 20), rows: 7,
                 extra: [Break(kind: .break, start: at(day(-1), 10, 0), end: at(day(-1), 10, 12), reason: "Sharpening")])
            let start = max(cal.startOfDay(now).addingTimeInterval(60), now.addingTimeInterval(-(3 * 3600 + 14 * 60))).roundedToMillisecond
            var breaks: [Break] = []
            if now.timeIntervalSince(start) > 2 * 3600 {
                let b = start.addingTimeInterval(70 * 60)
                breaks.append(Break(kind: .break, start: b, end: b.addingTimeInterval(12 * 60), reason: "Fuel run"))
            }
            let today = Shift(userId: me.userId, farmId: state.farm.id, start: start, breaks: breaks,
                              notes: "Picked up after Sam’s rows. Sap on the shears again.", rateCents: me.rateCents, updatedAt: start)
            records.append(.shift(today))
            try? model.session.save(records)
            for _ in 0..<4 { model.actions.perform(.markNextRow) }
            if self == .lunch, var shift = model.session.snapshot.shifts[today.id] {
                let lunch = max(start, now.addingTimeInterval(-14 * 60)).roundedToMillisecond
                shift.breaks.append(Break(kind: .lunch, start: lunch))
                shift.updatedAt = now.roundedToMillisecond
                try? model.session.save([.shift(shift)])
                model.actions.publishLiveSnapshot()
            }

        case .stale:
            past(-3, from: (7, 0), to: (15, 30), rows: 6)
            past(-2, from: (7, 15), to: (15, 45), rows: 8)
            let start = at(day(-1), 7, 0)
            records.append(.shift(Shift(userId: me.userId, farmId: state.farm.id, start: start, rateCents: me.rateCents, updatedAt: start)))
            try? model.session.save(records)
            model.actions.publishLiveSnapshot()
        }
    }
}
