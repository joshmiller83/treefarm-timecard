import ActivityKit
import AppIntents
import SwiftUI
import TimeCardCore
import UIKit

// MARK: Your details

/// Your name, job and hourly pay on this farm. They print on your time card (pay never does).
struct ProfileCard: View {
    var member: Member
    @Environment(TimeCardSession.self) private var session
    @State private var form: ProfileForm
    @State private var message: Message?
    @FocusState private var field: Field?

    private enum Field { case name, job, rate }
    private enum Message: Equatable {
        case saved(String)
        case problem(String)
    }

    init(member: Member) {
        self.member = member
        _form = State(initialValue: ProfileForm(member: member))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Your details")
            labeled("Your name") {
                TextField("Name", text: $form.name)
                    .textFieldStyle(.glove)
                    .textContentType(.name)
                    .focused($field, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { field = .job }
                    .accessibilityLabel("Your name")
                    .accessibilityIdentifier("profile-name")
            }
            labeled("Job") {
                TextField("Tree trimming", text: $form.job)
                    .textFieldStyle(.glove)
                    .textContentType(.jobTitle)
                    .focused($field, equals: .job)
                    .submitLabel(.next)
                    .onSubmit { field = .rate }
                    .accessibilityLabel("Job")
                    .accessibilityIdentifier("profile-job")
            }
            labeled("Hourly pay") {
                HStack(spacing: 6) {
                    Text("$")
                        .font(.tcNumber)
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                    TextField("18.00", text: $form.rate)
                        .font(.tcNumber)
                        .keyboardType(.decimalPad)
                        .focused($field, equals: .rate)
                        // The whole 54 pt box takes the tap, not just the line of text.
                        .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
                        .accessibilityLabel("Hourly pay in dollars")
                        .accessibilityIdentifier("profile-rate")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: GloveButtonStyle.minHeight)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { field = .rate }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            }
            Text("Your name and job print on your time card. Pay is only for your totals here; it never shows on the report. \(RateChange.footnote)")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            switch message {
            case .saved(let text):
                Label(text, systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Palette.firText)
                    .accessibilityIdentifier("profile-saved")
                    .task(id: text) { Announcer.say(text) }
            case .problem(let text):
                ErrorMessage(text: text)
            case nil:
                EmptyView()
            }
            Button("Save my details", action: save)
                .buttonStyle(.glovePrimary)
                .disabled(!form.isChanged(from: member))
                .accessibilityIdentifier("profile-save")
        }
        .card()
        .onChange(of: form) { if message != nil { withAnimation { message = nil } } }
        .onChange(of: member) { old, new in
            // Someone (an admin, another phone) changed it: show theirs unless you're editing.
            if let fresh = form.refreshed(from: old, to: new, editing: field != nil) { form = fresh }
        }
        .toolbar {
            if field == .rate {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { field = nil }.fontWeight(.semibold)
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            content()
        }
    }

    private func save() {
        field = nil
        if let problem = form.problem {
            withAnimation { message = .problem(problem) }
            return
        }
        let open = session.snapshot.openShift(for: member.userId)
        let records = form.records(for: member, openShift: open, now: Date())
        guard !records.isEmpty else { return }
        do {
            try session.save(records)
            form = ProfileForm(member: session.membership ?? member)
            withAnimation { message = .saved("Saved. It syncs to the farm next.") }
        } catch {
            withAnimation { message = .problem("Couldn’t save on this phone. Try again.") }
        }
    }
}

// MARK: Siri

/// How Siri behaves, and what to say. Both switches start off: quick and private.
struct VoiceCard: View {
    @Environment(TimeCardSession.self) private var session
    @State private var prefs = VoicePreferences()
    @State private var loaded = false
    @State private var problem: String?
    @State private var showingAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.firText)
                    .frame(width: 40, height: 40)
                    .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Siri").headingStyle(.tcTitle2).accessibilityAddTraits(.isHeader)
                    Text("Works with the phone locked, gloves on, and over AirPods.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            toggle("Ask for a break reason",
                   detail: "When you start a break by voice, Siri asks what it’s for.",
                   isOn: $prefs.askBreakReason, id: "ask-break-reason")
            Divider().overlay(Palette.line)
            toggle("Say pay out loud when locked",
                   detail: "Otherwise Siri asks you to unlock first, since people nearby can hear.",
                   isOn: $prefs.sayPayWhenLocked, id: "say-pay-locked")
            if let problem { ErrorMessage(text: problem) }

            SectionLabel("Try saying")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(phrases.enumerated()), id: \.element) { index, example in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("“\(example.phrase)”")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Text(example.does)
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Palette.line).frame(height: 1) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("siri-phrases")
            if !showingAll {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showingAll = true }
                } label: {
                    Label("More things to say", systemImage: "chevron.down")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityIdentifier("more-phrases")
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: GloveButtonStyle.minHeight)
            Text("In Shortcuts you can put any of these on the Action button, which works with gloves.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .onAppear {
            guard !loaded else { return }
            prefs = VoicePreferences.load(from: session.store)
            loaded = true
        }
        .onChange(of: prefs) { _, new in
            guard loaded else { return }
            do {
                try new.save(to: session.store)
                problem = nil
            } catch {
                problem = Speech.saveFailed
            }
        }
    }

    private var phrases: [SiriPhrases.Example] {
        showingAll ? SiriPhrases.examples : Array(SiriPhrases.examples.prefix(5))
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.fir)
        .frame(minHeight: GloveButtonStyle.minHeight)
        .contentShape(Rectangle())
        .accessibilityIdentifier(id)
    }
}

// MARK: Lock screen

/// Whether Live Activities are on, and how to turn them on.
struct LockScreenCard: View {
    @State private var enabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    label
                    pill
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    label
                    Spacer()
                    pill
                }
            }
            Text(enabled
                 ? "While you’re clocked in, your timer, next three rows and a Break button show on the lock screen. There’s no Clock out there, so a pocket tap can’t end your shift."
                 : "Turn on Live Activities for Time Card to see your timer and tap your next rows from the lock screen.")
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if enabled {
                Text("iPhone ends a Live Activity after 8 hours. Open Time Card and it starts again.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open iPhone Settings", systemImage: "gear")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityIdentifier("open-ios-settings")
            }
        }
        .card()
        .task {
            for await value in ActivityAuthorizationInfo().activityEnablementUpdates {
                withAnimation { enabled = value }
            }
        }
    }

    /// Never broken mid-word: it shrinks a little before it would wrap.
    private var label: some View {
        SectionLabel("Lock screen")
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var pill: some View {
        StatusPill(text: enabled ? "Live Activities on" : "Live Activities off", tone: enabled ? .working : .alert)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityIdentifier("live-activities-status")
    }
}

// MARK: Advanced

/// Which server to use. Most people never open this.
struct AdvancedCard: View {
    @Environment(TimeCardSession.self) private var session
    @State private var open = false
    @State private var text = ServerAddress.saved()?.absoluteString ?? ""
    @State private var saved = ServerAddress.saved()
    @State private var problem: String?

    private var inUse: URL { AppEnvironment.serverInUse }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { open.toggle() }
            } label: {
                HStack {
                    SectionLabel("Advanced")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced")
            .accessibilityValue(open ? "Shown" : "Hidden")
            .accessibilityIdentifier("advanced-toggle")

            if open && !ServerAddress.isEditable {
                Text("Server")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(inUse.absoluteString)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("server-in-use")
                Text("Your farm’s records sync with this server.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else if open {
                Text("Server")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                TextField(TimeCardCore.defaultServerURL.absoluteString, text: $text)
                    .textFieldStyle(.glove)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: text) { problem = nil }
                    .accessibilityIdentifier("server-url")
                Text("Using \(inUse.absoluteString)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("server-in-use")
                // What's saved (`saved` redraws this card) decides the next launch's server.
                let next = AppEnvironment.serverURL
                if next != inUse {
                    Text(switchNotice(to: next))
                        .font(.footnote)
                        .foregroundStyle(Palette.sapInk)
                        .padding(10)
                        .background(Palette.sapSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("server-switch-notice")
                }
                if let problem { ErrorMessage(text: problem) }
                HStack(spacing: 10) {
                    Button("Save", action: save)
                        .buttonStyle(.gloveSecondary)
                        .accessibilityIdentifier("server-save")
                    if saved != nil {
                        Button("Use the standard server") {
                            ServerAddress.save(nil)
                            saved = nil
                            text = ""
                        }
                        .buttonStyle(.gloveSecondary)
                    }
                }
                Text("Only change this if whoever runs your farm’s server asks you to.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    /// Switching signs out of the server in use, and changes still waiting to sync stay behind.
    private func switchNotice(to server: URL) -> String {
        var notice = "Time Card switches to \(server.host() ?? server.absoluteString) the next time it opens. You’ll sign in there."
        let pending = session.syncStatus.pendingCount
        if pending > 0 {
            notice += " " + (pending == 1 ? "1 change hasn’t" : "\(pending) changes haven’t")
                + " reached \(inUse.host() ?? inUse.absoluteString) yet. Let \(pending == 1 ? "it" : "them") sync before you close Time Card, or \(pending == 1 ? "it’s" : "they’re") left behind."
        }
        return notice
    }

    private func save() {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            ServerAddress.save(nil)
            saved = nil
            return
        }
        switch ServerAddress.parse(text) {
        case .success(let url):
            let standard = url == TimeCardCore.defaultServerURL
            ServerAddress.save(standard ? nil : url)
            saved = standard ? nil : url
            text = standard ? "" : url.absoluteString
        case .failure(let failure):
            withAnimation { problem = failure.message }
        }
    }
}
