import SwiftUI
import TreeFarmKit

/// Before the watch can do anything (docs/watch.md 3.1, 3.4): signed out on the phone, or the
/// phone never reached. Also carries the Siri note, because a declined Siri opt-in on the watch
/// can't be turned back on yet.
struct SetupScreen: View {
    let model: WatchShiftModel
    let phase: WatchPhase

    @State private var trying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: model.reach == .needsUnlock ? "lock.iphone" : WatchDisplay.Glyph.phone)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(WatchPalette.firBright)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.system(.headline, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setupMessage")

                if phase == .noData {
                    Button {
                        trying = true
                        Task {
                            await model.refresh()
                            trying = false
                        }
                    } label: {
                        GloveLabel(steps: [WatchDisplay.tryAgain], glyph: trying ? "ellipsis" : "arrow.clockwise",
                                   font: .system(.headline, design: .rounded))
                    }
                    .buttonStyle(GloveButtonStyle(tone: .fir, height: ButtonMetrics.current.secondary))
                    .disabled(trying)
                    .accessibilityIdentifier("tryAgain")
                }

                Text(WatchDisplay.siriNote)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(WatchDisplay.appName)
    }

    private var message: String {
        if model.reach == .needsUnlock { return WatchDisplay.unlockPhone }
        return phase == .signedOut ? WatchDisplay.signedOut : WatchDisplay.neverConnected
    }
}
