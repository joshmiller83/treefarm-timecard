import Foundation

/// Status questions Siri can answer.
public enum FieldQuestion: Hashable, Sendable {
    case hours
    case trees
    case whereAmI
    case pace
    /// Pay is spoken on a locked phone only if the person turned that on, since others can hear it.
    case pay(locked: Bool, sayWhenLocked: Bool)
}

public enum FieldAnswers {
    public static func answer(_ question: FieldQuestion, state: FieldState, now: Date) -> String {
        let cal = state.calendar
        let shifts = state.liveShifts
        let today = shifts.filter { cal.isSameDay($0.start, now) }
        let index = state.index
        let count: (Shift) -> Int = { state.treeCount($0, index: index) }

        switch question {
        case .hours:
            let h = Hours.summary(shifts: shifts, now: now, calendar: cal)
            let week = "\(Fmt.spokenDuration(h.week)) this week."
            return h.today > 0 ? "\(Fmt.spokenDuration(h.today)) today, \(week)" : "You haven't worked yet today. \(week)"

        case .trees:
            let p = Pace.stats(today, now: now, treeCount: count)
            let trees = today.reduce(0) { $0 + count($1) }
            let head = trees > 0 ? "\(Fmt.plural(trees, "tree")) today, \(Speech.rate(p.treesPerHour)) an hour." : "No trees marked yet today."
            return [head, whereSentence(state, index: index, rows: 1)].compactMap { $0 }.joined(separator: " ")

        case .whereAmI:
            return whereSentence(state, index: index, rows: 3) ?? Speech.noField

        case .pace:
            let day = Pace.stats(today, now: now, treeCount: count)
            let season = Pace.stats(shifts, now: now, treeCount: count)
            let seasonText = season.trees > 0 ? "Your season pace is \(Speech.rate(season.treesPerHour)) an hour." : nil
            let head = day.trees > 0 ? "\(Speech.rate(day.treesPerHour)) trees an hour today." : "No trees marked yet today."
            return [head, seasonText].compactMap { $0 }.joined(separator: " ")

        case .pay(let locked, let sayWhenLocked):
            if locked && !sayWhenLocked { return "Unlock your phone to hear your pay." }
            let weekStart = cal.startOfWeek(containing: now)
            let weekEnd = cal.addDays(weekStart, 7)
            func pay(_ list: [Shift]) -> Int {
                list.reduce(0) { $0 + Hours.payCents(for: $1.workedTime(at: now), rateCents: $1.rateCents) }
            }
            let week = shifts.filter { $0.start >= weekStart && $0.start < weekEnd }
            return "\(Fmt.usd(cents: pay(today))) today, \(Fmt.usd(cents: pay(week))) this week."
        }
    }

    /// "You're on block 1, row 3. Next are rows 4 and 5." Nil when there's no field.
    static func whereSentence(_ state: FieldState, index: MarkIndex, rows: Int) -> String? {
        guard let field = state.currentField else { return nil }
        let next = state.nextRows(rows, index: index)
        guard let first = next.first, let block = state.block(first.blockId) else {
            return state.walker(for: field).blocks.isEmpty ? nil : "Every row in \(field.name) is shaped."
        }
        var s = "You're on \(Speech.place(first, block))."
        let rest = next.dropFirst()
        guard !rest.isEmpty else { return s }
        if rest.allSatisfy({ $0.blockId == first.blockId }) {
            let numbers = rest.map { String($0.row + 1) }
            s += numbers.count == 1 ? " Next is row \(numbers[0])." : " Next are rows \(Speech.list(numbers))."
        } else {
            let parts = rest.map { Speech.relative($0, from: first, blocks: state.block) }
            s += parts.count == 1 ? " Next is \(parts[0])." : " Next are \(Speech.list(parts))."
        }
        return s
    }
}
