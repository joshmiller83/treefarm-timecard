import Foundation
import TreeFarmKit

// STUB: slice c replaces
//
// Reload the complications only when something they show changed (docs/watch.md 4.3):
// `signedIn`, the phase, the first chip, the field, the waiting count going between 0 and more
// than 0, `lastClosedShift`, `usualStart` (and a clock-out starting or stopping to wait).
// A timer tick or a later chip never reloads. Slice c writes it, test-first.
enum ComplicationReload {
    static func needsReload(old: WatchStateFile.Contents?, new: WatchStateFile.Contents) -> Bool {
        old != new
    }
}
