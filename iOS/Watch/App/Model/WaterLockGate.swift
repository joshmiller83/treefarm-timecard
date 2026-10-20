import WatchKit

/// The rain lock (Water Lock) stops phantom taps from wet needles or sap. It shows only while a
/// workout session runs, the app is in the foreground, and the watch is rated for water beyond
/// splashes (`.wr50`, and the Ultra's `.wr100`): an `.ipx7` watch has no Water Lock
/// (docs/watch.md 3.5). The person unlocks it by turning the crown.
enum WaterLockGate {
    static func isAvailable(rating: WKWaterResistanceRating, sessionActive: Bool, foreground: Bool) -> Bool {
        guard sessionActive, foreground else { return false }
        switch rating {
        case .wr50, .wr100: return true
        case .ipx7: return false
        @unknown default: return false
        }
    }
}
