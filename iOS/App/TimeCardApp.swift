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
                // Again for a model that replaced one that couldn't open its database.
                .task(id: ObjectIdentifier(model)) {
                    await model.start()
                    // Siri learns the rows, blocks and fields by name, and follows the farm from here on.
                    SiriSuggestions.shared.follow(model)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Woken before the first unlock after a restart, the database was sealed; it opens now.
                if model.storageError != nil { AppModel.reopenIfSealed() }
                if model !== AppModel.shared { model = AppModel.shared }
                Task { await model.sceneBecameActive() }
            case .background: model.sceneEnteredBackground()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppModel.backgroundRefreshID)) {
            await AppModel.reopenIfSealed().backgroundRefresh()
        }
    }
}
