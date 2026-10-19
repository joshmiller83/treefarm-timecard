import SwiftUI
import TimeCardCore

/// The active season with each field's progress, earlier seasons, and starting a new one.
/// Until the farm's records arrive it waits, rather than offering to start a season the
/// farm already has.
struct SeasonSection: View {
    @Environment(TimeCardSession.self) private var session
    @State private var starting = false

    var body: some View {
        let snapshot = session.snapshot
        let rows = SeasonPlans.rows(snapshot)
        let active = rows.first(where: \.isActive)
        let calendar = session.farm.map(FarmCalendar.init(farm:))

        VStack(alignment: .leading, spacing: 16) {
            if session.teamIsWaitingForFarm {
                TeamWaitingCard()
            } else {
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
                if let active, let earlier = SeasonPlans.undoTarget(snapshot, now: Date()) {
                    UndoSeasonCard(active: active.season, earlier: earlier)
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
                                EarlierSeasonRow(row: row, calendar: calendar)
                            }
                        }
                        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        Text("Earlier seasons’ trees stay with the shifts they were shaped on.")
                            .font(.footnote).foregroundStyle(Palette.muted)
                    }
                }
            }
        }
        .sheet(isPresented: $starting) {
            NewSeasonSheet()
        }
    }
}

/// "2025 · Started Jun 2, 2025 · 1,204 trees", stacked at the largest text sizes.
private struct EarlierSeasonRow: View {
    var row: SeasonPlans.Row
    var calendar: FarmCalendar
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.season.name).font(.headline).foregroundStyle(Palette.ink)
                Text("Started \(SeasonText.date(row.season.startedAt, calendar))").font(.subheadline).foregroundStyle(Palette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text.numberPhrase(Fmt.plural(row.shaped, "tree")).foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}

/// A season started in the last week with nothing shaped in it yet can be taken back.
private struct UndoSeasonCard: View {
    var active: Season
    var earlier: Season
    @Environment(TimeCardSession.self) private var session
    @State private var confirming = false
    @State private var problem: String?

    var body: some View {
        NoticeBox(systemImage: "arrow.uturn.backward.circle") {
            Text("Started \(active.name) by mistake? Nothing is shaped in it yet, so you can go back to \(earlier.name).")
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button { confirming = true } label: {
                Label("Make \(earlier.name) active again", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("season-undo")
            .confirmationDialog("Go back to \(earlier.name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Make \(earlier.name) active", action: undo)
                Button("Keep \(active.name)", role: .cancel) {}
            } message: {
                Text("The crew’s map shows \(earlier.name)’s shaped trees again when their phones sync. \(active.name) moves to earlier seasons.")
            }
            if let problem { ErrorMessage(text: problem) }
        }
        .announcing(problem)
    }

    private func undo() {
        guard let farm = session.farm else { return }
        do {
            problem = try TeamSave.apply(SeasonPlans.makeActive(earlier, farm: farm, now: Date()), in: session)
        } catch {
            problem = error.localizedDescription
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                        : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        Text(field.field.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
    /// The bullets' icon column grows with the text, so icons never run into it; at the
    /// largest sizes the icon sits above its line instead.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 22
    @Environment(\.dynamicTypeSize) private var typeSize

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
                        point("arrow.triangle.2.circlepath", "Each phone switches when it next syncs, so start it when nobody is marking trees.")
                        point("person.2", onTheClock, emphasized: true)
                    }
                    if let problem { ErrorMessage(text: problem) }
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let text = TeamErrors.nameProblem(trimmed, thing: "season") {
                            problem = text
                            TeamAnnounce.say(text)
                        } else {
                            confirming = true
                        }
                    } label: {
                        Text(startTitle)
                    }
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("season-new-start")
                    .confirmationDialog("\(startTitle) for everyone?", isPresented: $confirming, titleVisibility: .visible) {
                        Button(startTitle, action: start)
                        Button("Not yet", role: .cancel) {}
                    } message: {
                        Text("The whole crew’s map starts clean.")
                    }
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
        }
    }

    /// "Sam Ortiz is on the clock right now."
    private var onTheClock: String {
        guard let farm = session.farm else { return SeasonPlans.onTheClockLine([]) }
        return SeasonPlans.onTheClockLine(SeasonPlans.othersOnTheClock(session.snapshot, me: session.me?.user.id, now: Date(),
                                                                        calendar: FarmCalendar(farm: farm)))
    }

    private var startTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Start the season" : "Start \(trimmed)"
    }

    private func point(_ icon: String, _ text: String, emphasized: Bool = false) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return layout {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.sapInk)
                .frame(width: typeSize.isAccessibilitySize ? nil : iconWidth)
                .accessibilityHidden(true)
            Text(text)
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func suggest() {
        guard name.isEmpty, let farm = session.farm else { return }
        let snapshot = session.snapshot
        name = SeasonPlans.suggestedName(seasons: Array(snapshot.seasons.values), active: snapshot.activeSeason, now: Date(),
                                         calendar: FarmCalendar(farm: farm))
    }

    private func start() {
        // Before the first pull the farm's season isn't here yet: starting one now would
        // move the whole crew off a season the farm already has.
        guard let farm = session.farm, !session.teamIsWaitingForFarm else {
            problem = "The farm is still coming from the server. Try again in a moment."
            TeamAnnounce.say(problem)
            return
        }
        do {
            if let text = try TeamSave.apply(SeasonPlans.start(name: name, farm: farm, now: Date()), in: session) {
                problem = text
                TeamAnnounce.say(text)
            } else {
                dismiss()
            }
        } catch {
            problem = error.localizedDescription
            TeamAnnounce.say(problem)
        }
    }
}
