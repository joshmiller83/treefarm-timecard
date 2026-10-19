import Foundation
import TimeCardCore

/// The words and numbers on the big status card, worked out from the farm and the time.
/// Every time and duration goes through TreeFarmKit's `Hours` and `Fmt`, so the card,
/// Siri and the lock screen agree.
struct ClockStatus: Equatable {
    enum Phase: Equatable {
        case off
        case working
        case onBreak(BreakKind)
    }

    var phase: Phase
    /// The open shift, if any.
    var shiftId: UUID?
    /// "Off the clock", "On the clock", "On lunch", "On break".
    var pill: String
    /// "Wednesday, Oct 14".
    var dateText: String
    /// The big clock at `now`: today's worked time, or the open shift's if it began on an earlier day.
    var worked: TimeInterval
    /// "worked today", "worked this shift", plus "· paused while you’re on lunch" on a break.
    var workedLabel: String
    /// Quiet lines under the timer.
    var meta: [String]
    /// "Lunch started 12:01 PM · Fuel run", on a break.
    var breakLine: String?
    var breakStart: Date?
    /// "You’ve been clocked in since Tue, Oct 13 at 7:00 AM." for a shift left open.
    var stale: String?
    /// Open longer than a shift may be, so Clock out can't close it: the card offers
    /// "Fix clock-out time" instead, which opens the editor with an end filled in.
    var needsClockOutFix = false
    /// When the card was read; `worked` is the big clock at this instant.
    var computedAt: Date

    init(state: FieldState, now: Date) {
        let cal = state.calendar
        let shifts = state.liveShifts
        let open = state.openShift
        computedAt = now
        dateText = Fmt.dayLong(now, cal)
        worked = Self.worked(state: state, now: now)
        shiftId = open?.id
        breakLine = nil
        breakStart = nil
        stale = nil

        guard let open else {
            phase = .off
            pill = "Off the clock"
            workedLabel = "worked today"
            let lastOut = shifts
                .filter { $0.end != nil && cal.isSameDay($0.start, now) }
                .max { $0.start < $1.start }
            meta = [lastOut?.end.map { "Last clocked out at \(Fmt.time($0, cal))." } ?? "Not clocked in yet today."]
            return
        }

        let earlierDay = Hours.isStale(open, now: now, calendar: cal)
        let label = earlierDay ? "worked this shift" : "worked today"
        if earlierDay || Hours.forgotToClockOut(open, now: now) {
            stale = Speech.clockedInSince(open, calendar: cal)
        }
        needsClockOutFix = now.timeIntervalSince(open.start) > Limits.maxShift
        // A shift from an earlier day names the day, so 7:00 AM can't read as later today.
        let clockedIn = earlierDay
            ? "Clocked in \(Fmt.day(open.start, cal)) at \(Fmt.time(open.start, cal))"
            : "Clocked in \(Fmt.time(open.start, cal))"

        if let b = open.openBreak {
            phase = .onBreak(b.kind)
            pill = b.kind == .lunch ? "On lunch" : "On break"
            workedLabel = "\(label) · paused while you’re on \(b.kind == .lunch ? "lunch" : "break")"
            breakStart = b.start
            breakLine = "\(b.kind.label) started \(Fmt.time(b.start, cal))" + (b.reason.isEmpty ? "" : " · \(b.reason)")
            meta = [clockedIn]
        } else {
            phase = .working
            pill = "On the clock"
            workedLabel = label
            let breaks = open.breakTime(at: now)
            let breakText = open.breaks.isEmpty ? "No breaks yet" : breaks < 30 ? "Breaks under 1 min" : "Breaks \(Fmt.minutesText(breaks))"
            meta = ["\(clockedIn) · \(breakText)"]
        }
    }

    /// The big clock alone, cheap enough to run every second.
    static func worked(state: FieldState, now: Date) -> TimeInterval {
        Hours.bigClock(shifts: state.liveShifts, now: now, calendar: state.calendar)
    }

    /// The big clock a little later, while working: the reading plus the time since, without
    /// adding up every shift again (the card ticks every second).
    func bigClock(at date: Date) -> TimeInterval {
        isWorking ? worked + max(0, date.timeIntervalSince(computedAt)) : worked
    }

    /// The next moment the worked time reaches a whole second, so the ticks land on them.
    var nextWholeSecond: Date {
        computedAt.addingTimeInterval(worked.rounded(.up) - worked)
    }

    var isWorking: Bool { phase == .working }
    var isOnBreak: Bool {
        if case .onBreak = phase { return true }
        return false
    }
}

/// "Change start time": the wheel's hour and minute, in the farm's zone, on the shift's own day.
/// The AM/PM wheel is explicit, so a pick only crosses midnight when both the original start and
/// the picked time sit within three hours of it: 11:50 PM for a shift clocked in at 12:05 AM means
/// the night before, and 12:03 AM for one at 11:58 PM the next morning (which ShiftRules then
/// refuses as a time that hasn't happened yet). 7:00 PM for a 7:00 AM start stays on the same day.
///
/// Siri's "Fix my start time" resolves a spoken time differently (the latest matching time at
/// or before now), since a spoken "7" carries no AM or PM.
enum PickedStartTime {
    /// How close to midnight both times must be before a pick moves to the next or previous day.
    static let midnightWindow = 3 * 60

    /// An untouched hour and minute keep the exact original start (seconds and all), so
    /// opening the picker and saving changes nothing.
    static func newStart(picked: Date, original: Date, calendar: FarmCalendar) -> Date {
        let cal = calendar.calendar
        let p = cal.dateComponents([.hour, .minute], from: picked)
        let o = cal.dateComponents([.hour, .minute], from: original)
        let (ph, pm) = (p.hour ?? 0, p.minute ?? 0)
        let (oh, om) = (o.hour ?? 0, o.minute ?? 0)
        if ph == oh && pm == om { return original }
        let picked = ph * 60 + pm, started = oh * 60 + om
        let lateNight = 24 * 60 - midnightWindow
        let offset = started < midnightWindow && picked >= lateNight ? -1
            : started >= lateNight && picked < midnightWindow ? 1
            : 0
        let day = calendar.dayKey(calendar.addDays(calendar.date(on: calendar.dayKey(original), hour: 12, minute: 0), offset))
        return calendar.date(on: day, hour: ph, minute: pm)
    }

    /// Under the wheel: "Sun, Oct 18 at 7:00 PM · 12 h earlier", so the day is never a surprise.
    static func preview(start: Date, original: Date, calendar: FarmCalendar) -> String {
        let when = "\(Fmt.day(start, calendar)) at \(Fmt.time(start, calendar))"
        // Measured from the minute on the clock, so "+5 min" says 5 min, whatever the seconds.
        let shown = calendar.calendar.dateInterval(of: .minute, for: original)?.start ?? original
        let moved = start == original ? 0 : start.timeIntervalSince(shown)
        guard abs(moved) >= 30 else { return "\(when) · no change" }
        return "\(when) · \(Fmt.minutesText(abs(moved))) \(moved < 0 ? "earlier" : "later")"
    }
}
