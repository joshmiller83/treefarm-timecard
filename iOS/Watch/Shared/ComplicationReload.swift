import Foundation
import TreeFarmKit
import WidgetKit

// The rules behind the watch complications (docs/watch.md 4.3), kept pure so the watch tests
// pin them: when to redraw them, when the day turns over, what each family shows, and when the
// Smart Stack should raise them. Compiled into the watch app, which reloads, and the widget
// extension, which draws.

/// Reload the complications only when something they show changed. A reload in the background
/// counts against a small daily budget, so a timer tick, a new revision or a chip past the first
/// never spends one; most reloads happen with the app in front, where they're free.
///
/// What counts as shown: signed in or not, the phase, the first chip, the field (and whether
/// every row in it is shaped), whether taps are waiting (the count going between 0 and more, not
/// each tap), a clock-out waiting, the last closed shift, the usual start, the farm's time zone,
/// trees this shift, the moments the timers count from (a start time changed on the phone), and
/// off the clock the hours today and the day they belong to (an old timeline reads "IN" past
/// midnight, so the same hours on a later day are news).
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
    /// a clock-out and a new usual start all move it; a timeline reload alone never re-asks).
    /// Call it after `WatchStateFile.write` when `needsReload` says so.
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
        /// Off the clock with hours shown: the farm day they were counted on.
        var hoursDay: DayKey?

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
                if state.todayWorked >= ComplicationDay.someWork {
                    hoursDay = state.calendar.dayKey(ComplicationDay.countedAt(state))
                }
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

/// Off the clock, "6.5 h today" belongs to the day it was counted on. The timeline never
/// expires and the phone only sends a new state on an event, so after an evening clock-out the
/// complications turn back to "IN" at the farm's midnight on their own: the timeline carries a
/// second entry then, which costs no reload, and every entry reads the state as of its moment.
enum ComplicationDay {
    /// Less than this reads "IN" (`WatchDisplay.circularHours`).
    static let someWork: TimeInterval = 60

    /// The state as it reads at `date`: off the clock on a later farm day, nothing worked yet.
    /// On the clock it's as sent, since the timers count from their own moments.
    static func asOf(_ state: WatchState?, at date: Date) -> WatchState? {
        guard var state, state.snapshot == nil, state.todayWorked != 0 else { return state }
        guard date >= nextMidnight(after: countedAt(state), state.calendar) else { return state }
        state.todayWorked = 0
        return state
    }

    /// When the timeline's entries start: now, and off the clock with hours showing, the farm's
    /// next midnight, when they turn back to "IN".
    static func entryDates(for state: WatchState?, now: Date) -> [Date] {
        guard let state = asOf(state, at: now), state.signedIn, state.snapshot == nil,
              state.todayWorked >= someWork else { return [now] }
        return [now, nextMidnight(after: now, state.calendar)]
    }

    /// When the hours today were counted: when the phone built the state, or later when the
    /// watch itself clocked out with the phone away (its displayed state keeps the phone's
    /// `updatedAt`, and the closed shift's end is the tap).
    static func countedAt(_ state: WatchState) -> Date {
        max(state.updatedAt, state.lastClosedShift?.end ?? .distantPast)
    }

    static func nextMidnight(after date: Date, _ calendar: FarmCalendar) -> Date {
        calendar.startOfDay(calendar.addDays(calendar.startOfDay(date), 1))
    }
}

/// What the four complication families show at one moment, worked out from what the watch app
/// wrote. Every word and glyph on the face comes from `WatchDisplay`; the views only lay these out
/// (docs/watch.md 4.3).
struct ComplicationFace: Equatable {
    /// The color family: fir green while working, sap gold on lunch or a break. On tinted and
    /// Liquid Glass faces color is lost, so each phase keeps its own glyph and word too.
    enum Tone: Equatable {
        case working, onBreak, offClock, none
    }

    /// The circular ring fills over an eight-hour day.
    static let ringDay: TimeInterval = 8 * 3600

    var phase: WatchPhase
    var tone: Tone
    /// `leaf.fill`, `cup.and.saucer.fill`, `pause.fill`, `leaf`, `iphone`.
    var glyph: String
    /// The phase in a word, for VoiceOver beside the glyph: "Working", "Lunch", "Off the clock".
    var word: String
    /// Working: the worked-time timer counts from here.
    var timerStart: Date?
    /// Lunch or a break: the break timer counts from here.
    var breakStart: Date?
    /// Lunch or a break: the worked time, frozen, as a share of `ringDay`.
    var frozenRing: Double
    /// The next row: "14" (circular), "R14" (corner).
    var rowNumber: String?
    var cornerRow: String?
    /// Working with no chip: a check when the field is done, else the phone-away glyph.
    var noRowGlyph: String?
    /// Working: what VoiceOver says for the circular's centre: "next row 14", "Field done".
    var rowAccessibility: String?
    /// "Lunch", "Break".
    var breakWord: String
    /// Rectangular line 1: "Working · Block 2", "Lunch since 12:01", "Time Card".
    var title: String
    /// Line 1 when that's too wide: the block alone while working ("North Slope 12").
    var shortTitle: String
    /// Rectangular line 3, or the waiting taps.
    var detail: String?
    /// Line 3 is about taps waiting for the phone.
    var detailIsWaiting: Bool
    /// Line 3 read aloud when it differs: the frozen worked time, "Worked 3 hours 41 minutes".
    var detailAccessibility: String?
    /// Off the clock: "6.5h", or "IN" before any work today (circular).
    var hoursMark: String
    /// "6.5 h today" (corner and inline), or "Clock in" before any work today.
    var hoursLine: String
    /// Inline, after the timer: "Row 14", "3:41 worked".
    var inlineDetail: String

    /// What `contents` shows at `date`, the timeline entry's moment.
    init(_ contents: WatchStateFile.Contents, at date: Date) {
        let state = ComplicationDay.asOf(contents.displayed, at: date)
        let snapshot = state?.snapshot
        phase = WatchDisplay.phase(state)
        tone = switch phase {
        case .working: .working
        case .lunch, .onBreak: .onBreak
        case .offClock: .offClock
        case .signedOut, .noData: .none
        }
        glyph = WatchDisplay.phaseGlyph(phase)
        word = WatchDisplay.phaseTitle(phase)
        breakWord = WatchDisplay.phaseTitle(phase == .onBreak ? .onBreak : .lunch)

        timerStart = phase == .working ? snapshot?.timerStart : nil
        breakStart = tone == .onBreak ? (snapshot?.breakStart ?? snapshot?.timerStart) : nil
        let frozen = (snapshot?.workedSoFar ?? 0) / Self.ringDay
        frozenRing = frozen.isFinite ? min(1, max(0, frozen)) : 0

        let chip = phase == .working ? state?.nextRows.first : nil
        rowNumber = chip.map(WatchDisplay.rowNumber)
        cornerRow = chip.map(WatchDisplay.cornerRow)
        let primary = WatchDisplay.primary(state)
        noRowGlyph = phase == .working && chip == nil ? WatchDisplay.primaryGlyph(primary) : nil
        rowAccessibility = phase != .working ? nil
            : chip.map { "next row \(WatchDisplay.rowNumber($0))" } ?? WatchDisplay.primaryLabel(primary)

        title = WatchDisplay.rectangularTitle(state)
        shortTitle = chip?.blockName ?? title
        detail = WatchDisplay.rectangularDetail(state, waitingCount: contents.waitingCount, clockOutWaiting: contents.clockOutWaiting)
        detailIsWaiting = contents.clockOutWaiting || contents.waitingCount > 0
        detailAccessibility = tone == .onBreak && !detailIsWaiting ? snapshot.map { WatchDisplay.timerAccessibility($0.workedSoFar) } : nil

        let worked = state?.todayWorked ?? 0
        hoursMark = WatchDisplay.circularHours(worked)
        hoursLine = worked < ComplicationDay.someWork ? WatchDisplay.clockIn : WatchDisplay.hoursTodayLine(worked)
        inlineDetail = phase == .offClock ? hoursLine : WatchDisplay.inlineDetail(state)
    }
}

/// When the Smart Stack should raise the shift widget (watchOS 11 `relevance()`; watchOS
/// ignores `TimelineEntryRelevance`):
/// - clocked in: from the shift's start for 10 hours, so it stays up all shift;
/// - off the clock with a usual start: from 30 minutes before it to an hour after, in the farm's
///   time zone, today (unless that's over) and each of the next 7 days, so "Clock in" rises in
///   the morning even after a weekend with nothing new from the phone to ask again;
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
    /// Usual-start windows run this many days past today.
    static let daysAhead = 7

    static func windows(for state: WatchState?, now: Date) -> [Window] {
        guard let state, state.signedIn else { return [] }
        if let snapshot = state.snapshot {
            // The phone always sends the start; a shift without one counts from its timer.
            let start = state.shiftStart ?? snapshot.timerStart
            return [Window(interval: DateInterval(start: start, duration: shiftLength), kind: .shift)]
        }
        guard let usual = state.usualStart, let hour = usual.hour else { return [] }
        let calendar = state.calendar
        let today = calendar.startOfDay(now)
        return (0...daysAhead)
            .map { calendar.dayKey(calendar.addDays(today, $0)) }
            .map { day in
                let start = calendar.date(on: day, hour: hour, minute: usual.minute ?? 0)
                return Window(interval: DateInterval(start: start.addingTimeInterval(-beforeUsualStart),
                                                     end: start.addingTimeInterval(afterUsualStart)),
                              kind: .usualStart)
            }
            .filter { $0.interval.end > now }
    }
}
