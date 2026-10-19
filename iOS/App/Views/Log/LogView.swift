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
    @State private var treesCache = ShiftTreesCache()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .screenBackground()
            .navigationTitle("Log")
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
                AdaptiveStack(spacing: 10) {
                    Button {
                        editing = EditorTarget(shiftId: nil)
                    } label: {
                        Label("Add a shift", systemImage: "plus")
                    }
                    .buttonStyle(.gloveSecondary)
                    .accessibilityHint("For a day you forgot to clock in")
                    .accessibilityIdentifier("add-shift")
                    // Glove-size, beside the other button, rather than a small toolbar icon.
                    // Its own row with words at the largest sizes, so "Add a shift" isn't squeezed.
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showPay.toggle() }
                    } label: {
                        if typeSize.isAccessibilitySize {
                            Label(showPay ? "Hide pay" : "Show pay", systemImage: showPay ? "eye.slash" : "eye")
                        } else {
                            Image(systemName: showPay ? "eye.slash" : "eye")
                        }
                    }
                    .buttonStyle(.gloveSecondary)
                    .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: false)
                    .accessibilityLabel(showPay ? "Hide pay" : "Show pay")
                    .accessibilityIdentifier("log-pay-toggle")
                }

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
        return LogBuilder.weeks(shifts: mine, trees: treesCache.trees(for: snapshot), calendar: FarmCalendar(farm: farm), now: now)
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
                Text(week.title.wrappingOnlyAtDash)
                    .headingStyle(.tcTitle2)
                    .accessibilityAddTraits(.isHeader)
                if week.title != week.range {
                    Text(week.range.wrappingOnlyAtDash)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
            }
            AdaptiveStack(spacing: 12, alignment: .top) {
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Everything but the buttons is one VoiceOver stop that reads the whole shift.
            info
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spoken(showPay: showPay))
                .accessibilityIdentifier("log-shift-row")

            AdaptiveStack(spacing: 10) {
                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityLabel("Edit shift, \(row.day)")
                .accessibilityIdentifier("log-edit")
                Button(action: trees) {
                    Label("Trees", systemImage: "tree")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityLabel("Trees on \(row.day)")
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
        .accessibilityIdentifier("log-shift-card")
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 12) {
            if typeSize.isAccessibilitySize {
                // Stacked, so a number never wraps inside itself ("5.0" / "0").
                VStack(alignment: .leading, spacing: 6) {
                    day
                    times
                    VStack(alignment: .leading, spacing: 2) {
                        hours
                        if showPay { pay }
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        day
                        times
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        hours
                        if showPay { pay }
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
        }
    }

    private var day: some View {
        Text(row.day)
            .font(.tcHeadline)
            .foregroundStyle(Palette.ink)
    }

    private var hours: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(row.hours).numberStyle(.stat)
            Text("hrs").font(.subheadline)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(Palette.ink)
    }

    private var pay: some View {
        Text(row.pay)
            .numberStyle(.small)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(Palette.muted)
    }

    /// "7:02 AM – 3:31 PM" as one piece of text, so large sizes wrap at the dash, not inside a time.
    private var times: some View {
        func whole(_ s: String) -> String { s.replacingOccurrences(of: " ", with: "\u{00A0}") }
        let out = Text(whole(row.clockOut ?? "now")).foregroundStyle(row.clockOut == nil ? Palette.firText : Palette.ink)
        return AdaptiveStack(spacing: 6, alignment: .firstTextBaseline) {
            Text("\(whole(row.clockIn))\u{00A0}– \(out)")
                .numberStyle(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if row.endsNextDay {
                Text("next day")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.sapInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.sapSoft, in: Capsule())
            }
        }
    }

    private func detail<Content: View>(icon: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: iconWidth)
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
