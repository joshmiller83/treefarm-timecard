import SwiftUI
import TimeCardCore

/// The Clock tab: the big status card, where you're working with the lock screen's row
/// buttons, trees this shift, pace, shift notes, and hours and pay. Settings opens from the gear.
///
/// Every clock and row button runs through `AppModel.actions` (FieldActions), the same path
/// Siri and the Live Activity take, and shows what Siri would have said as a toast.
struct ClockView: View {
    @Environment(AppModel.self) private var model
    @Environment(TimeCardSession.self) private var session
    @Environment(\.openTab) private var openTab
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("clock.showPay") private var showPay = true

    @State private var sheet: ClockSheet?
    @State private var toast: ClockToast?
    @State private var confirmingOut = false
    /// Bumped after each action: the work position lives outside the observed snapshot.
    @State private var refresh = 0
    @State private var notes = ShiftNotesEditor()
    /// The gear's box: 54 pt, a little larger at the biggest text sizes.
    @ScaledMetric(relativeTo: .title3) private var gearScaled: CGFloat = GloveButtonStyle.minHeight
    private var gearBox: CGFloat { min(72, max(GloveButtonStyle.minHeight, gearScaled)) }

    var body: some View {
        let _ = refresh
        let state = model.actions.state()
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        if let state {
                            content(state)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .task {
                    guard model.mode != .live, let target = ClockScenario.scrollTarget else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    proxy.scrollTo(target, anchor: .top)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .overlay(alignment: .top) {
                // Cards scroll under the status bar; keep the clock and battery readable.
                Color.clear
                    .frame(height: 0)
                    .background(Palette.bg, ignoresSafeAreaEdges: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                // At the top, clear of the row tiles, Break and Undo people tap next; and
                // taps pass straight through it, so a gloved tap never lands on the message.
                if let toast {
                    ToastView(toast: toast)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .frame(maxWidth: 640)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .id(toast.id)
                }
            }
        }
        .sensoryFeedback(trigger: toast) { _, new in
            guard let new else { return nil }
            return new.succeeded ? .success : .warning
        }
        .task(id: toast?.id) {
            guard let shown = toast else { return }
            try? await Task.sleep(for: shown.duration)
            if toast?.id == shown.id { withAnimation(.easeInOut(duration: 0.25)) { toast = nil } }
        }
        .sheet(item: $sheet, onDismiss: { refresh += 1 }) { sheet in
            sheetView(sheet, state: state)
        }
        .onChange(of: NotesSource(state?.openShift), initial: true) { _, source in
            notes.load(shiftId: source.id, notes: source.notes)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { notes.flush() }
        }
        .onAppear(perform: connectNotes)
        .onDisappear { notes.flush() }
        .task {
            if await ClockScenario.applyIfRequested(model) { refresh += 1 }
            guard model.mode != .live, let open = ClockScenario.sheetToOpen else { return }
            switch open {
            case "settings": sheet = .settings
            case "break": sheet = .breakReason
            case "start": if let shift = model.actions.state()?.openShift { sheet = .startTime(shift) }
            default: break
            }
        }
    }

    // MARK: Layout

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.farm?.name ?? "")
                    .headingStyle(.tcTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("clock-farm-name")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 8)
            Button { sheet = .settings } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.semibold))
                    // The glyph grows a little with the text, never past its glove-sized box.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(Palette.ink)
                    .frame(width: gearBox, height: gearBox)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
    }

    /// "Crew lead · Alex Rivera"
    private var subtitle: String {
        let member = session.membership
        let name = member?.displayName ?? session.me?.user.displayName ?? ""
        return [member?.jobTitle ?? "", name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func content(_ state: FieldState) -> some View {
        let status = ClockStatus(state: state, now: Date())
        let working = NowWorking(state: state, live: model.actions.liveSnapshot())
        // Who holds each tree, built once per redraw: a late-season farm has thousands of marks.
        let index = state.index

        // The card's words roll over with the clock (midnight, the 16-hour warning) without a tap.
        TimelineView(.everyMinute) { context in
            statusCard(state, status: ClockStatus(state: state, now: context.date))
        }
        .id("status")

        if status.phase == .off {
            offTheClockLinks
        }

        if let working {
            NowWorkingCardView(
                card: working,
                onMarkRow: { run(.markRow($0.rowRef)) },
                onBreak: { run(.startBreak(.break, reason: "")) },
                onUndo: { run(.undo) },
                onMove: { run(.moveTo(blockId: $0, row: nil)) })
                .id("now")
            TreesCardView(content: .shift(working), onOpenMap: mapAction)
                .id("trees")
        } else if let field = FieldSummary(state: state, index: index) {
            TreesCardView(content: .field(field), onOpenMap: mapAction)
                .id("trees")
        }

        if PaceCard.hasTrees(state: state, index: index) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let pace = PaceCard(state: state, index: index, now: context.date, showPay: showPay) {
                    PaceCardView(pace: pace)
                }
            }
            .id("pace")
        }

        if status.shiftId != nil {
            ShiftNotesCardView(editor: notes)
                .id("notes")
        }

        TimelineView(.periodic(from: .now, by: 15)) { context in
            HoursPayCardView(hours: HoursPay(state: state, now: context.date), showPay: $showPay) {
                sheet = .settings
            }
        }
        .id("hours")
    }

    private func statusCard(_ state: FieldState, status: ClockStatus) -> some View {
        StatusCardView(
            state: state,
            status: status,
            clockOutQuestion: confirmingOut ? model.actions.confirmation(for: .clockOut) : nil,
            confirmingOut: $confirmingOut,
            onClockIn: { run(.clockIn(fieldId: nil)) },
            onLunch: { run(.startBreak(.lunch, reason: "")) },
            onOtherBreak: { sheet = .breakReason },
            onBackToWork: { run(.endBreak) },
            onClockOut: { run(.clockOut) },
            onChangeStart: { if let open = state.openShift { sheet = .startTime(open) } },
            onEditShift: { sheet = .editShift(status.shiftId) })
    }

    private var offTheClockLinks: some View {
        HStack(spacing: 10) {
            Button { sheet = .editShift(nil) } label: {
                Label("Add a shift", systemImage: "plus")
            }
            .buttonStyle(.gloveSecondary)
            .accessibilityIdentifier("add-shift")
            if let openTab {
                Button { openTab(.log) } label: {
                    Label("Past shifts", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.gloveSecondary)
                .accessibilityIdentifier("past-shifts")
            }
        }
    }

    private var mapAction: (() -> Void)? {
        guard let openTab else { return nil }
        return { openTab(.trees) }
    }

    @ViewBuilder
    private func sheetView(_ sheet: ClockSheet, state: FieldState?) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .breakReason:
            BreakReasonSheet { reason in run(.startBreak(.break, reason: reason)) }
        case .startTime(let shift):
            StartTimeSheet(shift: shift, calendar: state?.calendar ?? FarmCalendar(timeZone: .current, weekStart: .monday)) { start in
                run(.changeStart(start), toastFailures: false)
            }
        case .editShift(let id):
            ShiftEditorView(shiftId: id)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("shift-editor-sheet")
        }
    }

    // MARK: Actions

    /// Runs a field command the way Siri and the lock screen do, then says what happened.
    @discardableResult
    private func run(_ command: FieldCommand, toastFailures: Bool = true) -> FieldReply {
        notes.flush()
        confirmingOut = false
        let reply = withAnimation(.easeInOut(duration: 0.25)) { model.actions.perform(command) }
        refresh += 1
        if reply.succeeded || toastFailures {
            withAnimation(.spring(duration: 0.3)) { toast = ClockToast(text: reply.speech, succeeded: reply.succeeded) }
            AccessibilityNotification.Announcement(reply.speech).post()
        }
        return reply
    }

    /// Notes save straight onto the open shift through the session, stamped to the millisecond.
    private func connectNotes() {
        let session = self.session
        notes.save = { shiftId, text in
            guard let shift = session.snapshot.shifts[shiftId],
                  let updated = ShiftNotesEditor.updated(shift, notes: text, now: Date()) else { return }
            try session.save([.shift(updated)])
        }
    }
}

/// What the Clock tab can open on top of itself.
enum ClockSheet: Identifiable {
    case settings
    case breakReason
    case startTime(Shift)
    case editShift(UUID?)

    var id: String {
        switch self {
        case .settings: "settings"
        case .breakReason: "break"
        case .startTime(let shift): "start-\(shift.id)"
        case .editShift(let id): "edit-\(id?.uuidString ?? "new")"
        }
    }
}

/// The open shift's notes, to notice when they change elsewhere.
private struct NotesSource: Equatable {
    var id: UUID?
    var notes: String

    init(_ shift: Shift?) {
        id = shift?.id
        notes = shift?.notes ?? ""
    }
}
