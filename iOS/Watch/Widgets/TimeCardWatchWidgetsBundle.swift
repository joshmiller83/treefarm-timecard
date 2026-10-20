import SwiftUI
import WidgetKit

/// The watch's widget extension: the shift complication, in all four accessory families, which
/// is also the shift widget in the Smart Stack (docs/watch.md 4.3).
@main
struct TimeCardWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShiftComplication()
    }
}
