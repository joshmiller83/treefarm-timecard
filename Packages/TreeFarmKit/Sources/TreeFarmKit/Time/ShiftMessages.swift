import Foundation

/// What the shift editor says when a whole shift is added, saved or deleted. Everything about
/// the times themselves comes from `ShiftRules`.
public enum ShiftMessages {
    public static let added = "Shift added."
    public static let saved = "Shift saved."
    /// The shift is gone from this phone (deleted elsewhere and synced).
    public static let missing = "This shift isn’t on this phone anymore. It may have been deleted on another device."
    /// Saving a shift the person didn't change.
    public static let unchanged = "No changes to save."
    /// The shift changed elsewhere (Siri, the lock screen, another phone) in a part the person
    /// also changed; the editor shows the stored value there.
    public static let changedElsewhere = "This shift changed while you had it open. Check it and save again."
    /// Cancel with changes.
    public static let discardQuestion = "Discard your changes to this shift?"

    /// The question before deleting: what goes with the shift.
    public static func deleteQuestion(trees: Int, isOpen: Bool) -> String {
        var parts = ["Delete this shift?"]
        if isOpen { parts.append("You’re still clocked in on it.") }
        parts.append(trees > 0
            ? "Its \(Fmt.plural(trees, "tree")) will be unmarked on the map too."
            : "Its hours come off your time card.")
        parts.append("This can’t be undone.")
        return parts.joined(separator: " ")
    }

    /// The button that really deletes.
    public static func deleteButton(trees: Int) -> String {
        trees > 0 ? "Delete shift and \(Fmt.plural(trees, "tree"))" : "Delete shift"
    }

    /// What the Log says once it's gone.
    public static func deleted(trees: Int) -> String {
        trees > 0 ? "Shift deleted. \(Fmt.plural(trees, "tree")) unmarked." : "Shift deleted."
    }
}
