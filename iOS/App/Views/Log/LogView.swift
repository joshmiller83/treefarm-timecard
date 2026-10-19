import SwiftUI
import TimeCardCore

/// The Log tab. (Stand-in until its slice lands.)
struct LogView: View {
    var body: some View {
        PlaceholderScreen(title: "Log", systemImage: "list.bullet.rectangle",
                          headline: "Every shift, week by week",
                          detail: "Your shifts grouped by week with totals, and an editor for times, breaks and notes.")
    }
}
