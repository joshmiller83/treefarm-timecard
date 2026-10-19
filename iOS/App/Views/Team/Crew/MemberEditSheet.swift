import SwiftUI
import TimeCardCore

/// Role, job title and hourly rate for one person. Saves a member record through the
/// session; the last admin can't be made crew, and making yourself crew asks first.
struct MemberEditSheet: View {
    var member: Member
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MemberDraft
    @State private var problem: String?
    @State private var confirmingStepDown = false
    @FocusState private var focus: String?

    init(member: Member) {
        self.member = member
        _draft = State(initialValue: MemberDraft(member))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        Avatar(name: member.displayName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName).font(.tcHeadline).foregroundStyle(Palette.ink)
                            Text("People change their own name in Settings.").font(.footnote).foregroundStyle(Palette.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Role").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        ChoiceTile(title: Role.worker.teamLabel, detail: Role.worker.teamSummary, systemImage: "person",
                                   selected: draft.role == .worker) { draft.role = .worker }
                            .accessibilityIdentifier("member-role-worker")
                        ChoiceTile(title: Role.admin.teamLabel, detail: Role.admin.teamSummary, systemImage: "person.badge.key",
                                   selected: draft.role == .admin) { draft.role = .admin }
                            .accessibilityIdentifier("member-role-admin")
                        if member.role == .admin, MemberRules.isOnlyAdmin(member, members: Array(session.snapshot.members.values)) {
                            Text("\(member.displayName) is the only admin, so stays one until someone else is made admin.")
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    LabeledGloveField(title: "Job title", prompt: "Trimmer, crew lead…", text: $draft.jobTitle, identifier: "member-job", footnote: nil)
                        .focused($focus, equals: "job")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hourly pay").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        HStack(spacing: 10) {
                            Text("$").font(.tcStat).foregroundStyle(Palette.muted).accessibilityHidden(true)
                            TextField("0.00", text: $draft.rateText)
                                .keyboardType(.decimalPad)
                                .font(.tcStat)
                                .monospacedDigit()
                                .textFieldStyle(.glove)
                                .focused($focus, equals: "rate")
                                .accessibilityLabel("Hourly pay in dollars")
                                .accessibilityIdentifier("member-rate")
                            Text("an hour").font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        Text("New shifts use this rate. Shifts already started keep the rate they began with.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let problem {
                        ErrorMessage(text: problem)
                    }
                    if session.isCatchingUpOnRole {
                        // Until the farm is pulled again under your new role, the copies here
                        // may have blank rates, and saving one would overwrite the real rate.
                        Label(Self.waitingForRates, systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("member-waiting")
                    }
                    Button("Save", action: attemptSave)
                        .buttonStyle(.glovePrimary)
                        .disabled(session.isCatchingUpOnRole)
                        .accessibilityIdentifier("member-save")
                        .confirmationDialog("Make yourself crew?", isPresented: $confirmingStepDown, titleVisibility: .visible) {
                            Button("Make me crew", role: .destructive, action: save)
                            Button("Stay admin", role: .cancel) {}
                        } message: {
                            Text("You’ll lose the Team tab and stop seeing other people’s hours. Another admin can change it back.")
                        }
                }
                .teamPage()
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Role and Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .onChange(of: draft) { problem = nil }
        }
    }

    static let waitingForRates = "Getting everyone’s pay rates from the server. Save works once that’s done."

    private func attemptSave() {
        focus = nil
        guard !session.isCatchingUpOnRole else {
            problem = Self.waitingForRates
            TeamAnnounce.say(problem)
            return
        }
        if MemberRules.losesOwnAdmin(draft, for: member, me: session.me?.user.id),
           case .save = MemberRules.save(draft, for: member, members: Array(session.snapshot.members.values), now: Date()) {
            confirmingStepDown = true
            return
        }
        save()
    }

    private func save() {
        let current = session.snapshot.members[member.userId] ?? member
        let edit = MemberRules.save(draft, for: current, members: Array(session.snapshot.members.values), now: Date())
        do {
            if let text = try TeamSave.apply(edit, in: session) {
                problem = text
            } else {
                dismiss()
            }
        } catch {
            problem = error.localizedDescription
        }
        // Said out loud on every refused tap, even when the sentence is already showing.
        TeamAnnounce.say(problem)
    }
}
