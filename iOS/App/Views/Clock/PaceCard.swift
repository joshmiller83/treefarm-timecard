import Foundation
import TimeCardCore

/// The pace card: trees an hour today, this week and this season, as on the web time card.
/// Numbers come from TreeFarmKit's `Pace`; the headline is what Siri says for "What's my pace?".
/// Only shifts with trees marked count, so an unmarked shift doesn't drag the pace down.
struct PaceCard: Equatable {
    struct Column: Equatable, Identifiable {
        var title: String
        /// "26.7", or "–" with no trees.
        var rate: String
        /// "212 trees"
        var trees: String
        /// "2:15/tree"
        var each: String
        /// "$0.62/tree", nil while pay is hidden.
        var payEach: String?
        /// Today, while clocked in with trees marked.
        var isNow: Bool

        var id: String { title }
    }

    var headline: String
    var columns: [Column]
    var notes: [String]

    /// Whether any of your shifts has trees marked this season: cheap, for deciding to show the card.
    static func hasTrees(state: FieldState, index: MarkIndex) -> Bool {
        state.liveShifts.contains { state.treeCount($0, index: index) > 0 }
    }

    /// Nil until a tree has been marked this season. Pass the state's `index` when you have it.
    init?(state: FieldState, index: MarkIndex? = nil, now: Date, showPay: Bool) {
        let cal = state.calendar
        let index = index ?? state.index
        let count: (Shift) -> Int = { state.treeCount($0, index: index) }
        let shifts = state.liveShifts
        let season = Pace.stats(shifts, now: now, treeCount: count)
        guard season.trees > 0 else { return nil }

        let bounds = cal.weekBounds(containing: now)
        let todayList = shifts.filter { cal.isSameDay($0.start, now) }
        let weekList = shifts.filter { $0.start >= bounds[0] && $0.start < bounds[7] }
        let today = Pace.stats(todayList, now: now, treeCount: count)
        let clockedIn = state.openShift != nil

        func column(_ title: String, _ p: PaceStats, now isNow: Bool) -> Column {
            Column(title: title,
                   rate: p.trees > 0 ? Pace.rateText(p.treesPerHour) : "–",
                   trees: Fmt.plural(p.trees, "tree"),
                   each: p.trees > 0 ? Pace.eachText(minutes: p.minutesPerTree) + "/tree" : "–",
                   payEach: showPay && p.trees > 0 ? Fmt.usd(cents: p.payCentsPerTree) + "/tree" : nil,
                   isNow: isNow)
        }

        headline = FieldAnswers.answer(.pace, state: state, now: now)
        columns = [
            column("Today", today, now: clockedIn && today.trees > 0),
            column("This week", Pace.stats(weekList, now: now, treeCount: count), now: false),
            column("Season", season, now: false),
        ]

        var notes: [String] = []
        let others = Pace.stats(shifts.filter { !cal.isSameDay($0.start, now) }, now: now, treeCount: count)
        if today.trees > 0, others.trees > 0, others.treesPerHour > 0, today.worked >= 30 * 60 {
            let diff = (today.treesPerHour - others.treesPerHour) / others.treesPerHour * 100
            notes.append(abs(diff) < 3
                ? "Today you’re right on your usual pace."
                : "Today you’re \(Int(abs(diff).rounded()))% \(diff > 0 ? "faster" : "slower") than your other days.")
        }
        let treeDays = Set(shifts.filter { count($0) > 0 }.map { cal.dayKey($0.start) })
        if treeDays.count > 1, let best = Pace.bestDay(shifts, now: now, calendar: cal, treeCount: count) {
            let day = Fmt.day(cal.date(on: best.day, hour: 12, minute: 0), cal)
            notes.append("Best day: \(day), \(Pace.rateText(best.treesPerHour)) trees an hour (\(Fmt.plural(best.trees, "tree"))).")
        }
        if let field = state.currentField {
            let progress = state.walker(for: field).progress(index: index)
            let left = progress.total - progress.shaped
            if progress.total > 0 && left <= 0 {
                notes.append("Every tree in \(field.name) is shaped.")
            } else if left > 0, let hours = Pace.hoursLeft(treesLeft: left, treesPerHour: season.treesPerHour) {
                var line = "\(Fmt.plural(left, "tree")) left in \(field.name). At your season pace that’s about \(Pace.hoursWords(hours)) of work"
                if showPay && state.me.rateCents > 0 {
                    let dollars = Int((hours * Double(state.me.rateCents) / 100).rounded())
                    line += ", or about $\(Fmt.count(dollars))"
                }
                notes.append(line + ".")
            }
        }
        self.notes = notes
    }
}
