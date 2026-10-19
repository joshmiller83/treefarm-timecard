import Foundation
import TreeFarmKit
import WidgetKit

// The two timing rules behind the watch complications (docs/watch.md 4.3), kept pure so the
// watch tests pin them: when to redraw them, and when the Smart Stack should raise them.
// Compiled into the watch app, which reloads, and the widget extension, which asks for relevance.

/// Reload the complications only when something they show changed. A reload in the background
/// counts against a small daily budget, so a timer tick, a new revision or a chip past the first
/// never spends one; most reloads happen with the app in front, where they're free.
///
/// What counts as shown: signed in or not, the phase, the first chip, the field (and whether
/// every row in it is shaped), whether taps are waiting (the count going between 0 and more, not
/// each tap), a clock-out waiting, the last closed shift, the usual start, the farm's time zone,
/// trees this shift, and the moments the timers count from (a start time changed on the phone).
enum ComplicationReload {
    /// The shift complication's widget kind (`ShiftComplication`).
    static let kind = "timecard.watch.shift"

    /// Timers counting from moments closer than this are the same timer: a rebuilt snapshot
    /// can land a fraction of a second away. Start times are edited in whole minutes.
    static let timerTolerance: TimeInterval = 30

    static func needsReload(old: WatchStateFile.Contents?, new: WatchStateFile.Contents) -> Bool {
        guard let old else { return true }
        return Shown(old) != Shown(new)
    }

    /// Redraws the complications and asks the Smart Stack for their relevance again (a clock-in,
    /// a clock-out and a new usual start all move it). Call it after `WatchStateFile.write`
    /// when `needsReload` says so.
    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        WidgetCenter.shared.invalidateRelevance(ofKind: kind)
    }

    /// Everything a complication draws from the state, at the precision it draws it.
    private struct Shown: Equatable {
        var phase: WatchPhase
        var waiting: Bool
        var clockOutWaiting: Bool
        var firstChip: RowChip?
        var field = ""
        var fieldDone = false
        var lastClosedShift: ClosedShift?
        var usualStart: DateComponents?
        var timeZone: String?
        var trees: Int?
        var shiftStart: Moment?
        var timerStart: Moment?
        var breakStart: Moment?
        /// "3:41 worked" beside a break, "6.5 h today" off the clock.
        var workedText: String?

        init(_ contents: WatchStateFile.Contents) {
            let state = contents.displayed
            let snapshot = state?.snapshot
            phase = WatchDisplay.phase(state)
            waiting = contents.waitingCount > 0
            clockOutWaiting = contents.clockOutWaiting
            guard let state, state.signedIn else { return }
            firstChip = state.nextRows.first
            field = [state.fieldName, snapshot?.fieldName ?? ""].joined(separator: "\n")
            fieldDone = WatchDisplay.isFieldDone(state)
            lastClosedShift = state.lastClosedShift
            usualStart = state.usualStart
            timeZone = state.farmTimeZone
            shiftStart = state.shiftStart.map(Moment.init)
            switch phase {
            case .working:
                trees = snapshot?.shiftTrees
                timerStart = snapshot.map { Moment($0.timerStart) }
            case .lunch, .onBreak:
                breakStart = snapshot?.breakStart.map(Moment.init)
                workedText = snapshot.map(WatchDisplay.workedLine)
            case .offClock:
                workedText = WatchDisplay.circularHours(state.todayWorked)
            case .signedOut, .noData:
                break
            }
        }
    }

    /// A moment a timer counts from, equal to another within `timerTolerance`.
    private struct Moment: Equatable {
        var date: Date
        init(_ date: Date) { self.date = date }
        static func == (a: Moment, b: Moment) -> Bool {
            abs(a.date.timeIntervalSince(b.date)) < ComplicationReload.timerTolerance
        }
    }
}

/// When the Smart Stack should raise the shift widget (watchOS 11 `relevance()`; watchOS
/// ignores `TimelineEntryRelevance`):
/// - clocked in: from the shift's start for 10 hours, so it stays up all shift;
/// - off the clock with a usual start: from 30 minutes before it to an hour after, in the farm's
///   time zone, today (unless that's over) and tomorrow, so "Clock in" rises in the morning;
/// - otherwise (signed out, never connected, fewer than 3 shifts so far): never.
enum ComplicationRelevance {
    enum Kind: Equatable, Sendable {
        /// The shift on the clock.
        case shift
        /// The usual clock-in time.
        case usualStart
    }

    struct Window: Equatable, Sendable {
        var interval: DateInterval
        var kind: Kind
    }

    static let shiftLength: TimeInterval = 10 * 3600
    static let beforeUsualStart: TimeInterval = 30 * 60
    static let afterUsualStart: TimeInterval = 60 * 60

    static func windows(for state: WatchState?, now: Date) -> [Window] {
        guard let state, state.signedIn else { return [] }
        if let snapshot = state.snapshot {
            // The phone always sends the start; a shift without one counts from its timer.
            let start = state.shiftStart ?? snapshot.timerStart
            return [Window(interval: DateInterval(start: start, duration: shiftLength), kind: .shift)]
        }
        guard let usual = state.usualStart, let hour = usual.hour else { return [] }
        let calendar = state.calendar
        let today = calendar.dayKey(now)
        return [today, calendar.dayKey(calendar.addDays(calendar.startOfDay(now), 1))]
            .map { day in
                let start = calendar.date(on: day, hour: hour, minute: usual.minute ?? 0)
                return Window(interval: DateInterval(start: start.addingTimeInterval(-beforeUsualStart),
                                                     end: start.addingTimeInterval(afterUsualStart)),
                              kind: .usualStart)
            }
            .filter { $0.interval.end > now }
    }
}
