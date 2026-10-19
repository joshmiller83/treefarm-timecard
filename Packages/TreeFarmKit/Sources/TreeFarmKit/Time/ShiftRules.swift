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
        return nil
    }

    /// The latest-starting shift that shares time with `start..<end`. Open shifts run to `now`; touching ends don't count.
    static func overlap(_ start: Date, _ end: Date, _ rivals: [Shift], now: Date) -> Shift? {
        rivals
            .filter { start < ($0.end ?? max(now, $0.start)) && max(end, start) > $0.start }
            .max { $0.start < $1.start }
    }
}
