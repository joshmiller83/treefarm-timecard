import SwiftUI
import TimeCardCore

/// Settings, from the gear on the Clock tab: who you are, your name, job and pay, the farm,
/// Siri, the lock screen, sync, and (tucked away) which server to use.
struct SettingsView: View {
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AccountCard()
                    if let member = session.membership {
                        // A fresh form per farm and person, so a switch never carries the last farm's values over.
                        ProfileCard(member: member)
                            .id("\(member.farmId)/\(member.userId)")
                    }
                    FarmCard()
                    VoiceCard().id("voice")
                    LockScreenCard().id("lock")
                    SyncCard().id("sync")
                    AdvancedCard().id("advanced")
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(QuietDestructiveButtonStyle())
                    .accessibilityIdentifier("sign-out")
                    .padding(.top, 8)
                    Text(versionLine)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .task {
                // UI-test screenshots: `-UITestScrollTo voice|lock|sync|advanced`.
                guard LaunchMode.current() != .live, let target = ClockScenario.scrollTarget else { return }
                try? await Task.sleep(for: .seconds(1))
                proxy.scrollTo(target, anchor: .top)
            }
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("settings-done")
                }
            }
            .signOutConfirmation(isPresented: $confirmingSignOut)
        }
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Time Card \(version) (\(build))"
    }
}

// MARK: Signing out

/// "Sign out of Time Card?", the same from Settings and from the no-farm screen.
///
/// Signing out sends waiting changes first. If some still can't reach the server, a second
/// question puts "Sync first" forward and names what signing out anyway would lose.
struct SignOutConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(TimeCardSession.self) private var session
    @State private var working = false
    @State private var unsynced = 0
    @State private var askingAboutUnsynced = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Sign out of Time Card?", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { signOut(discarding: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SignOutWording.warning(pending: session.syncStatus.pendingCount))
            }
            .confirmationDialog(SignOutWording.unsyncedTitle(unsynced), isPresented: $askingAboutUnsynced, titleVisibility: .visible) {
                Button("Sync first") { Task { await session.requestSync(.manual) } }
                    .keyboardShortcut(.defaultAction)
                Button(SignOutWording.loseButton(unsynced), role: .destructive) { signOut(discarding: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(SignOutWording.unsyncedMessage)
            }
            .overlay {
                if working {
                    ProgressView("Sending your changes…")
                        .padding(20)
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .accessibilityIdentifier("signing-out")
                }
            }
            .disabled(working)
    }

    private func signOut(discarding: Bool) {
        working = true
        Task {
            let result = await session.signOut(discardingUnsynced: discarding)
            working = false
            if case .unsynced(let n) = result {
                unsynced = n
                askingAboutUnsynced = true
            }
        }
    }
}

/// What the sign-out questions say.
enum SignOutWording {
    static func warning(pending: Int) -> String {
        guard pending > 0 else { return "This phone forgets the farm until you sign in again." }
        let changes = pending == 1 ? "1 change hasn’t" : "\(pending) changes haven’t"
        return "\(changes) synced yet. Time Card sends \(pending == 1 ? "it" : "them") before signing out."
    }

    static func unsyncedTitle(_ n: Int) -> String {
        n == 1 ? "1 change hasn’t synced" : "\(n) changes haven’t synced"
    }

    static let unsyncedMessage = "They couldn’t reach the server. Sync first to keep them, or sign out and they’re gone from this phone."

    static func loseButton(_ n: Int) -> String {
        n == 1 ? "Sign out and lose 1 change" : "Sign out and lose \(n) changes"
    }
}

extension View {
    func signOutConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(SignOutConfirmation(isPresented: isPresented))
    }
}

// MARK: Account and farm

private struct AccountCard: View {
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // The initials circle is decoration; at the largest sizes the words get the room.
                details
            } else {
                HStack(alignment: .center, spacing: 14) {
                    Text(initials)
                        .font(.tcHeadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(Palette.firText)
                        .frame(width: 54, height: 54)
                        .background(Palette.firSoft, in: Circle())
                        .accessibilityHidden(true)
                    details
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.tcHeadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(session.me?.user.email ?? "")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .truncationMode(.middle)
            if let membership = session.membership {
                let pill = StatusPill(text: membership.role == .admin ? "Admin" : "Crew", tone: membership.role == .admin ? .working : .off)
                    .fixedSize()
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        pill
                        job(membership)
                    }
                    .padding(.top, 2)
                } else {
                    HStack(spacing: 8) {
                        pill
                        job(membership)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func job(_ membership: Member) -> some View {
        if !membership.jobTitle.isEmpty {
            Text(membership.jobTitle)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var name: String {
        session.membership?.displayName ?? session.me?.user.displayName ?? ""
    }

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

private struct FarmCard: View {
    @Environment(TimeCardSession.self) private var session
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    private var choices: [Farm] {
        guard let me = session.me else { return [] }
        let current = Set(me.memberships.filter { $0.removedAt == nil && $0.userId == me.user.id }.map(\.farmId))
        return me.farms.filter { current.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Farm")
            if choices.count > 1, let farm = session.farm {
                Picker("Farm", selection: Binding(get: { farm.id }, set: { id in Task { await session.selectFarm(id) } })) {
                    ForEach(choices) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .tint(Palette.firText)
                .frame(minHeight: GloveButtonStyle.minHeight)
            } else {
                Text(session.farm?.name ?? "")
                    .font(.tcHeadline)
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("settings-farm-name")
            }
            if let farm = session.farm {
                Label(farm.timeZoneId.replacingOccurrences(of: "_", with: " "), systemImage: "globe.americas")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                Label("Weeks start on \(Self.weekdays[farm.weekStart.rawValue - 1])", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
        .card()
    }
}

// MARK: Sync

private struct SyncCard: View {
    @Environment(TimeCardSession.self) private var session

    var body: some View {
        let status = session.syncStatus
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Sync")
            StatusPill(text: pillText(status), tone: tone(status))
            Text(status.summary)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
                .accessibilityIdentifier("sync-summary")
            if let last = status.lastSyncedAt {
                Text("Last synced \(Text(last, style: .relative)) ago")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
            if let error = status.lastError, status.phase != .idle {
                ErrorMessage(text: error)
            }
            Text("Everything saves on this phone first, so it works with no signal and catches up when you’re back in range.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await session.requestSync(.manual) }
            } label: {
                Label(status.phase == .syncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.gloveSecondary)
            .disabled(status.phase == .syncing || status.phase == .signedOut)
        }
        .card()
    }

    private func pillText(_ status: SyncStatus) -> String {
        switch status.phase {
        case .idle: status.pendingCount == 0 ? "Up to date" : "Waiting"
        case .syncing: "Syncing"
        case .offline: "Offline"
        case .failed: "Trouble syncing"
        case .signedOut: "Signed out"
        }
    }

    private func tone(_ status: SyncStatus) -> StatusPill.Tone {
        switch status.phase {
        case .idle: status.pendingCount == 0 ? .working : .onBreak
        case .syncing: .working
        case .offline: .off
        case .failed, .signedOut: .alert
        }
    }
}

/// Sign out: rust text and outline on the surface, readable in both themes and quieter
/// than a solid red slab at the bottom of the screen.
struct QuietDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Palette.rust)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rust.opacity(0.6), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .pressScale(configuration.isPressed, 0.98)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
