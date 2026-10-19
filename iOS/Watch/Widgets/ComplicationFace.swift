import Foundation
import TreeFarmKit

/// What the four complication families show, worked out once from an entry. Every word and
/// glyph comes from `WatchDisplay`; the views only lay these out (docs/watch.md 4.3).
struct ComplicationFace {
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
    /// Off the clock: "6.5h", or "IN" before any work today (circular).
    var hoursMark: String
    /// "6.5 h today" (corner and inline), or "Clock in" before any work today.
    var hoursLine: String
    /// Inline, after the timer: "Row 14", "3:41 worked".
    var inlineDetail: String

    init(_ entry: ShiftComplicationEntry) {
        let state = entry.state
        let snapshot = state?.snapshot
        phase = WatchDisplay.phase(state)
        tone = switch phase {
        case .working: .working
        case .lunch, .onBreak: .onBreak
        case .offClock: .offClock
        case .signedOut, .noData: .none
        }
        glyph = WatchDisplay.phaseGlyph(phase)
        breakWord = WatchDisplay.phaseTitle(phase == .onBreak ? .onBreak : .lunch)

        timerStart = phase == .working ? snapshot?.timerStart : nil
        breakStart = tone == .onBreak ? (snapshot?.breakStart ?? snapshot?.timerStart) : nil
        let frozen = (snapshot?.workedSoFar ?? 0) / Self.ringDay
        frozenRing = frozen.isFinite ? min(1, max(0, frozen)) : 0

        let chip = phase == .working ? state?.nextRows.first : nil
        rowNumber = chip.map(WatchDisplay.rowNumber)
        cornerRow = chip.map(WatchDisplay.cornerRow)
        noRowGlyph = phase == .working && chip == nil ? WatchDisplay.primaryGlyph(WatchDisplay.primary(state)) : nil

        title = WatchDisplay.rectangularTitle(state)
        shortTitle = chip?.blockName ?? title
        detail = WatchDisplay.rectangularDetail(state, waitingCount: entry.waitingCount, clockOutWaiting: entry.clockOutWaiting)
        detailIsWaiting = entry.clockOutWaiting || entry.waitingCount > 0

        let worked = state?.todayWorked ?? 0
        hoursMark = WatchDisplay.circularHours(worked)
        hoursLine = worked < 60 ? WatchDisplay.clockIn : WatchDisplay.hoursTodayLine(worked)
        inlineDetail = phase == .offClock ? hoursLine : WatchDisplay.inlineDetail(state)
    }
}
