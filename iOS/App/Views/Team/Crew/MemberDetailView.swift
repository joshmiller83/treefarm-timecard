import SwiftUI
import TimeCardCore

/// One person: who they are, what they're doing now, this week, their recent shifts, a
/// link to their time card, and the admin's tools: role and rate, a reset code, removal.
struct MemberDetailView: View {
    var userId: UUID
    @Environment(TimeCardSession.self) private var session
    @State private var actions: MemberActionsModel?
    @State private var editing = false
    @State private var reset: ResetCodeResponse?
    @State private var confirmingRemove = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            ScrollView {
                if let member = session.snapshot.members[userId], let farm = session.farm {
                    content(member: member, calendar: FarmCalendar(farm: farm), now: timeline.date)
                        .teamPage()
                }
            }
        }
        .screenBackground()
        .navigationTitle(session.snapshot.members[userId]?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if actions == nil { actions = MemberActionsModel(session: session) } }
        .sheet(isPresented: $editing) {
            if let member = session.snapshot.members[userId] { MemberEditSheet(member: member) }
        }
        .sheet(item: Binding(get: { reset.map(IdentifiedReset.init) }, set: { reset = $0?.reset })) { item in
            if let member = session.snapshot.members[userId] { ResetCodeSheet(member: member, reset: item.reset) }
        }
    }

    @ViewBuilder
    private func content(member: Member, calendar: FarmCalendar, now: Date) -> some View {
        let roster = CrewRoster.build(snapshot: session.snapshot, me: session.me?.user.id, now: now, calendar: calendar)
        let row = (roster.current + roster.former).first { $0.id == userId }
        let recent = CrewRoster.recentShifts(of: userId, snapshot: session.snapshot, now: now, limit: 6)
        let isYou = member.userId == session.me?.user.id
        let removed = member.removedAt != nil

        VStack(alignment: .leading, spacing: 16) {
            header(member, row: row, calendar: calendar, isYou: isYou)
            if let row {
                HStack(alignment: .top, spacing: 12) {
                    TeamStat(label: "This week", value: Fmt.decimalHours(row.week), unit: "h", accessibilityValue: Fmt.spokenDuration(row.week))
                    TeamStat(label: "Today", value: Fmt.decimalHours(row.today), unit: "h", accessibilityValue: Fmt.spokenDuration(row.today))
                    TeamStat(label: "Trees", value: Fmt.count(row.weekTrees), unit: nil, accessibilityValue: "\(Fmt.plural(row.weekTrees, "tree")) this week")
                }
                .card()
            }
            recentShifts(recent, calendar: calendar, now: now)
            NavigationLink(value: TeamView.Route.memberReport(userId)) {
                Label("\(firstName(member))’s time card", systemImage: "doc.text")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("member-report")

            if removed {
                Text("Removed \(Fmt.day(member.removedAt ?? now, calendar)). They can’t sign in to this farm, and their hours stay on its reports.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                adminTools(member, isYou: isYou)
            }
        }
    }

    private func header(_ member: Member, row: CrewRow?, calendar: FarmCalendar, isYou: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Avatar(name: member.displayName, size: 60, dimmed: member.removedAt != nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.displayName).headingStyle(.tcTitle2).fixedSize(horizontal: false, vertical: true)
                    if !member.email.isEmpty {
                        Text(member.email).font(.subheadline).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                }
            }
            HStack(spacing: 8) {
                StatusPill(text: member.role.teamLabel, tone: member.role == .admin ? .working : .off)
                if isYou { StatusPill(text: "You", tone: .off) }
                if member.removedAt != nil { StatusPill(text: "Removed", tone: .alert) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(member.jobTitle.isEmpty ? "No job title" : member.jobTitle, systemImage: "briefcase")
                Label(member.rateCents > 0 ? "\(Fmt.usd(cents: member.rateCents)) an hour" : "No pay rate set", systemImage: "dollarsign.circle")
            }
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            if let row, let status = CrewStatusText.line(row.status, calendar: calendar) {
                StatusPill(text: status, tone: CrewStatusText.tone(row.status))
            }
        }
        .card()
    }

    @ViewBuilder
    private func recentShifts(_ shifts: [CrewRoster.RecentShift], calendar: FarmCalendar, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Recent shifts")
            VStack(spacing: 0) {
                if shifts.isEmpty {
                    Text("No shifts yet.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(shifts.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { RowDivider().padding(.leading, 16) }
                    ShiftLine(item: item, calendar: calendar)
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func adminTools(_ member: Member, isYou: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Admin")
            Button { editing = true } label: {
                Label("Change role, job or rate", systemImage: "pencil")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("member-edit")
            Button {
                Task { reset = await actions?.resetCode(for: member) }
            } label: {
                if actions?.working == true {
                    ProgressView()
                } else {
                    Label("Make a password reset code", systemImage: "key")
                }
            }
            .buttonStyle(.gloveSecondary)
            .disabled(actions?.working == true)
            .accessibilityIdentifier("member-reset")
            if isYou {
                Text("To leave the farm yourself, delete your account in Settings.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Button(role: .destructive) { confirmingRemove = true } label: {
                    Label("Remove from the farm", systemImage: "person.badge.minus")
                }
                .buttonStyle(.gloveDestructive)
                .disabled(actions?.working == true)
                .accessibilityIdentifier("member-remove")
            }
            if let error = actions?.error {
                ErrorMessage(text: error)
            }
        }
        .confirmationDialog("Remove \(member.displayName)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove \(firstName(member))", role: .destructive) {
                Task { _ = await actions?.remove(member) }
            }
            Button("Keep \(firstName(member))", role: .cancel) {}
        } message: {
            Text("They won’t be able to sign in to \(session.farm?.name ?? "this farm"). Their hours stay on its reports.")
        }
    }

    private func firstName(_ member: Member) -> String {
        member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
    }
}

private struct IdentifiedReset: Identifiable {
    var reset: ResetCodeResponse
    var id: String { reset.code }
}

/// "Mon, Oct 19 · 7:02 AM – 3:31 PM · 8.15 h · 212 trees"
private struct ShiftLine: View {
    var item: CrewRoster.RecentShift
    var calendar: FarmCalendar

    var body: some View {
        let shift = item.shift
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.day(shift.start, calendar)).font(.headline).foregroundStyle(Palette.ink)
                HStack(spacing: 4) {
                    Text(Fmt.time(shift.start, calendar))
                    Text("–")
                    if let end = shift.end {
                        Text(Fmt.time(end, calendar))
                    } else {
                        Text("now").foregroundStyle(Palette.firText).fontWeight(.semibold)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Fmt.decimalHours(item.worked)) h").numberStyle(.body).foregroundStyle(Palette.ink)
                Text(Fmt.plural(item.trees, "tree")).font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }
}
