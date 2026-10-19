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
        var text: String
        var canUndo: Bool
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
        // "6:42:10"; "10:00:00" once a day is within an hour of ten hours.
        timerCharacters = !onBreak && s.workedSoFar >= 9 * 3600 ? 8 : 7
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

    /// Clocking in or out isn't offered for undo: the undo history may still hold an earlier
    /// shift's rows, and "Clocked in · Undo" would quietly take those back. An undo is
    /// confirmed without another Undo button, so a second tap can't look like a redo.
    static func lastAction(_ text: String?, canUndo: Bool) -> LastAction? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("Clocked") { return nil }
        if text.hasPrefix("Undid") { return LastAction(text: text, canUndo: false) }
        return LastAction(text: text, canUndo: canUndo)
    }
}
