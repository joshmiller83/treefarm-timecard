import SwiftUI
import TreeFarmKit

// STUB: slice a replaces
//
// NavigationStack: SetupScreen (signed out / never connected), OffClockScreen (one page),
// or on the clock a horizontal TabView(.page): Controls ← Now → Today (docs/watch.md 3.1).
struct WatchRootView: View {
    @State private var model = WatchShiftModel.shared

    var body: some View {
        let phase = WatchDisplay.phase(model.displayed)
        VStack(spacing: 8) {
            Image(systemName: WatchDisplay.phaseGlyph(phase))
            Text(WatchDisplay.phaseTitle(phase))
                .font(.headline)
            if phase == .noData {
                Text(WatchDisplay.neverConnected)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
