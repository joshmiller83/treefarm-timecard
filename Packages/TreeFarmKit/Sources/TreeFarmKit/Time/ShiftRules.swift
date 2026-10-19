import Foundation

/// Why a shift can't be saved. `message` is the sentence a person sees or Siri says.
public enum ShiftRuleError: Error, Equatable, Sendable {
    case endNotAfterStart
    case startInFuture
    case endInFuture
    /// A closed shift longer than `Limits.maxShift`.
    case tooLong
    /// The shift is open but the same person already has another open shift.
    case alreadyClockedIn
    /// Clashes with another of the person's shifts. The strings are ready to show: "Mon, Oct 12", "7:00 AM", "3:30 PM" or "now".
    case overlaps(day: String, from: String, to: String)
    /// Breaks are numbered from 1 in the order the shift lists them (the editor's order).
    case breakNeedsEnd(Int)
    case breakEndNotAfterStart(Int)
    case breakOutsideShift(Int)
    case onlyLatestBreakOpen
    case breaksOverlap
    /// Changing the open shift's start ("Change start time" / "I started at 7:30").
    case newStartInFuture
    /// The first break's start, ready to show: "12:01 PM".
    case newStartAfterFirstBreak(String)
    case newStartOverlaps(from: String, to: String)

    public var message: String {
        switch self {
        case .endNotAfterStart:
            "Clock out has to be after clock in."
        case .startInFuture:
            "Clock in can’t be later than right now."
        case .endInFuture:
            "Clock out can’t be later than right now."
        case .tooLong:
            "A shift can’t be longer than 24 hours. Check the clock-in and clock-out times."
        case .alreadyClockedIn:
            "You’re already clocked in on another shift. Add a clock-out time to this one."
        case .overlaps(let day, let from, let to):
            "This overlaps your shift on \(day) from \(from) to \(to). Change the times or edit that shift."
        case .breakNeedsEnd(let n):
            "Break \(n) needs an end time."
        case .breakEndNotAfterStart(let n):
            "Break \(n) has to end after it starts."
        case .breakOutsideShift(let n):
            "Break \(n) has to fall inside the shift."
        case .onlyLatestBreakOpen:
            "Only the latest break can be left open."
        case .breaksOverlap:
            "Two breaks overlap. Fix their times."
        case .newStartInFuture:
            "That time hasn’t happened yet. Pick an earlier time."
        case .newStartAfterFirstBreak(let time):
            "Your first break started at \(time). Pick a time before that."
        case .newStartOverlaps(let from, let to):
            "That overlaps your shift from \(from) to \(to)."
        }
    }
}

/// The rules every shift must follow. The app's editor and the server run the same checks,
/// so a shift the app accepts is never refused later for a different reason.
public enum ShiftRules {
    /// Whole-shift check, used by the app's editor and by the server for every pushed shift.
    /// `others` = the same user's other live shifts (deleted ones, other people's and this
    /// shift itself are skipped anyway). `skew` = how far in the future times may be (the
    /// server passes `Limits.clockSkew`). A deleted shift always passes. Returns the first problem found.
    public static func validate(_ shift: Shift, others: [Shift], now: Date, calendar: FarmCalendar, skew: TimeInterval = 0) -> ShiftRuleError? {
        guard shift.isLive else { return nil }
        let latest = now.addingTimeInterval(max(0, skew))
        if let end = shift.end, end <= shift.start { return .endNotAfterStart }
        if shift.start > latest { return .startInFuture }
        if let end = shift.end {
            if end > latest { return .endInFuture }
            if end.timeIntervalSince(shift.start) > Limits.maxShift { return .tooLong }
        }
        let rivals = others.filter { $0.isLive && $0.id != shift.id && $0.userId == shift.userId }
        if shift.isOpen && rivals.contains(where: \.isOpen) { return .alreadyClockedIn }
        if let o = overlap(shift.start, shift.end ?? now, rivals, now: now) {
            return .overlaps(day: Fmt.day(o.start, calendar), from: Fmt.time(o.start, calendar), to: o.end.map { Fmt.time($0, calendar) } ?? "now")
        }
        return validateBreaks(shift, latest: latest)
    }

    /// Moving the start of the open shift ("Change start time" / "I started at 7:30").
    /// The new start can't be in the future, after the first break, or inside another of the person's shifts.
    public static func validateNewStart(_ start: Date, for shift: Shift, others: [Shift], now: Date, calendar: FarmCalendar) -> ShiftRuleError? {
        if start > now { return .newStartInFuture }
        if let end = shift.end, end <= start { return .endNotAfterStart }
        if let first = shift.breaks.min(by: { $0.start < $1.start }), start > first.start {
            return .newStartAfterFirstBreak(Fmt.time(first.start, calendar))
        }
        let rivals = others.filter { $0.isLive && $0.id != shift.id && $0.userId == shift.userId }
        if let o = overlap(start, shift.end ?? now, rivals, now: now) {
            return .newStartOverlaps(from: Fmt.time(o.start, calendar), to: o.end.map { Fmt.time($0, calendar) } ?? "now")
        }
        return nil
    }

    /// Breaks sorted by start, notes and break reasons trimmed and clamped to `Limits`.
    public static func normalized(_ shift: Shift) -> Shift {
        var s = shift
        s.notes = Limits.clampNotes(s.notes)
        s.breaks = s.breaks
            .enumerated()
            .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            .map { var b = $0.element; b.reason = Limits.clampReason(b.reason); return b }
        return s
    }

    /// Each break on its own, then the breaks in time order.
    static func validateBreaks(_ shift: Shift, latest: Date) -> ShiftRuleError? {
        for (i, b) in shift.breaks.enumerated() {
            let n = i + 1
            if let end = b.end, end <= b.start { return .breakEndNotAfterStart(n) }
            if b.end == nil && shift.end != nil { return .breakNeedsEnd(n) }
            let limit = shift.end ?? latest
            if b.start < shift.start || b.start > limit || (b.end ?? b.start) > limit { return .breakOutsideShift(n) }
        }
        let sorted = shift.breaks.sorted { $0.start < $1.start }
        for (b, next) in zip(sorted, sorted.dropFirst()) {
            guard let end = b.end else { return .onlyLatestBreakOpen }
            if end > next.start { return .breaksOverlap }
        }
        return nil
    }

    /// The latest-starting shift that shares time with `start..<end`. Open shifts run to `now`; touching ends don't count.
    static func overlap(_ start: Date, _ end: Date, _ rivals: [Shift], now: Date) -> Shift? {
        rivals
            .filter { start < ($0.end ?? max(now, $0.start)) && max(end, start) > $0.start }
            .max { $0.start < $1.start }
    }
}
