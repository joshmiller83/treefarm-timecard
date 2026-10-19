import SwiftUI
import TimeCardCore

/// "Other break": an optional reason, with a few one-tap reasons for gloved hands.
struct BreakReasonSheet: View {
    var onStart: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @FocusState private var typing: Bool

    static let quickReasons = ["Fuel run", "Rain", "Sharpening", "Errand", "Restroom"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What’s the break for?")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        TextField("Fuel run, rain, errand, sharpening…", text: $reason)
                            .textFieldStyle(.glove)
                            .focused($typing)
                            .submitLabel(.go)
                            .onSubmit(start)
                            .onChange(of: reason) { if reason.count > Limits.reason { reason = String(reason.prefix(Limits.reason)) } }
                            .accessibilityIdentifier("break-reason")
                        Text("Optional. It shows on the log and the report.")
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Tap one")
                        FlowRows(spacing: 8) {
                            ForEach(Self.quickReasons, id: \.self) { quick in
                                let picked = reason == quick
                                Button {
                                    reason = picked ? "" : quick
                                    typing = false
                                } label: {
                                    Text(quick)
                                        .font(.callout.weight(.semibold))
                                        .padding(.horizontal, 18)
                                        .frame(minHeight: GloveButtonStyle.minHeight)
                                        .foregroundStyle(picked ? Palette.firInk : Palette.ink)
                                        .background(picked ? Palette.fir : Palette.surface, in: Capsule())
                                        .overlay(Capsule().strokeBorder(picked ? Palette.fir : Palette.line, lineWidth: 1))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(picked ? .isSelected : [])
                                .accessibilityIdentifier("reason-\(quick)")
                            }
                        }
                    }
                    Button(action: start) {
                        Label("Start break", systemImage: "cup.and.saucer.fill")
                    }
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("break-go")
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Other break")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func start() {
        onStart(reason)
        dismiss()
    }
}

/// "Change start time": a wheel picker in the farm's time zone. FieldEngine checks the new
/// start with ShiftRules, and its message shows here when the time won't work.
struct StartTimeSheet: View {
    var shift: Shift
    var calendar: FarmCalendar
    /// Runs the change and says how it went.
    var onSave: (Date) -> FieldReply
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date
    @State private var problem: String?

    init(shift: Shift, calendar: FarmCalendar, onSave: @escaping (Date) -> FieldReply) {
        self.shift = shift
        self.calendar = calendar
        self.onSave = onSave
        _picked = State(initialValue: shift.start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("You clocked in at \(Fmt.time(shift.start, calendar)) on \(Fmt.dayLong(shift.start, calendar)). When did you really start?")
                        .font(.body)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker("Start time", selection: $picked, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .environment(\.timeZone, calendar.timeZone)
                        .onChange(of: picked) { problem = nil }
                        .accessibilityIdentifier("start-picker")
                    if let problem {
                        ErrorMessage(text: problem)
                    }
                    Button("Save start time", action: save)
                        .buttonStyle(.glovePrimary)
                        .accessibilityIdentifier("start-save")
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Change start time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let start = StartTime.newStart(picked: picked, original: shift.start, calendar: calendar)
        guard start != shift.start else { dismiss(); return }
        let reply = onSave(start)
        if reply.succeeded {
            dismiss()
        } else {
            withAnimation { problem = reply.speech }
        }
    }
}

/// Lays children out in rows that wrap, like words in a sentence.
struct FlowRows: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let w = min(size.width, width)
            if !row.items.isEmpty && row.width + spacing + w > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + w
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// The message after a tap, what Siri would have said, floating above the tab bar.
struct ToastView: View {
    var toast: ClockToast

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toast.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(toast.succeeded ? ClockColors.pulse : Palette.sap)
                .accessibilityHidden(true)
            Text(toast.text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Palette.bg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toast")
    }
}
