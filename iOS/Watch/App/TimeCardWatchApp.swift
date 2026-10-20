import SwiftUI
import TreeFarmKit

/// The watch app (docs/watch.md 1.4, 3). `WatchAppDelegate` activates the model at launch.
/// A WatchConnectivity background wake activates the session and completes only once activation
/// is done, nothing is pending and every delivered state was handled (and the complications
/// written), so the system doesn't suspend the app halfway through.
@main
struct TimeCardWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .backgroundTask(.watchConnectivity) {
            await WatchShiftModel.shared.handleBackgroundWake()
        }
    }
}
