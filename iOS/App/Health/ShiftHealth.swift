import Foundation
import TimeCardCore

// A shift's Health card (docs/health.md 4): what Apple Health recorded over the time worked,
// with lunch and breaks cut out. It works whichever app recorded the shift (Time Card's Tree
// care workout, Gentler Streak, or none), and it stays on this phone: nothing here syncs.

/// What Health has for one shift's worked time. Each is nil when Health has none.
struct ShiftHealth: Equatable, Sendable {
    var steps: Double?
    var distanceMeters: Double?
    var flights: Double?
    var activeKcal: Double?
    var avgHeartRate: Double?
    var maxHeartRate: Double?

    var isEmpty: Bool {
        [steps, distanceMeters, flights, activeKcal, avgHeartRate, maxHeartRate].allSatisfy { $0 == nil }
    }
}

/// Reads a shift's numbers from Health. `HealthKitShiftHealthReader` is the real one; UI tests
/// and test hosts use `DemoShiftHealthReader`, which never prompts.
@MainActor
protocol ShiftHealthReader: AnyObject {
    /// False on a device without Health (an iPad): the Log shows no Health button.
    var isAvailable: Bool { get }
    /// Health was never asked for what the card reads.
    func needsPermission() async -> Bool
    func requestPermission() async
    /// Health's own totals over the spans, so steps from the iPhone and the watch count once.
    func read(_ spans: [DateInterval]) async -> ShiftHealth
}

/// What the card says. Every line is made here, so it's tested without Health.
enum ShiftHealthWording {
    struct Stat: Equatable, Identifiable {
        var label: String
        var value: String
        /// What VoiceOver says: the value in words.
        var spoken: String
        var id: String { label }
    }

    static let title = "Health"
    static let button = "Health"
    static let permissionTitle = "See your shift’s steps, distance and heart rate"
    static let permissionBody = "Time Card reads them from Apple Health for the time you worked. They stay on this iPhone and are never sent to the farm."
    static let allow = "Allow Health"
    static let empty = "No Health data for this shift. If you expected some, check Health › Sharing › Apps › Time Card."
    static let footnote = "From Apple Health, for the time you worked: lunch and breaks are left out. It stays on this iPhone and is never sent to the farm."

    /// Miles or kilometers, by the phone's region.
    static var miles: Bool { Locale.current.measurementSystem != .metric }

    /// The numbers Health has, in the card's order.
    static func stats(_ health: ShiftHealth, miles: Bool = miles) -> [Stat] {
        var stats: [Stat] = []
        if let steps = health.steps {
            let n = Int(steps.rounded())
            stats.append(Stat(label: "Steps", value: Fmt.count(n), spoken: Fmt.plural(n, "step")))
        }
        if let meters = health.distanceMeters {
            stats.append(Stat(label: "Distance", value: Fmt.distance(meters: meters, miles: miles),
                              spoken: Fmt.spokenDistance(meters: meters, miles: miles)))
        }
        if let flights = health.flights {
            let n = Int(flights.rounded())
            stats.append(Stat(label: "Flights climbed", value: Fmt.count(n), spoken: Fmt.plural(n, "flight")))
        }
        if let kcal = health.activeKcal {
            let n = Int(kcal.rounded())
            stats.append(Stat(label: "Active calories", value: "\(Fmt.count(n)) kcal", spoken: Fmt.plural(n, "calorie")))
        }
        if let heart = WatchDisplay.summaryHeartLine(avg: health.avgHeartRate, max: health.maxHeartRate) {
            stats.append(Stat(label: "Heart rate", value: heart,
                              spoken: WatchDisplay.summaryHeartAccessibility(avg: health.avgHeartRate, max: health.maxHeartRate) ?? heart))
        }
        return stats
    }

    /// "Tree care workout · 7:41 active", when the watch sent its workout's summary.
    static func workoutLine(_ summary: WorkoutSummary?) -> String? {
        guard let summary else { return nil }
        return "\(ShiftWorkoutType.treeCare.name) workout · \(Fmt.hm(summary.activeDuration)) active"
    }
}

/// Made-up numbers for UI tests and test hosts: no Health, no prompts.
@MainActor
final class DemoShiftHealthReader: ShiftHealthReader {
    var isAvailable: Bool { true }
    func needsPermission() async -> Bool { false }
    func requestPermission() async {}

    func read(_ spans: [DateInterval]) async -> ShiftHealth {
        let minutes = spans.reduce(0) { $0 + $1.duration } / 60
        guard minutes > 0 else { return ShiftHealth() }
        return ShiftHealth(steps: minutes * 18, distanceMeters: minutes * 12, flights: (minutes / 40).rounded(),
                           activeKcal: minutes * 2.4, avgHeartRate: 104, maxHeartRate: 151)
    }
}
