import SwiftUI
import TimeCardCore

/// The Clock tab: the big status card, where you're working with the lock screen's row
/// buttons, trees this shift, pace, shift notes, and hours and pay. Settings opens from the gear.
///
/// Every clock and row button runs through `AppModel.actions` (FieldActions, by way of
/// `performInApp`, which also teaches Siri), the same path Siri and the Live Activity take,
/// and shows what Siri would have said as a toast.
struct ClockView: View {
    @Environment(AppModel.self) private var model
    @Environment(TimeCardSession.self) private var session
    @Environment(\.openTab) private var openTab
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("clock.showPay") private var showPay = true

    @State private var sheet: ClockSheet?
    @State private var toast: ClockToast?
    @State private var confirmingOut = false
    /// Bumped after each action: the work position lives outside the observed snapshot.
    @State private var refresh = 0
    @State private var notes = ShiftNotesEditor()
    /// What the cards show, worked out once per change to the farm, not on every redraw.
    @State private var derivedCache = ClockDerivedCache()
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
                    VStack(spacing: 0) {
                        ToastView(toast: toast)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 14)
                            .background(Palette.bg, ignoresSafeAreaEdges: .top)
                        // What's under the message fades out instead of being cut through.
                        LinearGradient(colors: [Palette.bg, Palette.bg.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 22)
                    }
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
                    // At the largest sizes the name stops growing, so the clock and its
                    // buttons are on the first screen.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("clock-farm-name")
                if !subtitle.isEmpty && !typeSize.isAccessibilitySize {
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
        let derived = derivedCache.values(state: state, version: model.actions.stateVersion, live: model.actions.liveSnapshot())
        let working = derived.working
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
        } else if let field = derived.field {
            TreesCardView(content: .field(field), onOpenMap: mapAction)
                .id("trees")
        }

        if derived.hasTrees {
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
            onEditShift: { sheet = .editShift(status.shiftId) },
            onFixClockOut: { if let id = status.shiftId { sheet = .fixClockOut(id) } })
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
        case .fixClockOut(let id):
            ShiftEditorView(shiftId: id, suggestingEnd: true)
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
        let reply = withAnimation(.easeInOut(duration: 0.25)) { model.performInApp(command) }
        refresh += 1
        // A marked row already shows on the Now Working card ("✓ Row 10 marked · Undo"); a toast
        // over it would say the same thing twice. Clock and break actions still get one.
        let shownOnCard = reply.succeeded && command.marksTrees
            && model.actions.state().flatMap { NowWorking(state: $0, live: model.actions.liveSnapshot()) } != nil
        if (reply.succeeded || toastFailures) && !shownOnCard {
            withAnimation(.spring(duration: 0.3)) { toast = ClockToast(text: reply.speech, succeeded: reply.succeeded) }
        }
        if reply.succeeded || toastFailures {
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

extension FieldCommand {
    /// Marks rows or trees (what the Now Working card confirms on its own).
    var marksTrees: Bool {
        switch self {
        case .markNextRow, .markRow, .markTrees: true
        default: false
        }
    }
}

/// What the Clock tab can open on top of itself.
enum ClockSheet: Identifiable {
    case settings
    case breakReason
    case startTime(Shift)
    case editShift(UUID?)
    /// The editor with a clock-out filled in, for a shift open more than 24 hours.
    case fixClockOut(UUID)

    var id: String {
        switch self {
        case .settings: "settings"
        case .breakReason: "break"
        case .startTime(let shift): "start-\(shift.id)"
        case .editShift(let id): "edit-\(id?.uuidString ?? "new")"
        case .fixClockOut(let id): "fix-out-\(id)"
        }
    }
}

/// The Clock tab's cards, derived from the field state once per change (`FieldActions.stateVersion`
/// and the lock-screen snapshot), so a tap that redraws the tab several times doesn't walk the
/// field again each time.
@MainActor
final class ClockDerivedCache {
    struct Values {
        var working: NowWorking?
        var field: FieldSummary?
        var hasTrees: Bool
    }

    private var cached: (version: Int, live: LiveSnapshot?, values: Values)?

    func values(state: FieldState, version: Int, live: LiveSnapshot?) -> Values {
        if let cached, cached.version == version, cached.live == live { return cached.values }
        let index = state.index
        let working = NowWorking(state: state, live: live)
        let values = Values(working: working,
                            field: working == nil ? FieldSummary(state: state, index: index) : nil,
                            hasTrees: PaceCard.hasTrees(state: state, index: index))
        cached = (version, live, values)
        return values
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
