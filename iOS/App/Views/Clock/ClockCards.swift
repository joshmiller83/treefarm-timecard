import Charts
import SwiftUI
import TimeCardCore

// MARK: Trees

/// "Trees this shift" while working; the field's progress while off the clock.
struct TreesCardView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    enum Content {
        case shift(NowWorking)
        case field(FieldSummary)
    }

    var content: Content
    var onOpenMap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                count
                mapButton
            } else {
                HStack(alignment: .center, spacing: 12) {
                    count
                    Spacer(minLength: 8)
                    mapButton.fixedSize()
                }
            }
            Text(line)
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                // Read with the count (below), so the button stays its own element.
                .accessibilityHidden(true)
            if total > 0 {
                FieldProgressBar(fraction: Double(shaped) / Double(total))
                    .padding(.top, 2)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trees-card")
    }

    /// The count, the line and the progress bar read as one element; the map button is its own.
    private var count: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label)
            Text(big)
                .font(.custom(Typeface.numberSemiBold, size: 34, relativeTo: .largeTitle))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(big). \(line)")
        .accessibilityIdentifier("trees-card-summary")
    }

    @ViewBuilder
    private var mapButton: some View {
        if let onOpenMap {
            Button(action: onOpenMap) {
                Label(buttonTitle, systemImage: "map")
            }
            .buttonStyle(GloveButtonStyle(kind: isShift ? .primary : .secondary))
            .accessibilityIdentifier("trees-card-map")
        }
    }

    private var isShift: Bool {
        if case .shift = content { return true }
        return false
    }

    private var label: String { isShift ? "Trees this shift" : "Field" }
    private var buttonTitle: String { isShift ? "Mark trees" : "See the field" }

    private var big: String {
        switch content {
        case .shift(let card): Fmt.count(card.shiftTrees)
        case .field(let summary): "\(summary.percent)%"
        }
    }

    private var shaped: Int {
        switch content {
        case .shift(let card): card.fieldShaped
        case .field(let summary): summary.shaped
        }
    }

    private var total: Int {
        switch content {
        case .shift(let card): card.fieldTotal
        case .field(let summary): summary.total
        }
    }

    private var line: String {
        switch content {
        case .shift(let card):
            guard card.fieldTotal > 0 else { return "No trees on the map yet." }
            return "\(Fmt.count(card.fieldShaped)) of \(Fmt.plural(card.fieldTotal, "tree")) shaped in \(card.fieldName) · \(card.fieldPercent)%"
        case .field(let summary):
            return "\(summary.line) in \(summary.fieldName)"
        }
    }
}

// MARK: Pace

struct PaceCardView: View {
    var pace: PaceCard
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeading(title: "Pace") {
                Text("Counts shifts with trees marked")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            }
            Text(pace.headline)
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pace-headline")
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { columns }
            } else {
                HStack(alignment: .top, spacing: 8) { columns }
            }
            if !pace.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pace.notes, id: \.self) { note in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Palette.fir)
                                .frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { $0.height / 2 + 5 }
                                .accessibilityHidden(true)
                            Text(note)
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .card()
    }

    private var columns: some View {
        ForEach(pace.columns) { column in
            VStack(alignment: .leading, spacing: 2) {
                Text(column.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .opacity(0.85)
                Text(column.rate)
                    .numberStyle(.stat)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("trees an hour")
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text.numberPhrase(column.trees, .small)
                    Text.numberPhrase(column.each.replacingOccurrences(of: "/tree", with: " a tree"), .small)
                    if let pay = column.payEach { Text.numberPhrase(pay.replacingOccurrences(of: "/tree", with: " a tree"), .small) }
                }
                .opacity(0.85)
                .padding(.top, 4)
            }
            .foregroundStyle(column.isNow ? Palette.sapInk : Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(column.isNow ? Palette.sapSoft : Palette.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(column.title)
            .accessibilityValue(spoken(column))
        }
    }

    private func spoken(_ column: PaceCard.Column) -> String {
        guard column.rate != "–" else { return "No trees marked" }
        return ["\(column.rate) trees an hour", column.trees, column.each.replacingOccurrences(of: "/tree", with: " a tree"),
                column.payEach?.replacingOccurrences(of: "/tree", with: " a tree")]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: Notes

struct ShiftNotesCardView: View {
    @Bindable var editor: ShiftNotesEditor
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeading(title: "Shift notes") {
                statusText
            }
            TextEditor(text: $editor.text)
                .focused($focused)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if editor.text.isEmpty {
                        Text("Which rows or blocks, what you worked on, anything to remember")
                            .font(.body)
                            .foregroundStyle(Palette.muted)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? Palette.fir : Palette.line, lineWidth: focused ? 1.5 : 1))
                .onChange(of: editor.text) { editor.edited() }
                .onChange(of: focused) { _, now in
                    // Letting go saves what's typed, then shows anything that came in meanwhile.
                    if !now { editor.flush() }
                    editor.setEditing(now)
                }
                .accessibilityLabel("Shift notes")
                .accessibilityIdentifier("shift-notes")
            if let failure = editor.failure, editor.status == .failed {
                ErrorMessage(text: failure)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Notes go on the report next to this shift.")
                Spacer(minLength: 8)
                if editor.text.count > Limits.notes - 200 {
                    Text("\(Fmt.count(editor.text.count)) of \(Fmt.count(Limits.notes))")
                        .monospacedDigit()
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.muted)
        }
        .card()
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focused = false
                        editor.flush()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        Group {
            switch editor.status {
            case .idle: EmptyView()
            case .saving: Text("Saving…").foregroundStyle(Palette.muted)
            case .saved: Label("Saved", systemImage: "checkmark").foregroundStyle(Palette.firText)
            case .failed: Label("Couldn’t save", systemImage: "exclamationmark.triangle").foregroundStyle(Palette.rust)
            }
        }
        .font(.footnote.weight(.semibold))
        .accessibilityIdentifier("notes-state")
    }
}

// MARK: Hours and pay

struct HoursPayCardView: View {
    var hours: HoursPay
    @Binding var showPay: Bool
    var onSetRate: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeading(title: "Hours and pay") {
                Button(showPay ? "Hide pay" : "Show pay") {
                    withAnimation(.easeInOut(duration: 0.2)) { showPay.toggle() }
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.firText)
                .frame(minWidth: 54, minHeight: 54, alignment: .trailing)
                .contentShape(Rectangle())
                .accessibilityIdentifier("pay-toggle")
            }
            .padding(.bottom, -10)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    cell("Today", pay: hours.todayPay, hours: hours.todayHours, id: "today")
                    cell("This week", pay: hours.weekPay, hours: hours.weekHours, id: "week")
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    cell("Today", pay: hours.todayPay, hours: hours.todayHours, id: "today")
                    cell("This week", pay: hours.weekPay, hours: hours.weekHours, id: "week")
                }
            }
            if showPay && hours.needsRate {
                Button(action: onSetRate) {
                    Label("Add your hourly pay to see what you’ve earned", systemImage: "dollarsign.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityIdentifier("set-rate")
            }
            if typeSize.isAccessibilitySize {
                // Seven labels can't share one row at these sizes: one line per day instead.
                WeekList(hours: hours)
            } else {
                WeekChart(hours: hours)
                    // Seven day labels have to share one row; past this size they'd collide.
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .frame(height: 132)
            }
            Text(hours.footnote(showPay: showPay))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func cell(_ title: String, pay: String, hours: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title)
            if showPay && !self.hours.needsRate {
                Text(pay)
                    .font(.custom(Typeface.numberSemiBold, size: 27, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("pay-\(id)")
                Text.numberPhrase(hours, .small)
                    .foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("hours-\(id)")
            } else {
                Text(hours)
                    .font(.custom(Typeface.numberSemiBold, size: 27, relativeTo: .title))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("hours-\(id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The week at accessibility sizes: one row per day, today's in fir.
private struct WeekList: View {
    var hours: HoursPay

    var body: some View {
        VStack(spacing: 0) {
            ForEach(hours.days) { day in
                HStack {
                    Text(day.label)
                        .font(.body.weight(day.isToday ? .bold : .regular))
                        .foregroundStyle(day.isToday ? Palette.firText : Palette.ink)
                    Spacer(minLength: 8)
                    Text(day.hoursText)
                        .font(.tcNumberSmall)
                        .monospacedDigit()
                        .foregroundStyle(day.hours > 0 ? Palette.ink : Palette.muted)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.spoken)
                if day.id != hours.days.last?.id { Divider().overlay(Palette.line) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hours by day this week")
        .accessibilityIdentifier("week-chart")
    }
}

/// Seven bars for the farm's week, today's in full fir, with each day's hours under it.
private struct WeekChart: View {
    var hours: HoursPay

    var body: some View {
        Chart {
            // A faint line at a full day, so the bars have something to measure against. Days
            // off draw nothing (a full-height track read like data).
            if hours.chartMax >= 8 {
                RuleMark(y: .value("Hours", 8))
                    .foregroundStyle(Palette.line)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)
            }
            ForEach(hours.days) { day in
            BarMark(x: .value("Day", day.label), yStart: .value("Hours", 0), yEnd: .value("Hours", barHeight(day)), width: .ratio(0.6))
                .foregroundStyle(day.isToday ? Palette.fir : Palette.fir.opacity(0.62))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel(day.spoken)
            }
        }
        .chartYScale(domain: 0...hours.chartMax)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel(centered: true) {
                    if let label = value.as(String.self), let day = hours.days.first(where: { $0.label == label }) {
                        VStack(spacing: 1) {
                            Text(day.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(day.isToday ? Palette.firText : Palette.muted)
                            Text(day.hoursText)
                                .font(.tcNumberSmall)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Hours by day this week")
        .accessibilityIdentifier("week-chart")
    }

    private func barHeight(_ day: HoursPay.Day) -> Double {
        guard day.hours > 0 else { return 0 }
        return min(hours.chartMax, max(day.hours, hours.chartMax * 0.04))
    }
}
