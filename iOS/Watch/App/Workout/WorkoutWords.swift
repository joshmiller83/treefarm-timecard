import Foundation
import TreeFarmKit

/// The workout screens' words that `WatchDisplay` doesn't have yet: what VoiceOver says for the
/// numbers beside the heart and flame glyphs (which it skips), and the paused line.
///
/// The lead is asked to move these into `WatchDisplay` under the same names (slice 0 owns it);
/// then this file goes and the call sites say `WatchDisplay.` instead of `WorkoutWords.`.
enum WorkoutWords {
    /// The Today line while lunch or a break pauses the workout.
    static let paused = "Workout paused"

    /// "Average heart rate 104, maximum 151" for the summary's "avg 104 · max 151".
    static func summaryHeartAccessibility(avg: Double?, max: Double?) -> String? {
        switch (avg.map(bpm), max.map(bpm)) {
        case let (avg?, max?): "Average heart rate \(avg), maximum \(max)"
        case let (avg?, nil): "Average heart rate \(avg)"
        case let (nil, max?): "Maximum heart rate \(max)"
        case (nil, nil): nil
        }
    }

    /// "1,120 calories, 7 hours 41 minutes active" for the summary's "1,120 kcal · 7:41 act.",
    /// with the minutes the screen shows (cut, not rounded).
    static func summaryEnergyAccessibility(kcal: Double?, active: TimeInterval) -> String {
        let minutes = TimeInterval(Int(max(0, active)) / 60 * 60)
        let time = "\(Fmt.spokenDuration(minutes)) active"
        guard let kcal else { return time }
        return "\(calories(kcal)), \(time)"
    }

    /// "Heart rate 104, 612 calories" for the live "104 bpm · 612 kcal".
    static func heartLineAccessibility(bpm: Double?, kcal: Double?) -> String? {
        let parts = [bpm.map { "Heart rate \(Self.bpm($0))" }, kcal.map(calories)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func bpm(_ value: Double) -> Int { Int(value.rounded()) }

    private static func calories(_ kcal: Double) -> String { Fmt.plural(Int(kcal.rounded()), "calorie") }
}
