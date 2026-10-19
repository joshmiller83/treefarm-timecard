import SwiftUI
import TimeCardCore

/// The Clock tab. (Stand-in until the Clock slice lands.) Settings opens from its gear.
struct ClockView: View {
    @Environment(TimeCardSession.self) private var session
    @State private var showingSettings = false

    var body: some View {
        PlaceholderScreen(title: "Clock", systemImage: "clock",
                          headline: "Clock in, breaks and your next rows",
                          detail: "The big status card with a running timer, lunch and breaks, and the next three rows to shape will live here.") {
            VStack(alignment: .leading, spacing: 10) {
                StatusPill(text: "Off the clock", tone: .off)
                Text(session.farm?.name ?? "")
                    .headingStyle(.tcTitle)
                    .accessibilityIdentifier("clock-farm-name")
                if let name = session.me?.user.displayName {
                    Text("Signed in as \(name)").font(.subheadline).foregroundStyle(Palette.muted)
                }
            }
            .card(padding: 20)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settings-button")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}
