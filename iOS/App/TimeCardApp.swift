import SwiftUI
import TimeCardCore

@main
struct TimeCardApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Appearance.configure()
        // The shared model is made at launch, scene or not: a message from the Apple Watch can
        // launch the app in the background, and the model's init activates the watch link.
        _ = AppModel.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.session)
                // Text-colored tint: toolbar buttons, menus, pickers and chevrons read at 4.5:1 or
                // more in dark mode too. Controls that fill with white keep `Palette.fir` locally.
                .tint(Palette.firText)
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
                AppDatabase.resume()
                // Woken before the first unlock after a restart, the database was sealed; it opens now.
                if model.storageError != nil { AppModel.reopenIfSealed() }
                if model !== AppModel.shared { model = AppModel.shared }
                Task { await model.sceneBecameActive() }
            case .background:
                model.sceneEnteredBackground()
                AppDatabase.suspend()
            default: break
            }
        }
        .backgroundTask(.appRefresh(AppModel.backgroundRefreshID)) {
            await MainActor.run { AppDatabase.resume() }
            await AppModel.reopenIfSealed().backgroundRefresh()
        }
    }
}
