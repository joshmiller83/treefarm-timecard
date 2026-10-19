import SwiftUI
import TreeFarmKit

// STUB: slice a replaces
//
// The watch app's entry point. The wiring slice 0 fixed (docs/watch.md 8.3):
// - `WatchAppDelegate` activates the transport, then `ShiftWorkout.shared.recoverIfNeeded()`.
// - `.backgroundTask(.watchConnectivity)` activates the session and completes only once
//   activation is done, `hasContentPending` is false and `await transport.drained()` returns.
// - Every wrist raise after 30 s away lands on the Now page.
@main
struct TimeCardWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}
