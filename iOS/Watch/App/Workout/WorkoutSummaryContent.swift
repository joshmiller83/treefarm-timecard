import Foundation
import TreeFarmKit

/// What the shift summary says (docs/watch.md 2.6 and 3.9): worked time and trees from the
/// phone's closed shift (or the watch's own count while the clock-out waits), heart rate and
/// energy from the workout. Never pay. `ShiftDoneScreen` lays it out.
struct WorkoutSummaryContent: Equatable {
    var title = WatchDisplay.shiftDone
    /// The big "8:12".
    var worked: String?
    var workedAccessibility: String?
    /// "worked · 412 trees", or "412 trees · waiting for iPhone".
    var detail: String?
    /// "avg 104 · max 151", beside a heart.
    var heart: String?
    /// "Average heart rate 104, maximum 151": the heart is hidden from VoiceOver.
    var heartAccessibility: String?
    /// "1,120 kcal · 7:41 act.", beside a flame.
    var energy: String?
    /// "1,120 calories, 7 hours 41 minutes active".
    var energyAccessibility: String?

    init(closed: ClosedShift?, summary: WorkoutSummary?, waitingForPhone: Bool) {
        if let closed {
            worked = Fmt.hm(closed.worked)
            workedAccessibility = WatchDisplay.timerAccessibility(closed.worked)
            detail = waitingForPhone ? WatchDisplay.summaryWaitingLine(trees: closed.trees)
                                     : WatchDisplay.summaryWorkedLine(trees: closed.trees)
        }
        if let summary {
            heart = WatchDisplay.summaryHeartLine(avg: summary.avgHeartRate, max: summary.maxHeartRate)
            heartAccessibility = WatchDisplay.summaryHeartAccessibility(avg: summary.avgHeartRate, max: summary.maxHeartRate)
            energy = WatchDisplay.summaryEnergyLine(kcal: summary.activeKcal, active: summary.activeDuration)
            energyAccessibility = WatchDisplay.summaryEnergyAccessibility(kcal: summary.activeKcal, active: summary.activeDuration)
        }
    }
}
