import SwiftUI
import WidgetKit

@main
struct TimeCardWidgetsBundle: WidgetBundle {
    init() {
        WidgetFonts.register()
    }

    var body: some Widget {
        TimeCardLiveActivity()
        if #available(iOS 18.0, *) {
            ClockInControl()
            NextRowControl()
            BreakControl()
        }
    }
}
