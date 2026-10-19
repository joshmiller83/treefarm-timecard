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

    init(state: FieldState, now: Date) {
        let cal = state.calendar
        let shifts = state.liveShifts
        let open = state.openShift
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

        let label = Hours.isStale(open, now: now, calendar: cal) ? "worked this shift" : "worked today"
        if Hours.isStale(open, now: now, calendar: cal) || Hours.forgotToClockOut(open, now: now) {
            stale = "You’ve been clocked in since \(Fmt.day(open.start, cal)) at \(Fmt.time(open.start, cal))."
        }
        let clockedIn = "Clocked in \(Fmt.time(open.start, cal))"

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

    var isWorking: Bool { phase == .working }
    var isOnBreak: Bool {
        if case .onBreak = phase { return true }
        return false
    }
}

/// "Change start time": the picked wall-clock time, in the farm's zone, on whichever day puts
/// it nearest the original start. So 11:50 PM for a shift clocked in at 12:05 AM means the
/// night before, and 12:03 AM for one at 11:58 PM means the next morning (which ShiftRules
/// then refuses as a time that hasn't happened yet).
enum StartTime {
    /// An untouched hour and minute keep the exact original start (seconds and all), so
    /// opening the picker and saving changes nothing.
    static func newStart(picked: Date, original: Date, calendar: FarmCalendar) -> Date {
        let cal = calendar.calendar
        let p = cal.dateComponents([.hour, .minute], from: picked)
        let o = cal.dateComponents([.hour, .minute], from: original)
        if p.hour == o.hour && p.minute == o.minute { return original }
        let day = calendar.dayKey(original)
        return [-1, 0, 1]
            .map { offset in
                let key = calendar.dayKey(calendar.addDays(calendar.date(on: day, hour: 12, minute: 0), offset))
                return calendar.date(on: key, hour: p.hour ?? 0, minute: p.minute ?? 0)
            }
            .min { abs($0.timeIntervalSince(original)) < abs($1.timeIntervalSince(original)) }!
    }
}
