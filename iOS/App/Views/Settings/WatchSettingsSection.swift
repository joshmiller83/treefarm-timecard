import SwiftUI
import TimeCardCore

/// Settings › Apple Watch (docs/watch.md 5.5), shown only while a watch is paired: whether
/// Time Card is on it and in reach, and "Record shifts as workouts" (on by default, saved per
/// person on this phone, and sent to the watch at once).
struct WatchSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(TimeCardSession.self) private var session
    @State private var settings = WatchSettings()

    private var userId: UUID? { session.me?.user.id }

    var body: some View {
        let status = model.watch.status
        if WatchSettingsWording.isShown(status) {
            card(status)
                // Per person: a sign-in on this phone brings that person's choice.
                .task(id: userId) { settings = WatchSettings.load(from: session.store, userId: userId) }
        }
    }

    private func card(_ status: WatchLinkStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "applewatch")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .frame(width: 40, height: 40)
                    .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Watch").headingStyle(.tcTitle2).accessibilityAddTraits(.isHeader)
                    statusLine(status)
                }
            }
            Toggle(isOn: recordBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WatchSettingsWording.recordTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(WatchSettingsWording.recordDetail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.fir)
            .frame(minHeight: GloveButtonStyle.minHeight)
            .contentShape(Rectangle())
            .accessibilityIdentifier("watch-record-workouts")
            Text(WatchSettingsWording.footnote(recordWorkouts: settings.recordWorkouts))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch-footnote")
        }
        .card()
        .accessibilityIdentifier("watch-settings")
    }

    private func statusLine(_ status: WatchLinkStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(WatchSettingsWording.tone(status).dot)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(WatchSettingsWording.status(status))
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch-status")
    }

    private var recordBinding: Binding<Bool> {
        Binding {
            settings.recordWorkouts
        } set: { value in
            settings.recordWorkouts = value
            WatchSettings.save(settings, to: session.store, userId: userId)
            // The watch hears at once: the desk reads the setting on every state it makes.
            model.watch.publish(reason: .settingsChanged)
        }
    }
}

/// What the Apple Watch section says.
enum WatchSettingsWording {
    static let recordTitle = "Record shifts as workouts"
    static let recordDetail = "Clock-in starts an Other workout on your watch, lunch and breaks pause it, and clock-out ends it."

    /// Shown only with a watch paired.
    static func isShown(_ status: WatchLinkStatus) -> Bool {
        status != .noWatch
    }

    /// "Time Card on your watch · in reach".
    static func status(_ status: WatchLinkStatus) -> String {
        switch status {
        case .inReach: "Time Card on your watch · in reach"
        case .outOfReach: "Time Card on your watch · out of reach"
        case .appNotInstalled: "Time Card on your watch · not installed: install it from the Watch app"
        case .noWatch: "No Apple Watch paired"
        }
    }

    static func tone(_ status: WatchLinkStatus) -> StatusPill.Tone {
        switch status {
        case .inReach: .working
        case .outOfReach, .noWatch: .off
        case .appNotInstalled: .alert
        }
    }

    /// The workouts' promise, and what turning them off costs.
    static func footnote(recordWorkouts: Bool) -> String {
        let promise = "Workouts keep Time Card on your watch all shift and log heart rate and calories in Health. They never go to the farm."
        return recordWorkouts ? promise : promise + " The Action button needs workouts on."
    }
}
