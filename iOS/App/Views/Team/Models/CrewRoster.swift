import Foundation
import TimeCardCore

/// One person on the crew list.
struct CrewRow: Identifiable, Equatable {
    enum Status: Equatable {
        case working(since: Date)
        case onBreak(BreakKind, since: Date)
        case off
    }

    var member: Member
    /// Worked this farm week (shifts that started in it), up to now for an open shift.
    var week: TimeInterval
    var today: TimeInterval
    /// Trees shaped on this week's shifts.
    var weekTrees: Int
    var status: Status
    var isYou: Bool
    /// When the shift they probably forgot to clock out of began: open longer than
    /// `Limits.forgotToClockOut` (16 hours, `Hours.forgotToClockOut`). Nil otherwise.
    var forgotSince: Date? = nil

    var id: UUID { member.userId }
    var isOnTheClock: Bool { status != .off }
    var forgotClockOut: Bool { forgotSince != nil }
}

/// The Team tab's crew list: everyone on the farm with this week's hours, from the
/// snapshot's shifts (admins pull everyone's). People who were removed are listed apart;
/// their hours stay on the farm.
struct CrewRoster: Equatable {
    var current: [CrewRow]
    var former: [CrewRow]
    /// Everyone's worked time this week, former crew included.
    var weekTotal: TimeInterval
    /// Current crew on the clock (working or on a break).
    var onTheClock: Int
    var weekStart: Date
    /// "Oct 19 – Oct 25, 2026"
    var weekLabel: String
    /// Current crew whose shift has been open so long they probably forgot to clock out.
    var forgotClockOut: [CrewRow] = []

    static func build(snapshot: FarmSnapshot, me: UUID?, now: Date, calendar: FarmCalendar) -> CrewRoster {
        let bounds = calendar.weekBounds(containing: now)
        let byUser = Dictionary(grouping: snapshot.shifts.values.filter(\.isLive), by: \.userId)
        let weekShiftIds = Set(snapshot.shifts.values.filter { $0.isLive && $0.start >= bounds[0] && $0.start < bounds[7] }.map(\.id))
        var treesByUser: [UUID: Int] = [:]
        for mark in snapshot.marks.values where mark.isLive && weekShiftIds.contains(mark.shiftId) {
            treesByUser[mark.userId, default: 0] += 1
        }

        var rows = snapshot.members.values.map { member -> CrewRow in
            let shifts = byUser[member.userId] ?? []
            let hours = Hours.summary(shifts: shifts, now: now, calendar: calendar)
            return CrewRow(member: member, week: hours.week, today: hours.today, weekTrees: treesByUser[member.userId] ?? 0,
                           status: status(of: shifts), isYou: member.userId == me, forgotSince: forgotSince(shifts, now: now))
        }
        rows.sort(by: byName)
        let current = rows.filter { $0.member.removedAt == nil }
        let former = rows.filter { $0.member.removedAt != nil }
        let total = Hours.summary(shifts: Array(snapshot.shifts.values), now: now, calendar: calendar).week
        return CrewRoster(current: current, former: former, weekTotal: total,
                          onTheClock: current.filter(\.isOnTheClock).count, weekStart: bounds[0],
                          weekLabel: Fmt.rangeLabel(start: bounds[0], endExclusive: bounds[7], calendar),
                          forgotClockOut: current.filter(\.forgotClockOut))
    }

    /// "Sam Ortiz may have forgotten to clock out.", "2 people may have …", or nil.
    var forgotSummary: String? {
        switch forgotClockOut.count {
        case 0: nil
        case 1: "\(forgotClockOut[0].member.displayName) may have forgotten to clock out."
        default: "\(forgotClockOut.count) people may have forgotten to clock out."
        }
    }

    /// One shift in a person's recent list.
    struct RecentShift: Identifiable, Equatable {
        var shift: Shift
        var worked: TimeInterval
        var trees: Int
        /// Still open after 16 hours (`Hours.forgotToClockOut`).
        var forgotClockOut = false
        var id: UUID { shift.id }
    }

    /// A person's latest shifts, newest first, with the trees shaped on each.
    static func recentShifts(of userId: UUID, snapshot: FarmSnapshot, now: Date, limit: Int) -> [RecentShift] {
        let shifts = snapshot.shifts.values
            .filter { $0.isLive && $0.userId == userId }
            .sorted { ($0.start, $0.id.uuidString) > ($1.start, $1.id.uuidString) }
            .prefix(limit)
        let ids = Set(shifts.map(\.id))
        var trees: [UUID: Int] = [:]
        for mark in snapshot.marks.values where mark.isLive && ids.contains(mark.shiftId) {
            trees[mark.shiftId, default: 0] += 1
        }
        return shifts.map {
            RecentShift(shift: $0, worked: $0.workedTime(at: now), trees: trees[$0.id] ?? 0,
                        forgotClockOut: Hours.forgotToClockOut($0, now: now))
        }
    }

    private static func status(of shifts: [Shift]) -> CrewRow.Status {
        guard let open = shifts.filter({ $0.isLive && $0.isOpen }).max(by: { $0.start < $1.start }) else { return .off }
        if let pause = open.openBreak { return .onBreak(pause.kind, since: pause.start) }
        return .working(since: open.start)
    }

    /// The start of the oldest open shift past `Limits.forgotToClockOut`.
    private static func forgotSince(_ shifts: [Shift], now: Date) -> Date? {
        shifts.filter { Hours.forgotToClockOut($0, now: now) }.map(\.start).min()
    }

    private static func byName(_ a: CrewRow, _ b: CrewRow) -> Bool {
        let order = a.member.displayName.localizedStandardCompare(b.member.displayName)
        if order != .orderedSame { return order == .orderedAscending }
        return a.member.userId.uuidString < b.member.userId.uuidString
    }
}
