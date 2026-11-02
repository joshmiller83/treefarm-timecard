import SwiftUI
import TimeCardCore

/// A shift's Health card (docs/health.md 4): steps, distance, flights, calories and heart rate
/// from Apple Health over the time worked. For the worker only: it stays on this phone.
struct ShiftHealthSheet: View {
    var shiftId: UUID
    var reader: any ShiftHealthReader = AppModel.shared.health
    @Environment(TimeCardSession.self) private var session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case loading
        case needsPermission
        case loaded(ShiftHealth)
    }

    @State private var phase = Phase.loading

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let shift = session.snapshot.shifts[shiftId], let farm = session.farm {
                        content(shift: shift, calendar: FarmCalendar(farm: farm))
                    } else {
                        Text(ShiftMessages.missing)
                            .font(.body)
                            .foregroundStyle(Palette.ink)
                            .card()
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationTitle(ShiftHealthWording.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("health-done")
                }
            }
        }
        .task { await load() }
        .accessibilityIdentifier("shift-health-sheet")
    }

    @ViewBuilder
    private func content(shift: Shift, calendar: FarmCalendar) -> some View {
        let worked = shift.workedTime(at: Date())
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Fmt.dayLong(shift.start, calendar)) · \(Fmt.time(shift.start, calendar)) – \(shift.end.map { Fmt.time($0, calendar) } ?? "now")")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.hm(worked)).numberStyle(.timer).foregroundStyle(Palette.firText)
                Text("worked").font(.tcHeadline).foregroundStyle(Palette.ink)
            }
            if let line = ShiftHealthWording.workoutLine(model.watch.desk.summary(for: shift.id)) {
                Label(line, systemImage: "figure.walk")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("health-workout")
            }
        }
        .accessibilityElement(children: .combine)

        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 80)
        case .needsPermission:
            VStack(alignment: .leading, spacing: 12) {
                Text(ShiftHealthWording.permissionTitle)
                    .font(.tcHeadline)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ShiftHealthWording.permissionBody)
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        await reader.requestPermission()
                        await load()
                    }
                } label: {
                    Label(ShiftHealthWording.allow, systemImage: "heart.fill")
                }
                .buttonStyle(.glovePrimary)
                .accessibilityIdentifier("health-allow")
            }
            .card()
        case .loaded(let health):
            let stats = ShiftHealthWording.stats(health)
            if stats.isEmpty {
                Text(ShiftHealthWording.empty)
                    .font(.body)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .card()
                    .accessibilityIdentifier("health-empty")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                        if index > 0 { Divider().overlay(Palette.line) }
                        // Label and number on one line when they fit; a long one ("avg 104 · max
                        // 151") or a big text size puts the number under its label.
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                statLabel(stat)
                                Spacer(minLength: 12)
                                statValue(stat)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                statLabel(stat)
                                statValue(stat)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stat.label): \(stat.spoken)")
                    }
                }
                .card(padding: 16)
                .accessibilityIdentifier("health-stats")
            }
        }

        Text(ShiftHealthWording.footnote)
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func statLabel(_ stat: ShiftHealthWording.Stat) -> some View {
        Text(stat.label).font(.tcHeadline).foregroundStyle(Palette.ink).fixedSize()
    }

    private func statValue(_ stat: ShiftHealthWording.Stat) -> some View {
        Text(stat.value).numberStyle(.stat).foregroundStyle(Palette.firText).fixedSize()
    }

    private func load() async {
        guard let shift = session.snapshot.shifts[shiftId] else { return }
        if await reader.needsPermission() {
            phase = .needsPermission
            return
        }
        phase = .loaded(await reader.read(shift.workIntervals(at: Date())))
    }
}
