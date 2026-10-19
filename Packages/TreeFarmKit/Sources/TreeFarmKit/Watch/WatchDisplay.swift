import Foundation

/// What the watch is showing, read from the displayed state.
public enum WatchPhase: String, Codable, Sendable, CaseIterable {
    /// The watch has never heard from the phone.
    case noData
    case signedOut
    case offClock
    case working
    case lunch
    case onBreak
}

/// Every word and glyph name the watch app, its complications and the Live Activity's small
/// (Smart Stack) layout show, in one tested place, like `Speech` for Siri. Views only lay them
/// out. Times read in the farm's time zone (`WatchState.calendar`). Pay never appears.
///
/// On tinted or Liquid Glass faces color is lost, so every phase has its own glyph and word.
public enum WatchDisplay {
    // MARK: Phase

    public static func phase(_ state: WatchState?) -> WatchPhase {
        guard let state else { return .noData }
        guard state.signedIn else { return .signedOut }
        switch state.snapshot?.phase {
        case nil: return .offClock
        case .working?: return .working
        case .lunch?: return .lunch
        case .onBreak?: return .onBreak
        }
    }

    /// "Working", "Lunch", "Break".
    public static func phaseTitle(_ phase: WatchPhase) -> String {
        switch phase {
        case .working: "Working"
        case .lunch: "Lunch"
        case .onBreak: "Break"
        case .offClock: "Off the clock"
        case .signedOut: "Signed out"
        case .noData: appName
        }
    }

    /// SF Symbol names.
    public static func phaseGlyph(_ phase: WatchPhase) -> String {
        switch phase {
        case .working: "leaf.fill"
        case .lunch: "cup.and.saucer.fill"
        case .onBreak: "pause.fill"
        case .offClock: "leaf"
        case .signedOut, .noData: "iphone"
        }
    }

    // MARK: The primary button (Double Tap)

    /// What the big button does. Clock-out is never the primary action.
    public enum Primary: Equatable, Sendable {
        case clockIn
        case markRow(RowChip)
        case backToWork
        /// Every row in the field is shaped. Disabled.
        case fieldDone
        /// Chips ran out only because the phone is away. Disabled.
        case outOfKnownRows
        /// Signed out or never connected: no button.
        case none
    }

    /// The primary action, with the Digital Crown on chip `chipIndex` (0 = the next row).
    public static func primary(_ state: WatchState?, chipIndex: Int = 0) -> Primary {
        switch phase(state) {
        case .noData, .signedOut: return .none
        case .offClock: return .clockIn
        case .lunch, .onBreak: return .backToWork
        case .working:
            let chips = self.chips(state)
            guard !chips.isEmpty else { return isFieldDone(state) ? .fieldDone : .outOfKnownRows }
            return .markRow(chips[min(max(0, chipIndex), chips.count - 1)])
        }
    }

    /// "Row 14 done", "Clock in", "Back to work", "Field done", "Out of rows the watch knows".
    public static func primaryLabel(_ primary: Primary) -> String {
        primaryLabelSteps(primary).first ?? ""
    }

    /// The label, then shorter ones for `ViewThatFits` at large text sizes:
    /// "Row 14 done" → "Row 14" → "14".
    public static func primaryLabelSteps(_ primary: Primary) -> [String] {
        switch primary {
        case .clockIn: [clockIn]
        case .markRow(let chip): ["\(chip.title) done", chip.title, String(chip.row + 1)]
        case .backToWork: [backToWork, "Back"]
        case .fieldDone: ["Field done", "Done"]
        case .outOfKnownRows: ["Out of rows the watch knows", "No rows known"]
        case .none: []
        }
    }

    public static func primaryGlyph(_ primary: Primary) -> String {
        switch primary {
        case .clockIn, .backToWork: "play.fill"
        case .markRow, .fieldDone: "checkmark"
        case .outOfKnownRows: "iphone.slash"
        case .none: ""
        }
    }

    public static func isPrimaryEnabled(_ primary: Primary) -> Bool {
        switch primary {
        case .clockIn, .markRow, .backToWork: true
        case .fieldDone, .outOfKnownRows, .none: false
        }
    }

    /// VoiceOver: "Mark row 14 in block 2 shaped".
    public static func primaryAccessibilityLabel(_ primary: Primary) -> String {
        switch primary {
        case .markRow(let chip): "Mark row \(chip.row + 1) in \(blockPhrase(chip.blockName)) shaped"
        default: primaryLabel(primary)
        }
    }

    /// The command the primary button sends (the watch always sends `markRow` for the chip it
    /// showed, never `markNextRow`). Nil when it's disabled.
    public static func command(for primary: Primary) -> FieldCommand? {
        switch primary {
        case .clockIn: .clockIn(fieldId: nil)
        case .markRow(let chip): .markRow(chip.rowRef)
        case .backToWork: .endBreak
        case .fieldDone, .outOfKnownRows, .none: nil
        }
    }

    // MARK: Rows

    /// The Digital Crown's chips: the first 3 next rows.
    public static func chips(_ state: WatchState?) -> [RowChip] {
        Array((state?.nextRows ?? []).prefix(3))
    }

    /// The crown selector's spoken value: "Row 15 in block 2".
    public static func chipValue(_ chip: RowChip) -> String {
        "\(chip.title) in \(blockPhrase(chip.blockName))"
    }

    /// The state shows every row of the field shaped (never guessed from missing chips).
    public static func isFieldDone(_ state: WatchState?) -> Bool {
        guard let snapshot = state?.snapshot, snapshot.fieldTotal > 0 else { return false }
        return snapshot.fieldShaped >= snapshot.fieldTotal
    }

    /// What the watch says when there's no chip to mark (Double Tap, the Action button, Siri's
    /// "next row"). Nothing is queued.
    public static func noChipLine(_ state: WatchState?) -> String {
        guard let state, isFieldDone(state) else { return outOfKnownRows }
        return "Every row in \(state.snapshot?.fieldName ?? state.fieldName) is shaped."
    }

    public static let outOfKnownRows = "Out of rows the watch knows. Bring your phone closer."

    // MARK: Lines

    /// Working: "Block 2 · 38 trees". Off the clock: "Starts: Block 2 · Row 14".
    public static func placeLine(_ state: WatchState) -> String? {
        let first = state.nextRows.first
        if let snapshot = state.snapshot {
            let place = first?.blockName ?? (snapshot.fieldName.isEmpty ? nil : snapshot.fieldName)
            return [place, Fmt.plural(snapshot.shiftTrees, "tree")].compactMap { $0 }.joined(separator: " · ")
        }
        guard let first else { return nil }
        return "Starts: \(first.blockName) · \(first.title)"
    }

    /// "Dull’s Tree Farm · North"
    public static func farmLine(_ state: WatchState) -> String {
        [state.farmName, state.fieldName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Lunch · since 12:01", "Break · since 10:15", "Break · Fuel run".
    public static func breakLine(_ state: WatchState) -> String? {
        guard let snapshot = state.snapshot, let start = snapshot.breakStart else { return nil }
        let title = snapshot.phase == .lunch ? "Lunch" : "Break"
        if snapshot.phase == .onBreak, !snapshot.breakReason.isEmpty { return "\(title) · \(snapshot.breakReason)" }
        return "\(title) · since \(time(start, state))"
    }

    /// "Lunch since 12:01" (the rectangular complication's first line).
    public static func sinceLine(_ state: WatchState) -> String? {
        guard let snapshot = state.snapshot, let start = snapshot.breakStart else { return nil }
        return "\(snapshot.phase == .lunch ? "Lunch" : "Break") since \(time(start, state))"
    }

    /// "3:41 worked today" (the frozen total during a break), or "worked this shift".
    public static func workedLine(_ snapshot: LiveSnapshot) -> String {
        "\(Fmt.hm(snapshot.workedSoFar)) \(snapshot.workedLabel)"
    }

    /// "Last shift 8:12 · 412 trees", then shorter for `ViewThatFits`.
    public static func lastShiftSteps(_ closed: ClosedShift) -> [String] {
        let worked = Fmt.hm(closed.worked)
        return ["Last shift \(worked) · \(Fmt.plural(closed.trees, "tree"))", "Last shift \(worked)", worked]
    }

    /// "6.5 h today", for a day with more than one shift.
    public static func hoursTodayLine(_ worked: TimeInterval) -> String {
        "\(decimalHours(worked)) h today"
    }

    /// "6:40 worked · 212 trees" (the Today page).
    public static func todayLine(worked: TimeInterval, trees: Int) -> String {
        "\(Fmt.hm(worked)) worked · \(Fmt.plural(trees, "tree"))"
    }

    /// "34 trees an hour", nil until there's a pace.
    public static func paceLine(_ pacePerHour: Double?) -> String? {
        pacePerHour.map { "\(Speech.rate($0)) trees an hour" }
    }

    /// The field's progress bar: "North 62%" and its fraction.
    public static func fieldProgress(_ snapshot: LiveSnapshot) -> (line: String, fraction: Double)? {
        guard snapshot.fieldTotal > 0 else { return nil }
        let fraction = min(1, Double(snapshot.fieldShaped) / Double(snapshot.fieldTotal))
        let percent = Int((fraction * 100).rounded(.down))
        return ([snapshot.fieldName, "\(percent)%"].filter { !$0.isEmpty }.joined(separator: " "), fraction)
    }

    /// "104 bpm · 612 kcal" (next to a heart glyph), live from the workout.
    public static func heartLine(bpm: Double?, kcal: Double?) -> String? {
        let parts = [bpm.map { "\(Int($0.rounded())) bpm" }, kcal.map { "\(Fmt.count(Int($0.rounded()))) kcal" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: The phone and the queue

    public enum Reach: Equatable, Sendable {
        case reachable, outOfReach, needsUnlock, neverConnected
    }

    /// "iPhone: in reach", "iPhone: out of reach · 2 waiting", "iPhone: unlock once".
    public static func phoneLine(_ reach: Reach, waiting: Int) -> String {
        switch reach {
        case .reachable: waiting > 0 ? "iPhone: in reach · \(waiting) waiting" : "iPhone: in reach"
        case .outOfReach: waiting > 0 ? "iPhone: out of reach · \(waiting) waiting" : "iPhone: out of reach"
        case .needsUnlock: "iPhone: unlock once"
        case .neverConnected: "iPhone: not connected yet"
        }
    }

    public static let queueGlyph = "iphone.slash"

    /// The toast after a tap was queued: "Saved on watch · 2 waiting".
    public static func savedOnWatch(waiting: Int) -> String {
        "Saved on watch · \(waiting) waiting"
    }

    /// What Siri on the watch says when it queued a command.
    public static let savedForSiri = "Saved on your watch. It’ll reach your phone when it’s back in range."

    /// "2 taps waiting for iPhone"
    public static func waitingLine(count: Int) -> String {
        "\(count) \(count == 1 ? "tap" : "taps") waiting for iPhone"
    }

    /// "2 taps waiting · 10:31": the Today page's queue row, with the oldest tap's time.
    public static func waitingSince(count: Int, oldest: Date, state: WatchState?) -> String {
        "\(count) \(count == 1 ? "tap" : "taps") waiting · \(time(oldest, state))"
    }

    /// A waiting tap in the Queue sheet: "10:31 · Row 14 done", "10:35 · Lunch".
    public static func queueItemLine(_ request: WatchRequest, state: WatchState?) -> String {
        "\(time(request.issuedAt, state)) · \(label(for: request))"
    }

    /// A tap the phone refused, kept in the Queue sheet for an hour:
    /// "10:35 Lunch: You’re already on lunch since 10:34."
    public static func refusedItemLine(_ request: WatchRequest, speech: String, state: WatchState?) -> String {
        "\(time(request.issuedAt, state)) \(label(for: request)): \(speech)"
    }

    public static let queueFootnote = "These will count at the time you tapped once your iPhone is back."

    /// "3 older row taps couldn’t be kept."
    public static func droppedLine(_ count: Int) -> String {
        count == 1 ? "1 older row tap couldn’t be kept." : "\(count) older row taps couldn’t be kept."
    }

    /// A request in a few words.
    public static func label(for request: WatchRequest) -> String {
        switch request.body {
        case .command(let command): label(for: command)
        case .question: "Question"
        case .refresh: "Refresh"
        }
    }

    public static func label(for command: FieldCommand) -> String {
        switch command {
        case .clockIn: clockIn
        case .clockOut: clockOut
        case .startBreak(let kind, _): kind == .lunch ? lunch : takeBreak
        case .endBreak: backToWork
        case .markNextRow: "Next row"
        case .markRow(let row): "Row \(row.row + 1) done"
        case .markTrees(let row, let positions): "Row \(row.row + 1), trees \(positions.lowerBound + 1)–\(positions.upperBound + 1)"
        case .moveTo: "Move"
        case .addShiftNote: "Note"
        case .addTreeNote: "Tree note"
        case .changeStart: "Start time"
        case .undo: undo
        case .cancelShift: undoClockIn
        }
    }

    /// Undo took back a tap that was still waiting: "Took back row 15. It wasn’t sent yet."
    public static func tookBack(_ request: WatchRequest) -> String {
        let what: String
        switch request.command {
        case .markRow(let row)?: what = "row \(row.row + 1)"
        case .markTrees(let row, _)?: what = "the trees in row \(row.row + 1)"
        case .startBreak(let kind, _)?: what = kind == .lunch ? "lunch" : "the break"
        case .endBreak?: what = "back to work"
        case .clockIn?: what = "the clock-in"
        case .clockOut?: what = "the clock-out"
        case .addShiftNote?: what = "the note"
        case .cancelShift?: what = "the undo of the clock-in"
        default: what = "that"
        }
        return "Took back \(what). It wasn’t sent yet."
    }

    public static let neverConnected = "Open Time Card on your iPhone once."
    public static let signedOut = "Open Time Card on your iPhone to sign in."
    public static let unlockPhone = "Unlock your phone once."
    public static let waitingForPhone = "Waiting for phone…"
    public static let undoNeedsPhone = "Undo needs your phone nearby."
    public static let askNeedsPhone = "That needs your phone nearby."
    /// The watch app can't read a message from a newer iPhone app, or the other way round.
    public static let updatePhone = "Update Time Card on your iPhone."
    public static let updateWatch = "Update Time Card on your Apple Watch."
    public static let clockOutWaiting = "Clock-out waiting for iPhone"
    /// The local notification after a clock-out waited 60 minutes.
    public static let stuckClockOut = "Open Time Card near your iPhone to finish clocking out."
    /// A status answer from the watch's cache: "… as of 10:42."
    public static func asOf(_ date: Date, state: WatchState?) -> String {
        "as of \(time(date, state))"
    }

    // MARK: Setup and onboarding

    public static let appName = "Time Card"
    public static let siriNote = "Say “Clock in with Time Card” once and tap Allow. If you said no, Siri on the watch can’t be turned back on for Time Card yet."
    public static let returnToClockTip = "Settings › General › Return to Clock › Time Card › 1 hour"
    public static let healthTitle = "Record shifts as workouts"
    public static let allowHealth = "Allow Health"
    /// Apple's wording for how an Other workout counts calories.
    public static let caloriesNote = "You earn the calorie equivalent of a brisk walk anytime sensor readings are unavailable."
    public static let notificationsAsk = "Remind me if a clock-out gets stuck."

    // MARK: Workouts

    public static let recording = "Recording shift workout"
    public static let workoutsOff = "Workouts off · Allow Time Card in the Health app on your iPhone."
    public static let recordingStopped = "Recording stopped"
    public static let recordAgain = "Record again"
    public static let actionButtonNeedsWorkouts = "Action button needs workouts on."
    public static let lowPower = "Low Power: Double Tap is off"
    public static let recordingYourShift = "Recording your shift."

    /// "Recording from 7:14" (a workout that started later than the shift).
    public static func recordingFrom(_ date: Date, state: WatchState?) -> String {
        "Recording from \(time(date, state))"
    }

    /// "Battery 42%. Charge at lunch to last the shift." (below 50% at clock-in), else nil.
    public static func batteryWarning(level: Double) -> String? {
        guard level >= 0, level < 0.5 else { return nil }
        return "Battery \(Int((level * 100).rounded()))%. Charge at lunch to last the shift."
    }

    // MARK: Shift summary (never pay)

    public static let shiftDone = "Shift done"

    /// "worked · 412 trees" under the big worked time.
    public static func summaryWorkedLine(trees: Int) -> String {
        "worked · \(Fmt.plural(trees, "tree"))"
    }

    /// While the clock-out still waits for the phone, the watch's own count.
    public static func summaryWaitingLine(trees: Int) -> String {
        "\(Fmt.plural(trees, "tree")) · waiting for iPhone"
    }

    /// "avg 104 · max 151" (next to a heart glyph).
    public static func summaryHeartLine(avg: Double?, max: Double?) -> String? {
        let parts = [avg.map { "avg \(Int($0.rounded()))" }, max.map { "max \(Int($0.rounded()))" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "1,120 kcal · 7:41 act." (next to a flame glyph).
    public static func summaryEnergyLine(kcal: Double?, active: TimeInterval) -> String {
        let time = "\(Fmt.hm(active)) act."
        guard let kcal else { return time }
        return "\(Fmt.count(Int(kcal.rounded()))) kcal · \(time)"
    }

    // MARK: Buttons

    public static let clockIn = "Clock in"
    public static let clockOut = "Clock out"
    public static let lunch = "Lunch"
    public static let takeBreak = "Break"
    public static let backToWork = "Back to work"
    public static let undo = "Undo"
    public static let lock = "Lock"
    public static let undoClockIn = "Undo clock-in"
    public static let yesClockOut = "Yes, clock out"
    public static let keepWorking = "Keep working"
    public static let done = "Done"
    public static let tryAgain = "Try again"

    public enum Glyph {
        public static let clockIn = "play.fill"
        public static let backToWork = "play.fill"
        public static let rowDone = "checkmark"
        public static let lunch = "cup.and.saucer.fill"
        public static let takeBreak = "pause.fill"
        public static let undo = "arrow.uturn.backward"
        public static let lock = "drop.fill"
        public static let clockOut = "stop.fill"
        public static let heart = "heart.fill"
        public static let energy = "flame.fill"
        public static let shiftDone = "checkmark.circle.fill"
        public static let phone = "iphone"
        public static let phoneAway = "iphone.slash"
        public static let recording = "record.circle"
    }

    // MARK: Accessibility

    /// One element per timer: "Worked 3 hours 41 minutes".
    public static func timerAccessibility(_ worked: TimeInterval) -> String {
        "Worked \(Fmt.spokenDuration(worked))"
    }

    // MARK: Complications

    /// The circular complication's number: the next row, "14".
    public static func rowNumber(_ chip: RowChip) -> String {
        String(chip.row + 1)
    }

    /// The corner complication's row: "R14".
    public static func cornerRow(_ chip: RowChip) -> String {
        "R\(chip.row + 1)"
    }

    /// Off the clock in the circular complication: "6.5h" today, or "IN" before any work.
    public static func circularHours(_ worked: TimeInterval) -> String {
        worked < 60 ? "IN" : "\(decimalHours(worked))h"
    }

    public static let noDataMark = "—"
    public static let openOnPhone = "Open on iPhone"

    /// The rectangular complication (and the Smart Stack widget), line 1:
    /// "Working · Block 2", "Lunch since 12:01", "Time Card".
    public static func rectangularTitle(_ state: WatchState?) -> String {
        guard let state else { return appName }
        switch phase(state) {
        case .working:
            return [phaseTitle(.working), state.nextRows.first?.blockName].compactMap { $0 }.joined(separator: " · ")
        case .lunch, .onBreak:
            return sinceLine(state) ?? phaseTitle(phase(state))
        case .offClock, .signedOut, .noData:
            return appName
        }
    }

    /// Line 3: "Row 14 next · 38 trees", "3:41 worked today", "6.5 h today · Row 14 next", or the
    /// waiting taps ("2 taps waiting for iPhone", "Clock-out waiting for iPhone").
    public static func rectangularDetail(_ state: WatchState?, waitingCount: Int = 0, clockOutWaiting: Bool = false) -> String? {
        if clockOutWaiting { return self.clockOutWaiting }
        if waitingCount > 0 { return waitingLine(count: waitingCount) }
        guard let state else { return nil }
        switch phase(state) {
        case .working:
            let snapshot = state.snapshot!
            let next = state.nextRows.first.map { "\($0.title) next" }
            return [next, Fmt.plural(snapshot.shiftTrees, "tree")].compactMap { $0 }.joined(separator: " · ")
        case .lunch, .onBreak:
            return state.snapshot.map(workedLine)
        case .offClock:
            let hours = state.todayWorked >= 60 ? hoursTodayLine(state.todayWorked) : nil
            let next = state.nextRows.first.map { "\($0.title) next" }
            let line = [hours, next].compactMap { $0 }.joined(separator: " · ")
            return line.isEmpty ? nil : line
        case .signedOut, .noData:
            return nil
        }
    }

    /// The inline complication after its glyph, beside a timer: "Row 14" while working,
    /// "3:41 worked" on a break, "6.5 h today" off the clock.
    public static func inlineDetail(_ state: WatchState?) -> String {
        guard let state else { return appName }
        switch phase(state) {
        case .working: return state.nextRows.first?.title ?? phaseTitle(.working)
        case .lunch, .onBreak: return "\(Fmt.hm(state.snapshot?.workedSoFar ?? 0)) worked"
        case .offClock: return hoursTodayLine(state.todayWorked)
        case .signedOut, .noData: return appName
        }
    }

    // MARK: The Live Activity's small (Smart Stack) layout

    /// Line 1: "Working · Block 2", "Lunch · 3:41 worked".
    public static func smallTitle(_ snapshot: LiveSnapshot) -> String {
        switch snapshot.phase {
        case .working:
            return [phaseTitle(.working), snapshot.nextRows.first?.blockName].compactMap { $0 }.joined(separator: " · ")
        case .lunch, .onBreak:
            return "\(snapshot.phase == .lunch ? "Lunch" : "Break") · \(Fmt.hm(snapshot.workedSoFar)) worked"
        }
    }

    /// Line 2: "Next Row 14 · 38 trees", "Since 12:01".
    public static func smallDetail(_ snapshot: LiveSnapshot, calendar: FarmCalendar) -> String {
        switch snapshot.phase {
        case .working:
            let next = snapshot.nextRows.first.map { "Next \($0.title)" }
            return [next, Fmt.plural(snapshot.shiftTrees, "tree")].compactMap { $0 }.joined(separator: " · ")
        case .lunch, .onBreak:
            return snapshot.breakStart.map { "Since \(Fmt.spokenTime($0, calendar))" } ?? ""
        }
    }

    // MARK: Helpers

    /// A time of day as Siri says it, in the farm's zone: "12:01" in the workday, "5:45 AM" outside.
    public static func time(_ date: Date, _ state: WatchState?) -> String {
        Fmt.spokenTime(date, state?.calendar ?? FarmCalendar(timeZone: .current, weekStart: .monday))
    }

    /// "block 2" from a chip's "Block 2"; longer names as they are (like `Speech.blockPhrase`).
    public static func blockPhrase(_ title: String) -> String {
        title.hasPrefix("Block ") ? "block" + title.dropFirst("Block".count) : title
    }

    /// Hours to one place, without a trailing ".0": "6.5", "8".
    static func decimalHours(_ worked: TimeInterval) -> String {
        let tenths = Int((max(0, worked) / 360).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
    }
}
