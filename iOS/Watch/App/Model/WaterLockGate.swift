import WatchKit

// STUB: slice a replaces
//
// The rain lock (Water Lock) shows only while a workout session runs, the app is in the
// foreground, and the watch isn't `.ipx7` (docs/watch.md 3.5).
enum WaterLockGate {
    static func isAvailable(rating: WKWaterResistanceRating, sessionActive: Bool, foreground: Bool) -> Bool {
        false
    }
}
