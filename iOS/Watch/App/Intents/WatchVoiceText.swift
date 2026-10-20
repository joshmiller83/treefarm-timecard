import Foundation
import TreeFarmKit

/// What Siri on the watch says that isn't the phone's sentence or already in `WatchDisplay`:
/// the status answer from the watch's cache, with "as of" the time the phone last said.
enum WatchVoiceText {
    /// Whether a question came back with an answer (not the watch's "needs your phone").
    static func isAnswer(_ text: String) -> Bool {
        !text.isEmpty && text != WatchDisplay.askNeedsPhone && text != WatchDisplay.neverConnected
    }

    /// "3 hours 41 minutes today, 38 trees, 34 an hour. Next is row 14 in block 2. That’s as of 10:42."
    static func cachedStatus(_ state: WatchState?, now: Date) -> String {
        guard let state else { return WatchDisplay.neverConnected }
        guard state.signedIn else { return WatchDisplay.signedOut }
        // While working, the day kept counting since the phone said.
        let running = state.snapshot?.phase == .working ? max(0, now.timeIntervalSince(state.updatedAt)) : 0
        let worked = state.todayWorked + running
        var sentences: [String] = []
        if worked < 60 {
            sentences.append("You haven’t worked yet today.")
        } else {
            let trees = state.todayTrees == 0 ? "no trees yet" : Fmt.plural(state.todayTrees, "tree")
            let pace = state.pacePerHour.map { "\(Speech.rate($0)) an hour" }
            sentences.append([Fmt.spokenDuration(worked) + " today", trees, pace].compactMap { $0 }.joined(separator: ", ") + ".")
        }
        if let chip = state.nextRows.first {
            sentences.append("Next is \(WatchDisplay.chipValue(chip).lowercasedFirst).")
        } else if state.isClockedIn {
            sentences.append(WatchDisplay.noChipLine(state))
        }
        sentences.append("That’s \(WatchDisplay.asOf(state.updatedAt, state: state)).")
        return sentences.joined(separator: " ")
    }
}

private extension String {
    /// "Row 14 in block 2" → "row 14 in block 2".
    var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}
