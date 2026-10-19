import SwiftUI
import TimeCardCore

/// Makes a single-use invite: pick a role, add a note to remember who it's for, then show
/// the code big enough to read aloud, with a share button.
struct InviteSheet: View {
    var invites: InvitesModel
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var role: Role = .worker
    @State private var note = ""
    @State private var made: InviteInfo?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let made, let code = made.code {
                        madeView(made, code: code)
                    } else {
                        form
                    }
                }
                .teamPage()
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(made == nil ? "Invite Someone" : "Invite Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: made == nil ? .cancellationAction : .confirmationAction) {
                    Button(made == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("invite-done")
                }
            }
            .interactiveDismissDisabled(invites.working)
        }
        .onAppear { invites.error = nil }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("They’ll join \(session.farm?.name ?? "the farm") with the code, their email and a password of their own.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            LabeledGloveField(title: "Who’s it for?", prompt: "A name or job, for your list", text: $note,
                              identifier: "invite-note", footnote: "Optional. Only admins see it.")
            VStack(alignment: .leading, spacing: 10) {
                Text("They join as").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                ChoiceTile(title: Role.worker.teamLabel, detail: Role.worker.teamSummary, systemImage: "person",
                           selected: role == .worker) { role = .worker }
                    .accessibilityIdentifier("invite-role-worker")
                ChoiceTile(title: Role.admin.teamLabel, detail: Role.admin.teamSummary, systemImage: "person.badge.key",
                           selected: role == .admin) { role = .admin }
                    .accessibilityIdentifier("invite-role-admin")
            }
            if let error = invites.error {
                ErrorMessage(text: error)
            }
            Button {
                Task {
                    if let invite = await invites.create(role: role, note: note) {
                        withAnimation(.easeInOut(duration: 0.25)) { made = invite }
                    }
                }
            } label: {
                if invites.working {
                    ProgressView().tint(Palette.firInk)
                } else {
                    Label("Make the invite code", systemImage: "key")
                }
            }
            .buttonStyle(.glovePrimary)
            .disabled(invites.working)
            .accessibilityIdentifier("invite-make")
            Text("A code works once, for 7 days.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
        }
    }

    private func madeView(_ invite: InviteInfo, code: String) -> some View {
        let calendar = FarmCalendar(farm: session.farm ?? Farm(name: "", timeZoneId: TimeZone.current.identifier))
        let who = invite.note.isEmpty ? "" : " for \(invite.note)"
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Palette.fir)
                Text("Invite\(who) is ready").headingStyle(.tcTitle2)
            }
            .accessibilityElement(children: .combine)
            CodeCard(title: "\(invite.role.teamLabel) invite", code: code,
                     expiry: "Works once, until \(Fmt.day(invite.expiresAt, calendar)).",
                     shareText: InviteText.inviteShare(code: code, farmName: session.farm?.name ?? "the farm",
                                                       expiresAt: invite.expiresAt, calendar: calendar),
                     shareTitle: "Time Card invite")
            Text("On the sign-in screen they tap “Join with an invite code.” Dashes and capitals don’t matter.")
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A password reset code for someone who forgot theirs: big, shareable, shown once.
struct ResetCodeSheet: View {
    var member: Member
    var reset: ResetCodeResponse
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let calendar = FarmCalendar(farm: session.farm ?? Farm(name: "", timeZoneId: TimeZone.current.identifier))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(member.displayName) can sign in with this code and pick a new password. Their other devices sign out.")
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    CodeCard(title: "Reset code", code: reset.code,
                             expiry: "Works once, until \(Fmt.day(reset.expiresAt, calendar)) at \(Fmt.time(reset.expiresAt, calendar)).",
                             shareText: InviteText.resetShare(code: reset.code, expiresAt: reset.expiresAt, calendar: calendar),
                             shareTitle: "Time Card reset code")
                    Text("On the sign-in screen they tap “I have a reset code,” then enter their email and this code.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .teamPage()
            }
            .screenBackground()
            .navigationTitle("Reset Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("reset-done")
                }
            }
        }
    }
}
