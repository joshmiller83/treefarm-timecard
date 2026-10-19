import Foundation
import TimeCardCore

/// The Log's own sentences, for things TreeFarmKit has no wording for yet (saving and
/// deleting a whole shift). Everything about times and rules comes from `ShiftRules`.
enum LogWording {
    static let added = "Shift added."
    static let saved = "Shift saved."
    static let missing = "This shift isn’t on this phone anymore. It may have been deleted on another device."

    /// The question before deleting: what goes with the shift.
    static func deleteQuestion(trees: Int, isOpen: Bool) -> String {
        var parts = ["Delete this shift?"]
        if isOpen { parts.append("You’re still clocked in on it.") }
        parts.append(trees > 0
            ? "Its \(Fmt.plural(trees, "tree")) will be unmarked on the map too."
            : "Its hours come off your time card.")
        parts.append("This can’t be undone.")
        return parts.joined(separator: " ")
    }

    /// The button that really deletes.
    static func deleteButton(trees: Int) -> String {
        trees > 0 ? "Delete shift and \(Fmt.plural(trees, "tree"))" : "Delete shift"
    }

    /// What the log says once it's gone.
    static func deleted(trees: Int) -> String {
        trees > 0 ? "Shift deleted. \(Fmt.plural(trees, "tree")) unmarked." : "Shift deleted."
    }
}
