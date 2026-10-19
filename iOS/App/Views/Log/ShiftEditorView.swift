import SwiftUI
import TimeCardCore

/// Edits one shift (or adds one when `shiftId` is nil): date, clock in and out (out may be the
/// next day), breaks with their reasons, and notes. Every problem is a `ShiftRules` message.
/// Deleting asks twice and takes the shift's tree marks with it.
/// Opened from the Log tab and from the Clock tab's "fix the times" warning.
struct ShiftEditorView: View {
    var shiftId: UUID?
    /// Hears "Shift saved.", "Shift deleted. 48 trees unmarked." and so on, to show after the sheet closes.
    var onFinish: ((String) -> Void)?
    @Environment(TimeCardSession.self) private var session

    init(shiftId: UUID?, onFinish: ((String) -> Void)? = nil) {
        self.shiftId = shiftId
        self.onFinish = onFinish
    }

    var body: some View {
        EditorHost(session: session, shiftId: shiftId, onFinish: onFinish)
    }
}

/// Makes the model once, when the sheet appears. (Making it in `init` would rebuild it, and
/// re-index every tree mark, on each snapshot change while the sheet is open.)
private struct EditorHost: View {
    var session: TimeCardSession
    var shiftId: UUID?
    var onFinish: ((String) -> Void)?
    @State private var load: Load = .waiting
    @Environment(\.dismiss) private var dismiss

    private enum Load {
        case waiting
        case ready(ShiftEditorModel)
        case missing
    }

    var body: some View {
        NavigationStack {
            Group {
                switch load {
                case .waiting:
                    Color.clear
                case .ready(let model):
                    EditorForm(model: model) { message in
                        onFinish?(message)
                        dismiss()
                    }
                case .missing:
                    MissingShift { dismiss() }
                }
            }
            .screenBackground()
        }
        .onAppear {
            guard case .waiting = load else { return }
            load = ShiftEditorModel(session: session, shiftId: shiftId).map(Load.ready) ?? .missing
        }
    }
}

/// Which picker is open. Only one at a time, so the form stays short.
private enum EditorField: Hashable {
    case date, clockIn, clockOut
    case breakStart(UUID), breakEnd(UUID)
}

private struct EditorForm: View {
    @Bindable var model: ShiftEditorModel
    var finish: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var open: EditorField?
    @State private var confirmingDiscard = false
    @FocusState private var typing: Bool

    private var hasChanges: Bool { model.draft != model.initialDraft }

    private var calendar: FarmCalendar { model.calendar }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    whenCard
                    breaksCard
                    notesCard
                    if !model.isNew {
                        treesCard
                        deleteSection
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: open)
                .animation(.easeInOut(duration: 0.2), value: model.draft.breaks.count)
                .animation(.easeInOut(duration: 0.2), value: model.stage)
            }
            // Whatever just opened scrolls into view, clear of the save bar.
            .onChange(of: open) { _, field in
                guard let field else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(field, anchor: .center) }
            }
            .onChange(of: model.draft.breaks.count) { old, new in
                guard new > old, let added = model.draft.breaks.last else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(added.id, anchor: .center) }
            }
            .onChange(of: model.stage) { _, stage in
                guard stage == .confirmingDelete else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("delete-panel", anchor: .bottom) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .environment(\.timeZone, calendar.timeZone)
        .navigationTitle(model.isNew ? "Add a Shift" : "Edit Shift")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    typing = false
                    if hasChanges { confirmingDiscard = true } else { dismiss() }
                }
                .accessibilityIdentifier("editor-cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("editor-save-top")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { typing = false }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // While "Delete this shift?" is up, its two answers are the only big buttons.
            if model.stage == .editing {
                saveBar
            }
        }
        .interactiveDismissDisabled(hasChanges)
        // An alert, not a popover: both answers stay on screen as big targets.
        .alert(LogWording.discardQuestion, isPresented: $confirmingDiscard) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: When

    private var whenCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let owner = model.ownerLine {
                Label(owner, systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.sapInk)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("editor-owner")
            }
            SectionLabel("When")
                .padding(.bottom, 6)
            dateRow.id(EditorField.date)
            Divider().overlay(Palette.line)
            PickerRow(title: "Clock in", value: Fmt.time(model.draft.startDate(calendar), calendar),
                      isExpanded: open == .clockIn, identifier: "editor-clock-in",
                      toggle: { toggle(.clockIn) }) {
                DatePicker("Clock in", selection: timeBinding(get: { model.draft.start }, set: { model.draft.start = $0 }),
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
            }
            .id(EditorField.clockIn)
            if model.canStayOpen {
                Divider().overlay(Palette.line)
                Toggle("Still on the clock", isOn: Binding(get: { model.draft.end == nil }, set: { model.setStillOnTheClock($0) }))
                    .toggleStyle(GloveToggleStyle())
                    .accessibilityIdentifier("editor-still-open")
            }
            if let end = model.draft.end {
                Divider().overlay(Palette.line)
                PickerRow(title: "Clock out", value: Fmt.time(model.draft.endDate(calendar) ?? Date(), calendar),
                          tag: model.draft.dayTag(end, calendar),
                          isExpanded: open == .clockOut, identifier: "editor-clock-out",
                          toggle: { toggle(.clockOut) }) {
                    DatePicker("Clock out", selection: timeBinding(get: { end }, set: { model.draft.end = $0 }),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .id(EditorField.clockOut)
            }
            Text(model.totalsLine)
                .numberStyle(.small)
                .foregroundStyle(Palette.muted)
                .padding(.top, 8)
                .accessibilityIdentifier("editor-totals")
        }
        .card()
    }

    /// The day, with big previous/next buttons (most fixes are a day or two back).
    private var dateRow: some View {
        let today = calendar.dayKey(Date())
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Date")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 4)
                Button { shiftDay(-1) } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.firText)
                .accessibilityLabel("Day before")
                .accessibilityIdentifier("editor-day-back")
                Button { toggle(.date) } label: {
                    Text(Fmt.day(calendar.date(on: model.draft.day, hour: 12, minute: 0), calendar))
                        .font(.body.weight(.medium))
                        .foregroundStyle(open == .date ? Palette.firText : Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(open == .date ? Palette.firSoft : Palette.stripe, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(open == .date ? Palette.fir.opacity(0.35) : Palette.line, lineWidth: 1))
                        .frame(minHeight: GloveButtonStyle.minHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Date")
                .accessibilityValue(Fmt.dayLong(calendar.date(on: model.draft.day, hour: 12, minute: 0), calendar))
                .accessibilityIdentifier("editor-date")
                Button { shiftDay(1) } label: {
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                        .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.firText)
                .disabled(model.draft.day >= today)
                .accessibilityLabel("Day after")
                .accessibilityIdentifier("editor-day-forward")
            }
            if open == .date {
                DatePicker("Date", selection: dayBinding, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Palette.fir)
                    .labelsHidden()
                    // The farm's weeks: Monday first on a Monday farm, as on the Log.
                    .environment(\.calendar, calendar.calendar)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Breaks

    private var breaksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Breaks")
                Text("Listed on your time card, not counted as hours.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            }
            ForEach(Array(model.draft.breaks.enumerated()), id: \.element.id) { index, item in
                breakEditor(index: index, item: item)
            }
            Button {
                model.addBreak()
                typing = false
            } label: {
                Label(model.draft.breaks.contains { $0.kind == .lunch } ? "Add a break" : "Add lunch or a break", systemImage: "plus")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("editor-add-break")
        }
        .card()
    }

    private func breakEditor(index: Int, item: BreakDraft) -> some View {
        let id = item.id
        let binding = Binding<BreakDraft>(
            get: { model.draft.breaks.first { $0.id == id } ?? item },
            set: { new in if let i = model.draft.breaks.firstIndex(where: { $0.id == id }) { model.draft.breaks[i] = new } })
        let isLast = index == model.draft.breaks.count - 1
        let number = Text("\(index + 1)")
            .numberStyle(.small)
            .foregroundStyle(Palette.sapInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(minWidth: 26, minHeight: 26)
            .background(Palette.sapSoft, in: Capsule())
            .accessibilityLabel("Break \(index + 1)")
        let kind = GloveSegmented(options: [(BreakKind.lunch, "Lunch"), (BreakKind.break, "Break")],
                                  selection: binding.kind, identifier: "editor-break-kind")
        let remove = Button(role: .destructive) {
            model.removeBreak(id)
        } label: {
            Image(systemName: "trash")
                .font(.body.weight(.semibold))
                .frame(width: GloveButtonStyle.minHeight, height: GloveButtonStyle.minHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.rust)
        .accessibilityLabel("Remove break \(index + 1)")
        .accessibilityIdentifier("editor-remove-break")
        return VStack(alignment: .leading, spacing: 6) {
            if typeSize.isAccessibilitySize {
                // Lunch | Break gets the whole width, so neither word breaks.
                HStack(spacing: 8) {
                    number
                    Spacer(minLength: 8)
                    remove
                }
                kind
            } else {
                HStack(spacing: 8) {
                    number
                    kind
                    remove
                }
            }
            PickerRow(title: "Start", value: Fmt.time(model.draft.date(item.start, calendar), calendar),
                      tag: model.draft.dayTag(item.start, calendar),
                      isExpanded: open == .breakStart(id), identifier: "editor-break-start",
                      toggle: { toggle(.breakStart(id)) }) {
                DatePicker("Break start", selection: timeBinding(get: { binding.wrappedValue.start }, set: { binding.wrappedValue.start = $0 }),
                           displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
            }
            .id(EditorField.breakStart(id))
            if model.draft.end == nil && isLast {
                Toggle("Still on this break", isOn: Binding(
                    get: { binding.wrappedValue.end == nil },
                    set: { stillOn in binding.wrappedValue.end = stillOn ? nil : WallClock(Date(), calendar).unpinned }))
                    .toggleStyle(GloveToggleStyle())
            }
            if let end = item.end {
                PickerRow(title: "End", value: Fmt.time(model.draft.date(end, breakStart: item.start, calendar), calendar),
                          tag: model.draft.dayTag(end, breakStart: item.start, calendar),
                          isExpanded: open == .breakEnd(id), identifier: "editor-break-end",
                          toggle: { toggle(.breakEnd(id)) }) {
                    DatePicker("Break end", selection: timeBinding(get: { end }, set: { binding.wrappedValue.end = $0 }),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                .id(EditorField.breakEnd(id))
            } else if model.draft.end != nil || !isLast {
                // A break left open on a finished shift: ShiftRules asks for an end time.
                Button {
                    binding.wrappedValue.end = .minutes(item.start.minutesIntoDay + 15)
                    toggle(.breakEnd(id))
                } label: {
                    Label("Set an end time", systemImage: "clock")
                }
                .buttonStyle(.gloveSecondary)
            }
            TextField("Reason (optional)", text: Binding(
                get: { binding.wrappedValue.reason },
                set: { binding.wrappedValue.reason = String($0.prefix(Limits.reason)) }))
                .textFieldStyle(.glove)
                .focused($typing)
                .submitLabel(.done)
                .accessibilityIdentifier("editor-break-reason")
        }
        .padding(12)
        .background(Palette.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .transition(.opacity)
        .id(id)
    }

    // MARK: Notes

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Notes")
            ZStack(alignment: .topLeading) {
                if model.draft.notes.isEmpty {
                    Text("Anything worth remembering about this shift")
                        .font(.body)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(get: { model.draft.notes }, set: { model.draft.notes = String($0.prefix(Limits.notes)) }))
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .frame(minHeight: 110)
                    .focused($typing)
                    .accessibilityLabel("Notes")
                    .accessibilityIdentifier("editor-notes")
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            if model.draft.notes.count > Limits.notes - 300 {
                Text("\(Fmt.count(model.draft.notes.count)) of \(Fmt.count(Limits.notes)) characters")
                    .numberStyle(.small)
                    .foregroundStyle(model.draft.notes.count >= Limits.notes ? Palette.rust : Palette.muted)
            }
        }
        .card()
    }

    // MARK: Trees

    private var treesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Trees")
            Text(model.trees > 0 ? Fmt.plural(model.trees, "tree") : "No trees marked on this shift")
                .font(.tcHeadline)
                .foregroundStyle(Palette.ink)
            if !model.treeSummary.isEmpty {
                Text(model.treeSummary)
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Delete

    @ViewBuilder
    private var deleteSection: some View {
        switch model.stage {
        case .editing:
            Button {
                typing = false
                model.askToDelete()
            } label: {
                Label("Delete shift", systemImage: "trash")
                    .foregroundStyle(Palette.rust)
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("editor-delete")
            .padding(.top, 8)
        case .confirmingDelete:
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(model.deleteQuestion)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.rust)
                }
                .accessibilityIdentifier("editor-delete-question")
                Button(role: .destructive) {
                    if let message = model.delete() {
                        AppModel.shared.actions.publishLiveSnapshot()
                        finish(message)
                    }
                } label: {
                    Text(model.deleteButton)
                }
                .buttonStyle(ConfirmDeleteStyle())
                .accessibilityIdentifier("editor-confirm-delete")
                Button("Keep this shift") { model.cancelDelete() }
                    .buttonStyle(.gloveSecondary)
                    .accessibilityIdentifier("editor-keep")
            }
            .padding(16)
            .background(Palette.rust.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.rust.opacity(0.45), lineWidth: 1))
            .padding(.top, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .id("delete-panel")
        }
    }

    // MARK: Save

    private var saveBar: some View {
        VStack(spacing: 10) {
            if let problem = model.visibleProblem {
                ErrorMessage(text: problem)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(problem)
                    .accessibilityIdentifier("editor-problem")
                    .transition(.opacity)
            }
            Button { save() } label: {
                Text(model.isNew ? "Add shift" : "Save shift")
            }
            .buttonStyle(.glovePrimary)
            .accessibilityIdentifier("editor-save")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(Palette.bg.opacity(0.96).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(Palette.line) }
        .animation(.easeInOut(duration: 0.2), value: model.visibleProblem)
    }

    private func save() {
        typing = false
        if let message = model.save() {
            AppModel.shared.actions.publishLiveSnapshot()
            finish(message)
        } else if let problem = model.visibleProblem {
            AccessibilityNotification.Announcement(problem).post()
        }
    }

    // MARK: Helpers

    private func toggle(_ field: EditorField) {
        typing = false
        open = open == field ? nil : field
    }

    private func shiftDay(_ days: Int) {
        let noon = calendar.date(on: model.draft.day, hour: 12, minute: 0)
        let next = calendar.dayKey(calendar.addDays(noon, days))
        guard next <= calendar.dayKey(Date()) else { return }
        model.draft.day = next
    }

    private var dayBinding: Binding<Date> {
        Binding(
            get: { calendar.date(on: model.draft.day, hour: 12, minute: 0) },
            set: { model.draft.day = calendar.dayKey($0) })
    }

    /// A picker date for a time of day; setting it keeps only the hour and minute.
    private func timeBinding(get: @escaping () -> WallClock, set: @escaping (WallClock) -> Void) -> Binding<Date> {
        let cal = calendar
        let day = model.draft.day
        return Binding(
            get: { let c = get(); return cal.date(on: day, hour: c.hour, minute: c.minute) },
            set: { date in
                let c = cal.calendar.dateComponents([.hour, .minute], from: date)
                set(WallClock(hour: c.hour ?? 0, minute: c.minute ?? 0))
            })
    }
}

// MARK: Pieces

/// A toggle whose whole row is the tap target.
struct GloveToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Palette.fir : Palette.line)
                    .frame(width: 51, height: 31)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    }
            }
            .frame(minHeight: GloveButtonStyle.minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

/// The one button that can't be undone: white on rust, with a deeper rust in dark mode so the
/// text keeps at least 4.5:1 contrast there too (the light-mode rust is already 6.7:1).
private struct ConfirmDeleteStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    /// #B4452B: white on it is 5.5:1.
    private static let darkFill = Color(red: 0xB4 / 255, green: 0x45 / 255, blue: 0x2B / 255)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: GloveButtonStyle.minHeight)
            .background(scheme == .dark ? Self.darkFill : Palette.rust, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MissingShift: View {
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LogWording.missing)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Close", action: close)
                .buttonStyle(.glovePrimary)
        }
        .card(padding: 20)
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle("Edit Shift")
        .navigationBarTitleDisplayMode(.inline)
    }
}
