import SwiftUI
import TimeCardCore

/// Account, farm, sync status and sign out.
struct SettingsView: View {
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AccountCard()
                    FarmCard()
                    SyncCard()
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.gloveDestructive)
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
            .screenBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("settings-done")
                }
            }
            .confirmationDialog("Sign out of Time Card?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(signOutWarning)
            }
        }
    }

    private var signOutWarning: String {
        let pending = session.syncStatus.pendingCount
        if pending > 0 {
            let changes = pending == 1 ? "1 change hasn't" : "\(pending) changes haven't"
            return "\(changes) synced yet. Signing out now removes \(pending == 1 ? "it" : "them") from this phone."
        }
        return "This phone forgets the farm until you sign in again."
    }

    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Time Card \(version) (\(build))"
    }
}

private struct AccountCard: View {
    @Environment(TimeCardSession.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Account")
            Text(session.membership?.displayName ?? session.me?.user.displayName ?? "")
                .font(.tcHeadline)
                .foregroundStyle(Palette.ink)
            Text(session.me?.user.email ?? "")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            if let membership = session.membership {
                HStack(spacing: 8) {
                    StatusPill(text: membership.role == .admin ? "Admin" : "Crew", tone: membership.role == .admin ? .working : .off)
                    if !membership.jobTitle.isEmpty {
                        Text(membership.jobTitle).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct FarmCard: View {
    @Environment(TimeCardSession.self) private var session

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
            }
        }
        .card()
    }
}

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
