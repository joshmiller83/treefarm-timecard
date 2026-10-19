import SwiftUI
import TimeCardCore

/// The active season with each field's progress, earlier seasons, and starting a new one.
struct SeasonSection: View {
    @Environment(TimeCardSession.self) private var session
    @State private var starting = false

    var body: some View {
        let snapshot = session.snapshot
        let rows = SeasonPlans.rows(snapshot)
        let active = rows.first(where: \.isActive)
        let calendar = session.farm.map(FarmCalendar.init(farm:))

        VStack(alignment: .leading, spacing: 16) {
            if let active, let calendar {
                ActiveSeasonCard(row: active, progress: SeasonPlans.progress(snapshot), calendar: calendar)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No season yet").headingStyle(.tcTitle2)
                    Text("Shaped trees belong to a season. Start one to begin marking the map.")
                        .font(.body).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            Button { starting = true } label: {
                Label("Start a new season", systemImage: "leaf.arrow.triangle.circlepath")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("season-start")
            let past = rows.filter { !$0.isActive }
            if !past.isEmpty, let calendar {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Earlier seasons")
                    VStack(spacing: 0) {
                        ForEach(Array(past.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowDivider().padding(.leading, 16) }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.season.name).font(.headline).foregroundStyle(Palette.ink)
                                    Text("Started \(SeasonText.date(row.season.startedAt, calendar))").font(.subheadline).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Text(Fmt.plural(row.shaped, "tree")).numberStyle(.body).foregroundStyle(Palette.muted)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 64)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    Text("Earlier seasons’ trees stay with the shifts they were shaped on.")
                        .font(.footnote).foregroundStyle(Palette.muted)
                }
            }
        }
        .sheet(isPresented: $starting) {
            NewSeasonSheet()
        }
    }
}

enum SeasonText {
    /// "Sep 19, 2026"
    static func date(_ date: Date, _ calendar: FarmCalendar) -> String {
        Fmt.monthDay(date, calendar) + ", \(calendar.dayKey(date).year)"
    }
}

private struct ActiveSeasonCard: View {
    var row: SeasonPlans.Row
    var progress: [SeasonPlans.FieldProgress]
    var calendar: FarmCalendar

    var body: some View {
        let shaped = progress.reduce(0) { $0 + $1.shaped }
        let total = progress.reduce(0) { $0 + $1.total }
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("This season")
                Text(row.season.name).headingStyle(.tcTitle).accessibilityIdentifier("season-name")
                Text("Started \(SeasonText.date(row.season.startedAt, calendar))").font(.subheadline).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Fmt.count(shaped)).numberStyle(.stat).foregroundStyle(Palette.firText)
                Text("of \(Fmt.plural(total, "tree")) shaped").font(.subheadline).foregroundStyle(Palette.muted)
            }
            .accessibilityElement(children: .combine)
            ForEach(progress) { field in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(field.field.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(Fmt.count(field.shaped)) / \(Fmt.count(field.total))").numberStyle(.small).foregroundStyle(Palette.muted)
                    }
                    ProgressBar(fraction: field.fraction)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(field.field.name)
                .accessibilityValue("\(Fmt.count(field.shaped)) of \(Fmt.plural(field.total, "tree")) shaped")
            }
        }
        .card()
    }
}

private struct ProgressBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.stripe)
                Capsule().fill(Palette.fir)
                    .frame(width: fraction > 0 ? max(8, proxy.size.width * min(1, fraction)) : 0)
            }
        }
        .frame(height: 8)
    }
}

/// Starting a season: a name, a plain warning about what changes, and a confirmation.
struct NewSeasonSheet: View {
    @Environment(TimeCardSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var problem: String?
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LabeledGloveField(title: "Season name", prompt: "2027", text: $name, identifier: "season-new-name", footnote: nil)
                    NoticeBox(systemImage: "leaf") {
                        Text("What happens").font(.headline).foregroundStyle(Palette.ink)
                        point("square.grid.3x3", "The map starts clean for everyone: every tree shows as not shaped yet.")
                        point("doc.text", "This season’s shaped trees are kept with their shifts and listed under earlier seasons.")
                        point("note.text", "Tree notes stay with their trees.")
                        point("clock", "Anyone on the clock keeps going. Trees they shape from now on count for the new season.")
                    }
                    if let problem { ErrorMessage(text: problem) }
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let text = TeamErrors.nameProblem(trimmed, thing: "season") {
                            problem = text
                        } else {
                            confirming = true
                        }
                    } label: {
                        Text(startTitle)
                    }
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("season-new-start")
                }
                .teamPage()
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("New Season")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear(perform: suggest)
            .onChange(of: name) { problem = nil }
            .confirmationDialog("\(startTitle) for everyone?", isPresented: $confirming, titleVisibility: .visible) {
                Button(startTitle, action: start)
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("The whole crew’s map starts clean.")
            }
        }
    }

    private var startTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Start the season" : "Start \(trimmed)"
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.sapInk)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text).font(.subheadline).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func suggest() {
        guard name.isEmpty, let farm = session.farm else { return }
        let snapshot = session.snapshot
        name = SeasonPlans.suggestedName(seasons: Array(snapshot.seasons.values), active: snapshot.activeSeason, now: Date(),
                                         calendar: FarmCalendar(farm: farm))
    }

    private func start() {
        guard let farm = session.farm else { return }
        do {
            if let text = try TeamSave.apply(SeasonPlans.start(name: name, farm: farm, now: Date()), in: session) {
                problem = text
            } else {
                dismiss()
            }
        } catch {
            problem = error.localizedDescription
        }
    }
}
