import SwiftUI
import TimeCardCore

@main
struct TimeCardApp: App {
    @State private var model = AppEnvironment.makeModel()
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
                .task { await model.start() }
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
