import Foundation

/// Catches obvious failures from the watch's cached state, so a command that is bound to fail
/// isn't queued while the phone is away. Used **only when the phone is unreachable**: with the
/// phone in reach, the phone decides. The sentences are the engine's, so the watch says what
/// the phone would.
public enum WatchPrecheck {
    public static func refusal(for command: FieldCommand, state: WatchState?) -> String? {
        guard let state else { return WatchDisplay.neverConnected }
        guard state.signedIn else { return WatchDisplay.signedOut }
        let snapshot = state.snapshot
        switch command {
        case .clockIn:
            guard snapshot != nil else { return nil }
            guard let start = state.shiftStart else { return "You’re already clocked in." }
            return "You’re already clocked in since \(Fmt.spokenTime(start, state.calendar))."
        case .clockOut, .markRow, .markTrees, .markNextRow, .addShiftNote:
            return snapshot == nil ? Speech.notClockedIn : nil
        case .cancelShift(let id):
            guard snapshot != nil else { return Speech.notClockedIn }
            guard state.shiftId == nil || state.shiftId == id else {
                return "That shift isn’t the one on the clock, so nothing was cancelled."
            }
            return nil
        case .startBreak:
            guard let snapshot else { return Speech.notClockedIn }
            guard snapshot.phase != .working, let since = snapshot.breakStart else { return nil }
            let what = snapshot.phase == .lunch ? "lunch" : "a break"
            return "You’re already on \(what) since \(Fmt.spokenTime(since, state.calendar)). Say “back to work” when you’re done."
        case .endBreak:
            guard let snapshot else { return Speech.notClockedIn }
            return snapshot.phase == .working ? "You’re not on a break." : nil
        case .moveTo, .addTreeNote, .changeStart, .undo:
            return nil
        }
    }
}
