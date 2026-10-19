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
    /// The shift being fixed in the shift editor (a forgotten clock-out).
    @State private var fixing: FixShift?
    @Environment(\.dynamicTypeSize) private var typeSize

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
        .sheet(item: $fixing) { item in
            ShiftEditorView(shiftId: item.id)
        }
        .announcing(actions?.error)
    }

    @ViewBuilder
    private func content(member: Member, calendar: FarmCalendar, now: Date) -> some View {
        let roster = CrewRoster.build(snapshot: session.snapshot, me: session.me?.user.id, now: now, calendar: calendar)
        let row = (roster.current + roster.former).first { $0.id == userId }
        let recent = CrewRoster.recentShifts(of: userId, snapshot: session.snapshot, now: now, limit: 6)
        let isYou = member.userId == session.me?.user.id
        let removed = member.removedAt != nil

        VStack(alignment: .leading, spacing: 16) {
            header(member, row: row, calendar: calendar, isYou: isYou, now: now)
            if let row, let since = row.forgotSince {
                forgotBox(member, since: since, calendar: calendar, now: now)
            }
            if let row {
                TeamStatRow {
                    TeamStat(label: "This week", value: Fmt.decimalHours(row.week), unit: "hrs", accessibilityValue: CrewStatusText.spokenHours(row.week))
                    TeamStat(label: "Today", value: Fmt.decimalHours(row.today), unit: "hrs", accessibilityValue: CrewStatusText.spokenHours(row.today))
                    TeamStat(label: "Trees this week", value: Fmt.count(row.weekTrees), unit: nil, accessibilityValue: Fmt.plural(row.weekTrees, "tree"))
                }
                .card()
            }
            recentShifts(recent, calendar: calendar, now: now)
            NavigationLink(value: TeamView.Route.memberReport(userId)) {
                Label("\(member.teamFirstName)’s time card", systemImage: "doc.text")
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

    private func header(_ member: Member, row: CrewRow?, calendar: FarmCalendar, isYou: Bool, now: Date) -> some View {
        // At the largest text sizes the name and email get the full width under the initials.
        let top = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        return VStack(alignment: .leading, spacing: 14) {
            top {
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
            // A forgotten clock-out gets its own warning below, so the pill is for everyday status.
            if let row, !row.forgotClockOut, let status = CrewStatusText.line(row.status, calendar: calendar, now: now) {
                StatusPill(text: status, tone: CrewStatusText.tone(row.status))
            }
        }
        .card()
    }

    /// "Still clocked in since Sun, Oct 18 at 2:55 AM (26 h). Did Sam forget to clock out?"
    /// with a way into the shift editor to set the real clock-out time.
    private func forgotBox(_ member: Member, since: Date, calendar: FarmCalendar, now: Date) -> some View {
        let open = session.snapshot.shifts.values.first { $0.userId == member.userId && $0.isLive && $0.isOpen && $0.start == since }
        return AlertBox {
            Text(CrewStatusText.forgotLine(since: since, calendar: calendar, now: now) + ".")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(CrewStatusText.forgotQuestion(member)) Set the time they really stopped, so the hours and pay are right.")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let open {
                Button { fixing = FixShift(id: open.id) } label: {
                    Label("Fix \(member.teamFirstName)’s times", systemImage: "clock.badge.exclamationmark")
                }
                .buttonStyle(.glovePrimary)
                .accessibilityIdentifier("member-fix-shift")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("member-forgot")
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
                Task {
                    reset = await actions?.resetCode(for: member)
                    if reset == nil { TeamAnnounce.say(actions?.error) }
                }
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
                .confirmationDialog("Remove \(member.displayName)?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                    Button("Remove \(member.teamFirstName)", role: .destructive) {
                        Task {
                            if await actions?.remove(member) == false { TeamAnnounce.say(actions?.error) }
                        }
                    }
                    Button("Keep \(member.teamFirstName)", role: .cancel) {}
                } message: {
                    Text("They won’t be able to sign in to \(session.farm?.name ?? "this farm"). Their hours stay on its reports.")
                }
            }
            if let error = actions?.error {
                ErrorMessage(text: error)
            }
        }
    }
}

private struct FixShift: Identifiable {
    var id: UUID
}

private struct IdentifiedReset: Identifiable {
    var reset: ResetCodeResponse
    var id: String { reset.code }
}

/// "Mon, Oct 19 · 7:02 AM – 3:31 PM · 8.15 h · 212 trees", stacked at the largest text sizes.
private struct ShiftLine: View {
    var item: CrewRoster.RecentShift
    var calendar: FarmCalendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shift = item.shift
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(Fmt.day(shift.start, calendar)).font(.headline).foregroundStyle(Palette.ink)
                HStack(spacing: 4) {
                    Text(Fmt.time(shift.start, calendar))
                    Text("–")
                    if let end = shift.end {
                        Text(Fmt.time(end, calendar))
                    } else if item.forgotClockOut {
                        Text("still open").foregroundStyle(Palette.rust).fontWeight(.semibold)
                    } else {
                        Text("now").foregroundStyle(Palette.firText).fontWeight(.semibold)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                Text.numberPhrase("\(Fmt.decimalHours(item.worked)) hrs").foregroundStyle(item.forgotClockOut ? Palette.rust : Palette.ink)
                Text(Fmt.plural(item.trees, "tree")).font(.caption).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }
}
