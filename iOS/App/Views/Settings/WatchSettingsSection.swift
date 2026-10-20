import SwiftUI
import TimeCardCore

/// Settings › Apple Watch (docs/watch.md 5.5), shown only while a watch is paired: whether
/// Time Card is on it and in reach, and "Record shifts as workouts" (on by default, saved per
/// person on this phone, and sent to the watch at once).
struct WatchSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The status dot, sized and lifted with the text so it sits mid-line at every size.
    @ScaledMetric(relativeTo: .subheadline) private var dotSize: CGFloat = 8
    @ScaledMetric(relativeTo: .subheadline) private var dotLift: CGFloat = 2
    /// What was set here, until the person changes; before that, what's saved for them.
    @State private var chosen: (userId: UUID?, settings: WatchSettings)?

    private var userId: UUID? { session.me?.user.id }

    private var settings: WatchSettings {
        if let chosen, chosen.userId == userId { return chosen.settings }
        return WatchSettings.load(from: session.store, userId: userId)
    }

    var body: some View {
        let status = model.watch.status
        if WatchSettingsWording.isShown(status) {
            card(status)
        }
    }

    private func card(_ status: WatchLinkStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                // The watch glyph is decoration; at the largest sizes the words get the room.
                VStack(alignment: .leading, spacing: 4) {
                    title
                    statusLine(status)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Palette.firText)
                        .frame(width: 40, height: 40)
                        .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    title
                }
                statusLine(status)
            }
            Toggle(isOn: recordBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WatchSettingsWording.recordTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize { detail }
                }
            }
            // The whole row is the switch: a gloved thumb doesn't have to find the knob.
            .toggleStyle(GloveToggleStyle())
            .accessibilityIdentifier("watch-record-workouts")
            if typeSize.isAccessibilitySize { detail }
            Text(WatchSettingsWording.footnote(recordWorkouts: settings.recordWorkouts))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch-footnote")
        }
        .card()
        .accessibilityIdentifier("watch-settings")
    }

    private var title: some View {
        Text("Apple Watch").headingStyle(.tcTitle2).accessibilityAddTraits(.isHeader)
    }

    private var detail: some View {
        Text(WatchSettingsWording.recordDetail)
            .font(.subheadline)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "● Time Card on your watch · in reach": the dot sits in the text, so it stays on the
    /// first line's baseline at every size.
    private func statusLine(_ status: WatchLinkStatus) -> some View {
        (Text(Image(systemName: "circle.fill"))
            .font(.system(size: dotSize))
            .baselineOffset(dotLift)
            .foregroundStyle(WatchSettingsWording.tone(status).dot)
            + Text("  " + WatchSettingsWording.status(status))
            .font(.subheadline)
            .foregroundStyle(Palette.muted))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(WatchSettingsWording.status(status))
            .accessibilityIdentifier("watch-status")
    }

    private var recordBinding: Binding<Bool> {
        Binding {
            settings.recordWorkouts
        } set: { value in
            var next = settings
            next.recordWorkouts = value
            // Per person: a sign-in on this phone brings that person's own choice.
            chosen = (userId, next)
            WatchSettings.save(next, to: session.store, userId: userId)
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
