import SwiftUI
import TimeCardCore

/// The crew with this week's hours, who's on the clock, and the farm's invites.
struct CrewSection: View {
    /// Owned by the tab, so the list survives switching sections and reloads on pull to refresh.
    var invites: InvitesModel?
    @Environment(TimeCardSession.self) private var session
    @State private var inviting = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            VStack(alignment: .leading, spacing: 16) {
                content(now: timeline.date)
            }
        }
        .sheet(isPresented: $inviting) {
            if let invites { InviteSheet(invites: invites) }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let farm = session.farm {
            let calendar = FarmCalendar(farm: farm)
            let roster = CrewRoster.build(snapshot: session.snapshot, me: session.me?.user.id, now: now, calendar: calendar)
            WeekSummary(roster: roster)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Crew")
                VStack(spacing: 0) {
                    ForEach(Array(roster.current.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { RowDivider().padding(.leading, 74) }
                        CrewRowLink(row: row, calendar: calendar)
                    }
                }
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            }
            Button { inviting = true } label: {
                Label("Invite someone", systemImage: "person.badge.plus")
            }
            .buttonStyle(.glovePrimary)
            .accessibilityIdentifier("team-invite")
            if let invites {
                InviteList(invites: invites, now: now, calendar: calendar)
            }
            if !roster.former.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Former crew")
                    VStack(spacing: 0) {
                        ForEach(Array(roster.former.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowDivider().padding(.leading, 74) }
                            CrewRowLink(row: row, calendar: calendar)
                        }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    Text("They can’t sign in to this farm. Their hours stay on its reports.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

/// Crew hours this week and who's working right now.
private struct WeekSummary: View {
    var roster: CrewRoster

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("This week")
                Text(roster.weekLabel).font(.subheadline).foregroundStyle(Palette.muted)
            }
            TeamStatRow {
                TeamStat(label: "Crew hours", value: Fmt.decimalHours(roster.weekTotal), unit: "h",
                         accessibilityValue: Fmt.spokenDuration(roster.weekTotal))
                TeamStat(label: "On the clock", value: "\(roster.onTheClock)", unit: "of \(roster.current.count)",
                         accessibilityValue: "\(roster.onTheClock) of \(Fmt.plural(roster.current.count, "person"))")
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("team-week")
    }
}

/// One person: initials, name, role and job, what they're doing, and this week's hours.
private struct CrewRowLink: View {
    var row: CrewRow
    var calendar: FarmCalendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationLink(value: TeamView.Route.member(row.id)) {
            HStack(alignment: .center, spacing: 14) {
                Avatar(name: row.member.displayName, dimmed: row.member.removedAt != nil)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) {
                        details
                        hours
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    details.frame(maxWidth: .infinity, alignment: .leading)
                    hours
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(CrewRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("crew-\(row.member.displayName)")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(row.member.displayName)
                    .font(.headline)
                    .foregroundStyle(row.member.removedAt == nil ? Palette.ink : Palette.muted)
                if row.isYou {
                    Text("You")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.firText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Palette.firSoft, in: Capsule())
                }
            }
            Text(roleLine).font(.subheadline).foregroundStyle(Palette.muted)
            if let status = CrewStatusText.line(row.status, calendar: calendar) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle().fill(CrewStatusText.tone(row.status).dot).frame(width: 8, height: 8)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text(status).font(.subheadline.weight(.medium)).foregroundStyle(CrewStatusText.tone(row.status).ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hours: some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 1) {
            Text(Fmt.decimalHours(row.week)).numberStyle(.body).foregroundStyle(Palette.ink)
            Text("h this week").font(.caption).foregroundStyle(Palette.muted)
        }
    }

    private var roleLine: String {
        let role = row.member.role.teamLabel
        return row.member.jobTitle.isEmpty ? role : "\(role) · \(row.member.jobTitle)"
    }

    private var accessibilityText: String {
        var parts = [row.member.displayName + (row.isYou ? ", you" : ""), roleLine]
        if let status = CrewStatusText.line(row.status, calendar: calendar) { parts.append(status) }
        parts.append("\(Fmt.spokenDuration(row.week)) this week")
        return parts.joined(separator: ". ")
    }
}

/// A row that darkens a little while pressed.
private struct CrewRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.stripe : Color.clear)
    }
}

/// Open invites with their notes and how long they work, and a revoke button each.
/// Used and expired ones fold away.
private struct InviteList: View {
    var invites: InvitesModel
    var now: Date
    var calendar: FarmCalendar
    @State private var showingOld = false
    @State private var revoking: InviteInfo?

    var body: some View {
        let open = invites.invites.filter { InviteText.status($0, now: now) == .open }
        let old = invites.invites.filter { InviteText.status($0, now: now) != .open }
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Invites")
            VStack(alignment: .leading, spacing: 0) {
                if let error = invites.listError, !invites.loaded {
                    VStack(alignment: .leading, spacing: 12) {
                        ErrorMessage(text: error)
                        Button("Try again") { Task { await invites.load() } }
                            .buttonStyle(.gloveSecondary)
                    }
                    .padding(16)
                } else if !invites.loaded {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Getting invites…").font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                } else if open.isEmpty {
                    Text("No open invites. Make one when someone new joins the crew.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(open.enumerated()), id: \.element.id) { index, invite in
                        if index > 0 { RowDivider().padding(.leading, 16) }
                        InviteRow(invite: invite, now: now, calendar: calendar) { revoking = invite }
                    }
                }
                if invites.loaded && !old.isEmpty {
                    RowDivider()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showingOld.toggle() }
                    } label: {
                        HStack {
                            Text(showingOld ? "Hide used and expired" : "Used and expired (\(old.count))")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.firText)
                            Spacer()
                            Image(systemName: showingOld ? "chevron.up" : "chevron.down")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.firText)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: GloveButtonStyle.minHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("invites-old")
                    if showingOld {
                        ForEach(old) { invite in
                            RowDivider().padding(.leading, 16)
                            InviteRow(invite: invite, now: now, calendar: calendar, onRevoke: nil)
                        }
                    }
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            if let error = invites.error, !invites.working {
                ErrorMessage(text: error)
            }
        }
        .confirmationDialog("Revoke this invite?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
                            titleVisibility: .visible, presenting: revoking) { invite in
            Button("Revoke invite", role: .destructive) { Task { await invites.revoke(invite) } }
            Button("Keep it", role: .cancel) {}
        } message: { _ in
            Text("The code stops working right away. You can make a new one any time.")
        }
    }
}

private struct InviteRow: View {
    var invite: InviteInfo
    var now: Date
    var calendar: FarmCalendar
    var onRevoke: (() -> Void)?

    var body: some View {
        let status = InviteText.status(invite, now: now)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                text(status)
                Spacer(minLength: 8)
                revoke
            }
            VStack(alignment: .leading, spacing: 10) {
                text(status)
                revoke
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .accessibilityIdentifier("invite-\(invite.note.isEmpty ? invite.id.uuidString : invite.note)")
    }

    private func text(_ status: InviteText.Status) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(invite.note.isEmpty ? "No note" : invite.note)
                    .font(.headline)
                    .foregroundStyle(invite.note.isEmpty || status != .open ? Palette.muted : Palette.ink)
                Text(invite.role.teamLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(invite.role == .admin ? Palette.sapInk : Palette.firText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(invite.role == .admin ? Palette.sapSoft : Palette.firSoft, in: Capsule())
            }
            Text(InviteText.statusLine(invite, now: now, calendar: calendar))
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var revoke: some View {
        if let onRevoke {
            Button("Revoke", action: onRevoke)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.rust)
                .padding(.horizontal, 16)
                .frame(minHeight: GloveButtonStyle.minHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.rust.opacity(0.4), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .buttonStyle(.plain)
                .accessibilityLabel("Revoke \(invite.note.isEmpty ? "invite" : "invite for \(invite.note)")")
        }
    }
}
