import SwiftUI
import TimeCardCore

@main
struct TimeCardApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.session)
                .tint(Palette.fir)
                .task {
                    await model.start()
                    // Siri learns the rows, blocks and fields by name, and follows the farm from here on.
                    SiriSuggestions.shared.follow(model)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.sceneBecameActive() }
            case .background: model.sceneEnteredBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppModel.backgroundRefreshID)) {
            await model.backgroundRefresh()
        }
    }
}
