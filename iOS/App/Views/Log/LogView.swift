import SwiftUI
import TimeCardCore

/// The Log tab: every shift, week by week (the farm's weeks), newest first, with each week's
/// hours, pay and trees. Each shift shows its times, trees, breaks and notes, with big Edit
/// and Trees buttons. "Add a shift" covers a day someone forgot to clock.
struct LogView: View {
    @Environment(TimeCardSession.self) private var session
    /// Shared with the Clock tab's "Hide pay".
    @AppStorage("clock.showPay") private var showPay = true
    @State private var editing: EditorTarget?
    @State private var treesFor: TreesTarget?
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .screenBackground()
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showPay.toggle() }
                    } label: {
                        Image(systemName: showPay ? "eye.slash" : "eye")
                    }
                    .accessibilityLabel(showPay ? "Hide pay" : "Show pay")
                    .accessibilityIdentifier("log-pay-toggle")
                }
            }
        }
        .toast($toast)
        .sheet(item: $editing) { target in
            ShiftEditorView(shiftId: target.shiftId) { message in toast = message }
        }
        .sheet(item: $treesFor) { target in
            ShiftTreesSheet(shiftId: target.id)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            await LogScenario.applyIfRequested(AppModel.shared)
            switch LogScenario.takeEditorRequest(AppModel.shared) {
            case "new": editing = EditorTarget(shiftId: nil)
            case "last":
                let mine = session.snapshot.shifts.values.filter { $0.userId == session.membership?.userId }
                editing = mine.max { $0.start < $1.start }.map { EditorTarget(shiftId: $0.id) }
            default: break
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let weeks = self.weeks(now: now)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Button {
                    editing = EditorTarget(shiftId: nil)
                } label: {
                    Label("Add a shift", systemImage: "plus")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityHint("For a day you forgot to clock in")
                .accessibilityIdentifier("add-shift")

                if weeks.isEmpty {
                    EmptyLog()
                }
                ForEach(weeks) { week in
                    WeekHeader(week: week, showPay: showPay)
                        .padding(.top, 10)
                    ForEach(week.shifts) { row in
                        ShiftCard(row: row, showPay: showPay,
                                  edit: { editing = EditorTarget(shiftId: row.id) },
                                  trees: { treesFor = TreesTarget(id: row.id) })
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await session.requestSync(.manual) }
    }

    private func weeks(now: Date) -> [LogWeek] {
        guard let farm = session.farm, let me = session.membership else { return [] }
        let snapshot = session.snapshot
        let mine = snapshot.shifts.values.filter { $0.userId == me.userId }
        return LogBuilder.weeks(shifts: mine, trees: ShiftTrees(snapshot: snapshot), calendar: FarmCalendar(farm: farm), now: now)
    }
}

/// Which shift the editor sheet is open for (nil id = adding one).
struct EditorTarget: Identifiable {
    var shiftId: UUID?
    var id: String { shiftId?.uuidString ?? "new" }
}

struct TreesTarget: Identifiable {
    var id: UUID
}

// MARK: Week header

private struct WeekHeader: View {
    var week: LogWeek
    var showPay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(week.title)
                    .headingStyle(.tcTitle2)
                    .accessibilityAddTraits(.isHeader)
                if week.title != week.range {
                    Text(week.range)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                StatColumn(label: "Hours", value: week.hours)
                if showPay {
                    StatColumn(label: "Pay", value: week.pay)
                }
                StatColumn(label: "Trees", value: Fmt.count(week.trees))
                StatColumn(label: week.days == 1 ? "Day" : "Days", value: "\(week.days)")
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("log-week-header")
    }
}

// MARK: Shift card

private struct ShiftCard: View {
    var row: LogShiftRow
    var showPay: Bool
    var edit: () -> Void
    var trees: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.day)
                        .font(.tcHeadline)
                        .foregroundStyle(Palette.ink)
                    times
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(row.hours).numberStyle(.stat)
                        Text("hrs").font(.subheadline)
                    }
                    .foregroundStyle(Palette.ink)
                    if showPay {
                        Text(row.pay)
                            .numberStyle(.small)
                            .foregroundStyle(Palette.muted)
                    }
                }
            }

            if row.isOpen {
                StatusPill(text: "On the clock", tone: .working)
            }

            VStack(alignment: .leading, spacing: 8) {
                detail(icon: "tree", tint: Palette.firText) {
                    if row.trees > 0 {
                        let count = Text(Fmt.plural(row.trees, "tree")).fontWeight(.semibold)
                        let summary = Text(row.treeSummary.isEmpty ? "" : "  ·  " + row.treeSummary).foregroundStyle(Palette.muted)
                        Text("\(count)\(summary)")
                    } else {
                        Text("No trees marked").foregroundStyle(Palette.muted)
                    }
                }
                if !row.breakLines.isEmpty {
                    detail(icon: "cup.and.saucer", tint: Palette.sapInk) {
                        Text(row.breakLines.joined(separator: " · "))
                    }
                }
                if !row.notes.isEmpty {
                    detail(icon: "note.text", tint: Palette.muted) {
                        Text(row.notes).lineLimit(4)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(Palette.ink)

            HStack(spacing: 10) {
                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityLabel("Edit shift")
                .accessibilityIdentifier("log-edit")
                Button(action: trees) {
                    Label("Trees", systemImage: "tree")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityLabel("Trees on this shift")
                .accessibilityIdentifier("log-trees")
            }
        }
        .card()
        .overlay(alignment: .leading) {
            if row.isOpen {
                UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                    .fill(Palette.fir)
                    .frame(width: 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.spoken(showPay: showPay))
        .accessibilityIdentifier("log-shift-row")
    }

    private var times: some View {
        HStack(spacing: 6) {
            Text(row.clockIn)
            Text("–").foregroundStyle(Palette.muted)
            Text(row.clockOut ?? "now")
                .foregroundStyle(row.clockOut == nil ? Palette.firText : Palette.ink)
            if row.endsNextDay {
                Text("next day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.sapInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.sapSoft, in: Capsule())
            }
        }
        .numberStyle(.body)
        .foregroundStyle(Palette.ink)
    }

    private func detail<Content: View>(icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            content()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Empty

private struct EmptyLog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.firText)
                .frame(width: 56, height: 56)
                .background(Palette.firSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text("No shifts yet").headingStyle(.tcTitle2)
            Text("Clock in on the Clock tab and your shifts show up here, week by week. Forgot a day? Add it above.")
                .font(.body)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 20)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("log-empty")
    }
}
