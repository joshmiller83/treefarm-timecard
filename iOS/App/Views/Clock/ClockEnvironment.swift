import SwiftUI

/// Switches the main tabs, for buttons like "Open the map". `MainTabView` provides it;
/// where it's missing (previews, tests) those buttons stay hidden rather than doing nothing.
struct OpenTabAction: Sendable {
    let action: @MainActor @Sendable (AppTab) -> Void

    init(_ action: @escaping @MainActor @Sendable (AppTab) -> Void) {
        self.action = action
    }

    @MainActor
    func callAsFunction(_ tab: AppTab) {
        action(tab)
    }
}

extension EnvironmentValues {
    @Entry var openTab: OpenTabAction?
}
