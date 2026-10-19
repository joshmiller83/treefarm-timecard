import Foundation
import TimeCardCore

/// What a status question asks about.
enum StatusTopic: String, CaseIterable, Sendable {
    /// Hours, trees and where you are, all at once.
    case summary
    case hours
    case trees
    case whereAmI
    case pace
    case pay
}

/// The numbers behind the small card Siri shows under a status answer. Every number comes
/// from TreeFarmKit (`Hours`, `Pace`, `FieldWalker`), so the card and the spoken answer agree.
struct DayCard: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case working, lunch, onBreak, off
    }

    /// A row on the map: "Block 2", row 15 (counting from 1).
    struct Spot: Equatable, Sendable, Hashable {
        var block: String
        var row: Int
    }

    /// What "worked" and "trees" count: today, or the open shift when it began on an earlier
    /// day (past midnight), as the Clock tab's "worked this shift".
    enum Span: Equatable, Sendable {
        case today, thisShift

        var words: String { self == .today ? "today" : "this shift" }
    }

    var topic: StatusTopic
    var phase: Phase
    var fieldName: String
    var span: Span = .today
    var worked: TimeInterval
    var workedWeek: TimeInterval
    var trees: Int
    var treesPerHour: Double
    var seasonTreesPerHour: Double
    /// The row you're on, and the two after it.
    var here: Spot?
    var next: [Spot]
    var fieldShaped: Int
    var fieldTotal: Int
    /// Pay today and this week, only when pay was asked about and may show.
    var pay: Pay?
    /// Pay was asked about, but the phone is locked and "Say pay out loud when locked" is off.
    var payHidden: Bool

    struct Pay: Equatable, Sendable {
        var todayCents: Int
        var weekCents: Int
    }

    func with(topic: StatusTopic) -> DayCard {
        var copy = self
        copy.topic = topic
        return copy
    }

    var fieldProgress: Double {
        fieldTotal > 0 ? min(1, Double(fieldShaped) / Double(fieldTotal)) : 0
    }

    static func build(state: FieldState, now: Date, topic: StatusTopic, showPay: Bool = false, payHidden: Bool = false) -> DayCard {
        let cal = state.calendar
        let shifts = state.liveShifts
        let index = state.index
        let count: (Shift) -> Int = { state.treeCount($0, index: index) }
        let today = shifts.filter { cal.isSameDay($0.start, now) }
        let hours = Hours.summary(shifts: shifts, now: now, calendar: cal)
        let stale = state.openShift.flatMap { Hours.isStale($0, now: now, calendar: cal) ? $0 : nil }
        let day = Pace.stats(stale.map { [$0] } ?? today, now: now, treeCount: count)
        let season = Pace.stats(shifts, now: now, treeCount: count)

        let phase: Phase = switch state.openShift.map({ $0.openBreak?.kind }) {
        case nil: .off
        case .some(nil): .working
        case .some(.lunch?): .lunch
        case .some(.break?): .onBreak
        }

        let spots = state.nextRows(3, index: index).compactMap { row -> Spot? in
            state.block(row.blockId).map { Spot(block: Speech.blockTitle($0), row: row.row + 1) }
        }
        var pay: Pay?
        if showPay {
            // As FieldAnswers adds it up for "How much have I made": each shift's own rate,
            // shifts counted by the day and week they started in.
            let bounds = hours.weekBounds
            func cents(_ list: [Shift]) -> Int {
                list.reduce(0) { $0 + Hours.payCents(for: $1.workedTime(at: now), rateCents: $1.rateCents) }
            }
            pay = Pay(todayCents: cents(today), weekCents: cents(shifts.filter { $0.start >= bounds[0] && $0.start < bounds[7] }))
        }
        var shaped = 0, total = 0
        if let field = state.currentField {
            (shaped, total) = state.walker(for: field).progress(index: index)
        }
        return DayCard(
            topic: topic,
            phase: phase,
            fieldName: state.currentField?.name ?? "",
            span: stale == nil ? .today : .thisShift,
            worked: Hours.bigClock(shifts: shifts, now: now, calendar: cal),
            workedWeek: hours.week,
            trees: day.trees,
            treesPerHour: day.treesPerHour,
            seasonTreesPerHour: season.treesPerHour,
            here: spots.first,
            next: Array(spots.dropFirst()),
            fieldShaped: shaped,
            fieldTotal: total,
            pay: pay,
            payHidden: payHidden)
    }
}
