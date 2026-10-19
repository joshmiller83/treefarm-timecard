import SwiftUI
import TimeCardCore

/// The Report tab: pick This week, Last week, This month or any dates, see the paper time
/// card, and share it as a PDF or a CSV. Admins can run it for anyone on the crew. Pay is
/// never on it.
struct ReportView: View {
    @Environment(TimeCardSession.self) private var session
    @State private var range: ReportRange = LogScenario.reportPeriod.flatMap(ReportRange.init(rawValue:)) ?? .thisWeek
    @State private var custom: (from: DayKey, to: DayKey)?
    @State private var pickingDates = false
    /// Whose time card an admin is looking at; nil = their own.
    @State private var personId: UUID?
    @State private var treesCache = ShiftTreesCache()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                if let farm = session.farm, let me = session.membership {
                    content(farm: farm, me: me, now: context.date)
                }
            }
            .screenBackground()
            .navigationTitle("Report")
            // The title in the top bar, level with the Clock and Trees tabs' headings.
            .toolbarTitleDisplayMode(.inlineLarge)
        }
        .sheet(isPresented: $pickingDates) {
            if let farm = session.farm {
                let calendar = FarmCalendar(farm: farm)
                let bounds = period(calendar: calendar, now: Date()).bounds(now: Date(), calendar: calendar)
                PickDatesSheet(calendar: calendar,
                               from: custom?.from ?? calendar.dayKey(bounds.start),
                               to: custom?.to ?? calendar.dayKey(calendar.addDays(bounds.end, -1))) { from, to in
                    custom = (from, to)
                    range = .custom
                }
            }
        }
        .task { await LogScenario.applyIfRequested(AppModel.shared) }
    }

    private func period(calendar: FarmCalendar, now: Date) -> ReportPeriod {
        switch range {
        case .thisWeek: .thisWeek
        case .lastWeek: .lastWeek
        case .thisMonth: .thisMonth
        case .custom:
            if let custom { .custom(from: custom.from, to: custom.to) } else { .thisWeek }
        }
    }

    @ViewBuilder
    private func content(farm: Farm, me: Member, now: Date) -> some View {
        let calendar = FarmCalendar(farm: farm)
        let who = session.isAdmin ? (personId ?? me.userId) : me.userId
        let snapshot = session.snapshot
        let report = ReportContent(snapshot: snapshot, farm: farm,
                                   request: ReportRequest(period: period(calendar: calendar, now: now), userId: who), now: now,
                                   trees: treesCache.trees(for: snapshot))
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if session.isAdmin {
                    crewPicker(me: me.userId, selected: who)
                }
                rangePicker(card: report.card)
                stats(report)
                exports(report)
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Preview")
                    PaperCardView(card: report.card)
                }
                .padding(.top, 4)
                Text("Pay never shows on the time card. Hours are worked time; breaks are listed, not counted.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .padding(.bottom, 16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await session.requestSync(.manual) }
    }

    // MARK: Pieces

    private func crewPicker(me: UUID, selected: UUID) -> some View {
        let crew = ReportContent.crew(members: session.snapshot.members.values, me: me)
        let name = crew.first { $0.id == selected }?.name ?? ""
        return Menu {
            Picker("Time card for", selection: Binding(get: { selected }, set: { personId = $0 })) {
                ForEach(crew, id: \.id) { person in
                    Text(person.name).tag(person.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                // At the largest sizes the words need the room more than the picture does.
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(Palette.firText)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Time card for")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    Text(name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minHeight: GloveButtonStyle.minHeight + 4)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Time card for")
        .accessibilityValue(name)
        .accessibilityIdentifier("report-person")
    }

    private func rangePicker(card: PaperTimeCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GloveSegmented(options: [(ReportRange.thisWeek, "This week"), (.lastWeek, "Last week"), (.thisMonth, "This month")],
                           selection: Binding(get: { range }, set: { range = $0 }),
                           identifier: "report-range")
            AdaptiveStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(range == .custom ? "Your dates" : "Dates")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                    Text(card.range.wrappingOnlyAtDash)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .accessibilityIdentifier("report-range-label")
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Button {
                    pickingDates = true
                } label: {
                    Label("Pick dates", systemImage: "calendar")
                }
                .buttonStyle(range == .custom ? GloveButtonStyle(kind: .primary) : GloveButtonStyle(kind: .secondary))
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
                .accessibilityAddTraits(range == .custom ? [.isSelected] : [])
                .accessibilityIdentifier("report-pick-dates")
            }
        }
    }

    private func stats(_ report: ReportContent) -> some View {
        StatRow(stats: [
            StatRow.Stat(label: "Hours", value: report.hours, identifier: "report-hours"),
            StatRow.Stat(label: "Trees", value: report.trees, identifier: "report-trees"),
            StatRow.Stat(label: report.days == 1 ? "Day" : "Days", value: "\(report.days)", identifier: "report-days"),
        ])
        .card()
    }

    private func exports(_ report: ReportContent) -> some View {
        let name = report.card.fileName
        return AdaptiveStack(spacing: 10) {
            ShareLink(item: report.pdfFile, preview: SharePreview(name, image: Image(systemName: "doc.richtext"))) {
                Label("Export PDF", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glovePrimary)
            .accessibilityIdentifier("export-pdf")
            ShareLink(item: report.csvFile, preview: SharePreview(name, image: Image(systemName: "tablecells"))) {
                Label("CSV", systemImage: "tablecells")
            }
            .buttonStyle(.gloveSecondary)
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 130)
            .accessibilityLabel("Export CSV")
            .accessibilityIdentifier("export-csv")
        }
    }
}

/// From and To, each opening a calendar, then "Show these dates".
struct PickDatesSheet: View {
    var calendar: FarmCalendar
    @State var from: DayKey
    @State var to: DayKey
    var apply: (DayKey, DayKey) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var open: Which? = .from

    enum Which { case from, to }

    init(calendar: FarmCalendar, from: DayKey, to: DayKey, apply: @escaping (DayKey, DayKey) -> Void) {
        self.calendar = calendar
        _from = State(initialValue: from)
        _to = State(initialValue: max(from, to))
        self.apply = apply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 4) {
                        PickerRow(title: "From", value: Fmt.day(noon(from), calendar), monospaced: false, isExpanded: open == .from,
                                  identifier: "pick-from", toggle: { open = open == .from ? nil : .from }) {
                            DatePicker("From", selection: fromBinding, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(Palette.fir)
                                .labelsHidden()
                        }
                        Divider().overlay(Palette.line)
                        PickerRow(title: "To", value: Fmt.day(noon(to), calendar), monospaced: false, isExpanded: open == .to,
                                  identifier: "pick-to", toggle: { open = open == .to ? nil : .to }) {
                            DatePicker("To", selection: toBinding, in: noon(from)..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(Palette.fir)
                                .labelsHidden()
                        }
                    }
                    .card()
                    .animation(.easeInOut(duration: 0.2), value: open)
                    Text(Fmt.rangeLabel(start: calendar.startOfDay(from), endExclusive: calendar.addDays(calendar.startOfDay(to), 1), calendar)
                        .wrappingOnlyAtDash)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("pick-summary")
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .environment(\.timeZone, calendar.timeZone)
            // The farm's weeks: Monday first on a Monday farm, as on the Log.
            .environment(\.calendar, calendar.calendar)
            .navigationTitle("Pick Dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Show these dates") {
                    apply(from, max(from, to))
                    dismiss()
                }
                .buttonStyle(.glovePrimary)
                .accessibilityIdentifier("pick-apply")
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.bg.opacity(0.96).ignoresSafeArea(edges: .bottom))
            }
        }
    }

    private func noon(_ day: DayKey) -> Date { calendar.date(on: day, hour: 12, minute: 0) }

    /// Moving From past To pulls To along.
    private var fromBinding: Binding<Date> {
        Binding(get: { noon(from) }, set: { from = calendar.dayKey($0); if to < from { to = from } })
    }

    private var toBinding: Binding<Date> {
        Binding(get: { noon(to) }, set: { to = max(from, calendar.dayKey($0)) })
    }
}
