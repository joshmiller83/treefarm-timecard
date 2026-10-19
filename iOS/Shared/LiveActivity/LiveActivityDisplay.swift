import Foundation
import TimeCardCore

/// Everything the lock screen and the Dynamic Island say, worked out from a `LiveSnapshot`.
/// The views only lay these out, so the wording is tested once (TimeCardTests) and the
/// lock screen, the island and the app can't drift apart.
///
/// Compiled into the app (for tests and previews) and the widget extension (which draws it).
struct LiveActivityDisplay: Equatable {
    enum Tone: Equatable {
        case working, lunch, onBreak
    }

    /// One of the big row buttons: "ROW / 13", or "BLOCK 3 / 1" once the next rows cross into another block.
    struct RowButton: Equatable, Identifiable {
        var chip: RowChip
        var caption: String
        var number: String
        var accessibilityLabel: String

        var id: String { chip.id }
    }

    /// "Row 14 marked" and whether Undo is offered next to it.
    struct LastAction: Equatable {
        enum Kind: Equatable {
            /// "Row 14 marked": a check beside it, and Undo when there's something to undo.
            case done
            /// "Undid row 14": confirmed without another Undo, so a second tap can't look like a redo.
            case undone
            /// A refused lock-screen tap: "Row 14 was shaped by Sam on Oct 16." No check, no Undo.
            case notice
        }

        var text: String
        var kind: Kind = .done
        var canUndo: Bool

        init(text: String, kind: Kind = .done, canUndo: Bool) {
            self.text = text
            self.kind = kind
            self.canUndo = kind == .done && canUndo
        }
    }

    var tone: Tone
    var statusTitle: String
    /// "North Field · Block 2"
    var place: String
    /// The block the first next row is in: "Block 2".
    var blockTitle: String?
    /// The running timer counts from here: worked time while working, the break while on one.
    var timerStart: Date
    /// "worked today" beside the worked timer. None on a break: the pill already says it.
    var timerCaption: String?
    /// How many characters the running timer may reach before the next update. Timer text
    /// can't be measured (it would size itself for counting forever), so its width is set.
    var timerCharacters: Int
    /// Worked time, frozen during a break: "4:12:08".
    var frozenWorked: String?
    var frozenWorkedCaption: String?
    var frozenWorkedAccessibilityLabel: String?
    /// The break's reason, when one was given.
    var breakDetail: String?
    var breakStart: Date?
    /// "212"
    var trees: String
    /// "trees this shift"
    var treesCaption: String
    /// Field progress, 0...1.
    var progress: Double
    var progressLabel: String
    var rows: [RowButton]
    /// Shown instead of row buttons when there's no row to offer.
    var fieldMessage: String?
    var lastAction: LastAction?
    /// The next row's number, for the island's compact view.
    var compactRow: String?

    var isOnBreak: Bool { tone != .working }

    init(_ s: LiveSnapshot) {
        tone = switch s.phase {
        case .working: .working
        case .lunch: .lunch
        case .onBreak: .onBreak
        }
        statusTitle = switch s.phase {
        case .working: "Working"
        case .lunch: "On lunch"
        case .onBreak: "On break"
        }

        let first = s.nextRows.first
        blockTitle = first?.blockName
        place = [s.fieldName, first?.blockName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")

        let onBreak = s.phase != .working
        timerStart = onBreak ? (s.breakStart ?? s.timerStart) : s.timerStart
        timerCaption = onBreak ? nil : s.workedLabel
        // The timer runs on its own until the next update, which may not come before iOS ends
        // the activity; size it for the most it can show by then.
        let madeAt = s.timerStart.addingTimeInterval(s.workedSoFar)
        let counted = onBreak ? max(0, madeAt.timeIntervalSince(s.breakStart ?? madeAt)) : s.workedSoFar
        timerCharacters = Self.timerCharacters(reaching: counted + Self.timerHorizon)
        frozenWorked = onBreak ? Fmt.hms(s.workedSoFar) : nil
        frozenWorkedCaption = onBreak ? s.workedLabel : nil
        frozenWorkedAccessibilityLabel = onBreak ? "\(Fmt.spokenDuration(s.workedSoFar)) \(s.workedLabel)" : nil
        let reason = s.breakReason.trimmingCharacters(in: .whitespacesAndNewlines)
        breakDetail = onBreak && !reason.isEmpty ? reason : nil
        breakStart = onBreak ? s.breakStart : nil

        trees = Fmt.count(s.shiftTrees)
        treesCaption = (s.shiftTrees == 1 ? "tree" : "trees") + " this shift"
        progress = s.fieldTotal > 0 ? min(1, max(0, Double(s.fieldShaped) / Double(s.fieldTotal))) : 0
        progressLabel = "\(Fmt.count(s.fieldShaped)) of \(Fmt.plural(s.fieldTotal, "tree")) shaped"
            + (s.fieldName.isEmpty ? "" : " in \(s.fieldName)")

        rows = s.nextRows.map { chip in
            let sameBlock = chip.blockId == first?.blockId
            let number = String(chip.row + 1)
            return RowButton(chip: chip,
                             caption: sameBlock ? "Row" : chip.blockName,
                             number: number,
                             accessibilityLabel: sameBlock ? "Mark row \(number) shaped" : "Mark \(chip.blockName), row \(number) shaped")
        }
        if s.nextRows.isEmpty {
            // The same words FieldEngine says when there's nothing to mark.
            fieldMessage = s.fieldName.isEmpty ? Speech.noField : "Every row in \(s.fieldName) is shaped."
        } else {
            fieldMessage = nil
        }
        compactRow = first.map { String($0.row + 1) }

        lastAction = Self.lastAction(s.lastAction, canUndo: s.canUndo)
    }

    /// True when the two would draw the same card: every word matches and the timers count
    /// from the same second. (Snapshots made moments apart differ in their running totals.)
    static func sameOnScreen(_ a: LiveSnapshot, _ b: LiveSnapshot) -> Bool {
        var x = LiveActivityDisplay(a), y = LiveActivityDisplay(b)
        x.timerStart = x.timerStart.toTheSecond
        y.timerStart = y.timerStart.toTheSecond
        return x == y
    }

    /// Nothing updates an activity once iOS ends it, eight hours after it starts, so a running
    /// timer shows at most this much more than its snapshot.
    static let timerHorizon: TimeInterval = 8 * 3600

    /// "6:42:10" is 7 characters, "10:00:00" 8 and "100:00:00" (a clock-in left open for days) 9.
    static func timerCharacters(reaching seconds: TimeInterval) -> Int {
        seconds >= 100 * 3600 ? 9 : seconds >= 10 * 3600 ? 8 : 7
    }

    // Until LiveSnapshot says what kind of action it was (see the slice notes), the kind is read
    // from the engine's fixed short phrases: "Clocked in", "Undid row 14", "Row 14 marked".
    // A refused tap's reason is a sentence, so it ends with a full stop.

    /// Clocking in or out isn't offered for undo: the undo history may still hold an earlier
    /// shift's rows, and "Clocked in · Undo" would quietly take those back.
    static func lastAction(_ text: String?, canUndo: Bool) -> LastAction? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let last = text.last, ".!?".contains(last) { return LastAction(text: text, kind: .notice, canUndo: false) }
        if text.hasPrefix("Clocked") { return nil }
        if text.hasPrefix("Undid") { return LastAction(text: text, kind: .undone, canUndo: false) }
        return LastAction(text: text, canUndo: canUndo)
    }
}

private extension Date {
    var toTheSecond: Date { Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded()) }
}
