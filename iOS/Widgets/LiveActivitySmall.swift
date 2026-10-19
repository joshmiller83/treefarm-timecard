import SwiftUI
import TimeCardCore

// STUB: slice c replaces
//
// The Live Activity's `.small` family: the watch Smart Stack card (and CarPlay), 152×69.5 pt
// at 40 mm (docs/watch.md 4.4). One control only. Built into the widget extension and, for
// its tests, into the app. Slice c writes it, test-first, and adds
// `.supplementalActivityFamilies([.small])` with the `activityFamily` branch in
// TimeCardLiveActivity.swift.
struct LiveActivitySmallView: View {
    var state: LiveSnapshot

    var body: some View {
        EmptyView()
    }
}
