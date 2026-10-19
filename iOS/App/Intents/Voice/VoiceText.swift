import Foundation
import TimeCardCore

/// The few things Siri says that aren't the result of a field action: the questions it
/// asks, and what it says when the answer is "no". Everything an action itself says comes
/// from TreeFarmKit (`FieldEngine`, `FieldAnswers`, `Speech`, `ShiftRules`).
///
/// Kept short, so an answer is over before the shears are back in hand.
enum VoiceText {
    // What Siri says when nothing happens lives in TreeFarmKit's `Speech`, with every other
    // sentence the app, Siri and the lock screen say.
    static let unlockOnce = Speech.unlockOnce
    static let stillClockedIn = Speech.stillClockedIn
    static let nothingMarked = Speech.nothingMarked
    static let nothingNoted = Speech.nothingNoted

    // Questions. The same words are in each parameter's `requestValueDialog`.
    static let whichRow = "Which row?"
    static let whichBlock = "Which block?"
    static let whichTree = "Which tree?"
    static let firstTree = "First tree?"
    static let lastTree = "Last tree?"
    static let whatsTheNote = "What’s the note?"
    static let whatsTheBreakFor = "What’s the break for?"
    static let anyFlag = "Any flag? Needs attention, dead, replant, or none."
    static let whatTime = "What time did you start?"
}
