import Foundation

/// The few things Siri says that aren't the result of a field action: the questions it
/// asks, and what it says when the answer is "no". Everything an action itself says comes
/// from TreeFarmKit (`FieldEngine`, `FieldAnswers`, `Speech`, `ShiftRules`).
///
/// Kept short, so an answer is over before the shears are back in hand.
enum VoiceText {
    /// The database is sealed until the phone is unlocked once after a restart.
    static let unlockOnce = "Unlock your phone once, then try again."
    /// "No" to "Clock out?"
    static let stillClockedIn = "Okay, you’re still clocked in."
    /// "No" to "Row 40 in block 2? That’s 26 rows ahead."
    static let nothingMarked = "Okay, nothing marked."

    // Questions. The same words are in each parameter's `requestValueDialog`.
    static let whichRow = "Which row?"
    static let whichBlock = "Which block?"
    static let whichField = "Which field?"
    static let whichTree = "Which tree?"
    static let firstTree = "First tree?"
    static let lastTree = "Last tree?"
    static let whatsTheNote = "What’s the note?"
    static let whatsTheBreakFor = "What’s the break for?"
    static let anyFlag = "Any flag? Needs attention, dead, replant, or none."
    static let whatTime = "What time did you start?"
    static let whatToDo = "Add a note, note a tree, mark trees, or fix your start time?"
}
