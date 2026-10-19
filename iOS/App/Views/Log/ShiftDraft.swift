import Foundation
import TimeCardCore

/// A time of day on the farm's clock, as the editor's pickers set it.
///
/// `pinned` is the exact instant the time was loaded from. It's kept while the person leaves
/// the time alone, so saving an untouched shift never moves it: its seconds stay, and so does
/// the second 1:30 on a fall-back night. Setting the time drops it.
///
/// `dayOffset` is how many days after the shift's start day the time falls on. A loaded time
/// keeps the day it was on (a shift left open since yesterday keeps today's break on today,
/// and a 24-hour shift ends on the next day), and keeps it relative to the start day when the
/// date changes. A time the person sets has none, and follows `ShiftDraft`'s rule instead.
struct WallClock: Hashable {
    var hour: Int
    var minute: Int
    var pinned: Date?
    var dayOffset: Int?

    init(hour: Int, minute: Int, pinned: Date? = nil, dayOffset: Int? = nil) {
        self.hour = hour
        self.minute = minute
        self.pinned = pinned
        self.dayOffset = dayOffset
    }

    /// The time `date` shows on the farm's clock, pinned to `date`.
    init(_ date: Date, _ calendar: FarmCalendar) {
        let c = calendar.calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0, pinned: date)
    }

    /// The same, also remembering how many days after `startDay` it falls on.
    init(_ date: Date, _ calendar: FarmCalendar, startDay: DayKey) {
        self.init(date, calendar)
        dayOffset = ShiftDraft.days(from: startDay, to: calendar.dayKey(date), calendar)
    }

    var minutesIntoDay: Int { hour * 60 + minute }

    /// The same time of day, unpinned and with no day of its own (what a picker hands back).
    var unpinned: WallClock { WallClock(hour: hour, minute: minute) }

    /// This time on `day` on the farm's clock.
    func date(on day: DayKey, _ calendar: FarmCalendar) -> Date {
        if let pinned, calendar.dayKey(pinned) == day, WallClock(pinned, calendar).minutesIntoDay == minutesIntoDay {
            return pinned
        }
        return calendar.date(on: day, hour: hour, minute: minute)
    }

    /// `minutes` past midnight, wrapped into one day.
    static func minutes(_ minutes: Int) -> WallClock {
        let m = ((minutes % 1440) + 1440) % 1440
        return WallClock(hour: m / 60, minute: m % 60)
    }
}

/// One break as the editor holds it.
struct BreakDraft: Identifiable, Hashable {
    var id: UUID
    var kind: BreakKind
    var start: WallClock
    /// Nil while the break is still running (only on a shift that's still open).
    var end: WallClock?
    var reason: String

    init(id: UUID = UUID(), kind: BreakKind, start: WallClock, end: WallClock?, reason: String = "") {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.reason = reason
    }
}

/// A shift as the editor holds it: a day, times of day and breaks, the way a person thinks
/// about a time card. A time the person sets that's earlier in the day than clock-in belongs
/// to the next day, so a shift (or a break) can run past midnight; a time loaded from the
/// shift keeps its own day (`WallClock.dayOffset`). `shift(...)` turns it back into a `Shift`
/// for `ShiftRules.validate` and the store.
struct ShiftDraft: Hashable {
    var id: UUID
    var userId: UUID
    var farmId: UUID
    var rateCents: Int
    /// The day the shift starts on (it counts toward this day).
    var day: DayKey
    var start: WallClock
    /// Nil = still on the clock.
    var end: WallClock?
    var breaks: [BreakDraft]
    var notes: String
    /// The shift as it was loaded; nil when adding one.
    var original: Shift?

    var isNew: Bool { original == nil }

    /// Loads a saved shift.
    init(shift: Shift, calendar: FarmCalendar) {
        id = shift.id
        userId = shift.userId
        farmId = shift.farmId
        rateCents = shift.rateCents
        let day = calendar.dayKey(shift.start)
        self.day = day
        start = WallClock(shift.start, calendar)
        end = shift.end.map { WallClock($0, calendar, startDay: day) }
        breaks = shift.breaks.map { b in
            BreakDraft(id: b.id, kind: b.kind, start: WallClock(b.start, calendar, startDay: day),
                       end: b.end.map { WallClock($0, calendar, startDay: day) }, reason: b.reason)
        }
        notes = shift.notes
        original = shift
    }

    init(id: UUID = UUID(), userId: UUID, farmId: UUID, rateCents: Int, day: DayKey, start: WallClock, end: WallClock?,
         breaks: [BreakDraft] = [], notes: String = "") {
        self.id = id
        self.userId = userId
        self.farmId = farmId
        self.rateCents = rateCents
        self.day = day
        self.start = start
        self.end = end
        self.breaks = breaks
        self.notes = notes
        self.original = nil
    }

    /// A new shift to fill in. It takes the clock times of the person's latest finished shift
    /// (crews keep regular hours), or 7:00 AM to 3:30 PM, on the latest day those times are
    /// already over: today after the shift would have ended, else yesterday.
    static func newShift(userId: UUID, farmId: UUID, rateCents: Int, mine: [Shift], now: Date, calendar: FarmCalendar) -> ShiftDraft {
        let latest = mine.filter { $0.isLive && $0.userId == userId && !$0.isOpen }.max { $0.start < $1.start }
        let start = latest.map { WallClock($0.start, calendar).unpinned } ?? WallClock(hour: 7, minute: 0)
        let end = latest.flatMap { $0.end }.map { WallClock($0, calendar).unpinned } ?? WallClock(hour: 15, minute: 30)
        var draft = ShiftDraft(userId: userId, farmId: farmId, rateCents: rateCents, day: calendar.dayKey(now), start: start, end: end)
        if let resolvedEnd = draft.endDate(calendar), resolvedEnd > now {
            draft.day = calendar.dayKey(calendar.addDays(calendar.startOfDay(now), -1))
        }
        return draft
    }

    /// A clock-out for a shift left open too long: the last sign of work on it (a break, a
    /// tree mark), or 8 hours after clock-in when there's nothing to go on; never more than
    /// `Limits.maxShift` after clock-in, and never after now.
    static func suggestedEnd(for shift: Shift, lastMark: Date?, now: Date) -> Date {
        let signs = shift.breaks.flatMap { [$0.start, $0.end].compactMap { $0 } } + [lastMark].compactMap { $0 }
        let last = signs.filter { $0 > shift.start }.max() ?? shift.start.addingTimeInterval(8 * 3600)
        return min(last, shift.start.addingTimeInterval(Limits.maxShift), now)
    }

    // MARK: Turning times into instants

    /// How many days after the start day a time falls on. A loaded time keeps its own day; a
    /// time the person set is the next day when it's earlier than clock-in. A break's end set
    /// by the person goes with its start, so a break taken today on a shift left open since
    /// yesterday ends today too.
    func dayOffset(of clock: WallClock, breakStart: WallClock? = nil) -> Int {
        if let offset = clock.dayOffset { return offset }
        let rule = clock.minutesIntoDay < start.minutesIntoDay ? 1 : 0
        if let breakStart, let startOffset = breakStart.dayOffset {
            let startRule = breakStart.minutesIntoDay < start.minutesIntoDay ? 1 : 0
            return startOffset + max(0, rule - startRule)
        }
        return rule
    }

    /// The day a time of day falls on.
    func day(for clock: WallClock, breakStart: WallClock? = nil, _ calendar: FarmCalendar) -> DayKey {
        Self.day(day, plus: dayOffset(of: clock, breakStart: breakStart), calendar)
    }

    func startDate(_ calendar: FarmCalendar) -> Date {
        start.date(on: day, calendar).roundedToMillisecond
    }

    func endDate(_ calendar: FarmCalendar) -> Date? {
        end.map { date($0, calendar) }
    }

    /// The instant a time stands for. Pass a break's start when `clock` is that break's end.
    func date(_ clock: WallClock, breakStart: WallClock? = nil, _ calendar: FarmCalendar) -> Date {
        clock.date(on: day(for: clock, breakStart: breakStart, calendar), calendar).roundedToMillisecond
    }

    /// Clock-out lands on a later day than clock-in.
    var endsNextDay: Bool {
        guard let end else { return false }
        return dayOffset(of: end) > 0
    }

    /// A time of day lands on a later day than clock-in.
    func isNextDay(_ clock: WallClock, breakStart: WallClock? = nil) -> Bool {
        dayOffset(of: clock, breakStart: breakStart) > 0
    }

    /// The small tag beside a time that isn't on the start day: "Next day", or the day itself
    /// ("Tue, Oct 20") further out.
    func dayTag(_ clock: WallClock, breakStart: WallClock? = nil, _ calendar: FarmCalendar) -> String? {
        switch dayOffset(of: clock, breakStart: breakStart) {
        case 0: nil
        case 1: "Next day"
        default: Fmt.day(calendar.date(on: day(for: clock, breakStart: breakStart, calendar), hour: 12, minute: 0), calendar)
        }
    }

    /// The shift to validate and save, stamped `updatedAt = now`. Breaks stay in the editor's
    /// order so `ShiftRules` messages ("Break 2 …") match what the person sees.
    func shift(calendar: FarmCalendar, now: Date) -> Shift {
        var shift = original ?? Shift(id: id, userId: userId, farmId: farmId, start: startDate(calendar), rateCents: rateCents)
        shift.start = startDate(calendar)
        shift.end = endDate(calendar)
        shift.breaks = breaks.map { b in
            Break(id: b.id, kind: b.kind, start: date(b.start, calendar), end: b.end.map { date($0, breakStart: b.start, calendar) }, reason: b.reason)
        }
        shift.notes = notes
        // After the version it replaces, even if this phone's clock is behind the last writer's.
        shift.updatedAt = original.map { RecordMetadata.stamp(now, after: $0.updatedAt) } ?? now.roundedToMillisecond
        return shift
    }

    /// Worked time and break time as the draft stands (an open shift runs to `now`).
    func totals(calendar: FarmCalendar, now: Date) -> (worked: TimeInterval, breaks: TimeInterval) {
        let s = shift(calendar: calendar, now: now)
        return (s.workedTime(at: now), s.breakTime(at: now))
    }

    // MARK: Adding a break

    /// A sensible next break that fits inside the shift: lunch at noon for half an hour when
    /// there's no lunch yet and noon fits, else a break in the middle of the free time left.
    func suggestedBreak(calendar: FarmCalendar, now: Date) -> BreakDraft {
        let startMinute = start.minutesIntoDay
        // Minutes from clock-in, so a shift past midnight is one straight line.
        func offset(_ clock: WallClock) -> Int { (clock.minutesIntoDay - startMinute + 1440) % 1440 }
        let shiftLength: Int = {
            if let end { let n = offset(end); return n == 0 ? 0 : n }
            let open = Int(now.timeIntervalSince(startDate(calendar)) / 60)
            return max(0, min(open, 1439))
        }()
        let hasLunch = breaks.contains { $0.kind == .lunch }
        let kind: BreakKind = hasLunch ? .break : .lunch
        let length = kind == .lunch ? 30 : 15

        // Minutes already taken by breaks, as half-open spans from clock-in.
        let taken = breaks.map { b -> (from: Int, to: Int) in
            let from = offset(b.start)
            let to = b.end.map { max(from, offset($0)) } ?? shiftLength
            return (from, to)
        }
        func fits(_ from: Int, _ len: Int) -> Bool {
            from >= 0 && from + len <= shiftLength && !taken.contains { from < $0.to && $0.from < from + len }
        }
        if kind == .lunch {
            let noon = offset(WallClock(hour: 12, minute: 0))
            if fits(noon, length) {
                return BreakDraft(kind: .lunch, start: .minutes(startMinute + noon), end: .minutes(startMinute + noon + length))
            }
        }
        // Otherwise the middle of the longest free stretch, on a five-minute mark.
        var free: [(Int, Int)] = []
        var cursor = 0
        for span in taken.sorted(by: { $0.from < $1.from }) {
            if span.from > cursor { free.append((cursor, span.from)) }
            cursor = max(cursor, span.to)
        }
        if shiftLength > cursor { free.append((cursor, shiftLength)) }
        guard let gap = free.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }), gap.1 - gap.0 > 0 else {
            return BreakDraft(kind: kind, start: .minutes(startMinute), end: .minutes(startMinute + length))
        }
        let len = min(length, gap.1 - gap.0)
        var from = gap.0 + (gap.1 - gap.0 - len) / 2
        from = max(gap.0, (from / 5) * 5)
        return BreakDraft(kind: kind, start: .minutes(startMinute + from), end: .minutes(startMinute + from + len))
    }

    // MARK: Days

    static func day(_ day: DayKey, plus days: Int, _ calendar: FarmCalendar) -> DayKey {
        days == 0 ? day : calendar.dayKey(calendar.addDays(calendar.date(on: day, hour: 12, minute: 0), days))
    }

    /// Calendar days from one day to another (negative when `to` is earlier).
    static func days(from: DayKey, to: DayKey, _ calendar: FarmCalendar) -> Int {
        calendar.calendar.dateComponents([.day], from: calendar.startOfDay(from), to: calendar.startOfDay(to)).day ?? 0
    }

    // MARK: Changes made elsewhere

    /// The person's edits (`mine`, which opened as `base`) put on top of the shift as it's
    /// stored now (`theirs`), part by part: when (date and clock-in), clock-out, breaks and
    /// notes. A part the person left alone takes the stored value, so a break started from the
    /// lock screen or a clock-out from Siri survives the save. A part changed on both sides
    /// takes the stored value and comes back as a conflict, so the person can look again.
    static func rebase(_ mine: ShiftDraft, base: ShiftDraft, onto theirs: ShiftDraft) -> (draft: ShiftDraft, conflict: Bool) {
        var merged = theirs
        var conflict = false
        func pick<T: Equatable>(_ path: WritableKeyPath<ShiftDraft, T>) {
            let mineChanged = mine[keyPath: path] != base[keyPath: path]
            let theirsChanged = theirs[keyPath: path] != base[keyPath: path]
            guard mineChanged else { return }
            if !theirsChanged {
                merged[keyPath: path] = mine[keyPath: path]
            } else if mine[keyPath: path] != theirs[keyPath: path] {
                conflict = true
            }
        }
        pick(\.when)
        pick(\.end)
        pick(\.breaks)
        pick(\.notes)
        return (merged, conflict)
    }

    /// The date and clock-in together: changing the date moves clock-in.
    private var when: When {
        get { When(day: day, start: start) }
        set { day = newValue.day; start = newValue.start }
    }

    private struct When: Equatable {
        var day: DayKey
        var start: WallClock
    }
}
