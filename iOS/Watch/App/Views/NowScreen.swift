import SwiftUI
import TreeFarmKit

/// The primary screen on the clock (docs/watch.md 3.2, 3.3). It never scrolls, so Double Tap
/// always acts: it marks the row on the big button (or goes back to work on a break).
///
/// The Digital Crown picks among the next 3 rows; six seconds after it stops, the selection
/// snaps back to the next row. Every Double Tap and crown action is also an ordinary button.
struct NowScreen: View {
    let model: WatchShiftModel
    let state: WatchState
    let primaryEnabled: Bool
    let act: (FieldCommand, WatchSource) -> Void
    let showQueue: () -> Void

    @State private var chipIndex = 0
    @State private var snapBack: Task<Void, Never>?
    @State private var clockTick = Date()
    @FocusState private var crownFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var timerScale: CGFloat = 1
    @Environment(\.isLuminanceReduced) private var dimmed

    private let metrics = ButtonMetrics.current

    var body: some View {
        let phase = WatchDisplay.phase(state)
        let chips = WatchDisplay.chips(state)
        let primary = WatchDisplay.primary(state, chipIndex: chipIndex)
        let _ = clockTick
        let showUndoClockIn = model.canUndoClockIn

        VStack(spacing: metrics.isSmall ? 4 : 6) {
            info(phase: phase, compact: showUndoClockIn)
                .frame(maxHeight: .infinity)
                .watchToast(model.toast, alignment: .bottom)

            primaryButton(primary, chips: chips)

            if showUndoClockIn {
                Button {
                    Task { _ = await model.undoClockIn() }
                } label: {
                    GloveLabel(steps: [WatchDisplay.undoClockIn, WatchDisplay.undo], glyph: WatchDisplay.Glyph.undo,
                               font: .system(.headline, design: .rounded))
                }
                .buttonStyle(GloveButtonStyle(tone: .quiet, height: metrics.secondary))
                .accessibilityIdentifier("undoClockIn")
            }
        }
        .padding(.horizontal, 2)
        .background(PhaseGlow(phase: phase))
        .focusable(phase == .working && chips.count > 1)
        .focusEffectDisabled()
        .focused($crownFocused)
        .digitalCrownRotation(detent: $chipIndex, from: 0, through: max(0, chips.count - 1), by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true,
                              onChange: { _ in snapBack?.cancel() },
                              onIdle: scheduleSnapBack)
        .task {
            // Focus is fragile in a TabView: take it once the page has settled.
            try? await Task.sleep(for: .milliseconds(300))
            crownFocused = true
        }
        .onChange(of: primaryEnabled) { _, enabled in
            if enabled { crownFocused = true }
        }
        // Once a row is marked (here, by Siri, or on the phone), the crown is back on the next row.
        .onChange(of: state.nextRows) { _, _ in chipIndex = 0 }
        .task(id: model.undoClockInUntil) {
            // Undo clock-in goes away by itself after its 2 minutes.
            guard let until = model.undoClockInUntil else { return }
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.5))
            clockTick = Date()
        }
    }

    // MARK: The top: phase, timer, place

    @ViewBuilder
    private func info(phase: WatchPhase, compact: Bool) -> some View {
        let snapshot = state.snapshot
        VStack(alignment: .leading, spacing: metrics.isSmall ? 0 : 2) {
            HStack {
                PhaseTag(phase: phase, title: WatchDisplay.breakLine(state))
                Spacer(minLength: 4)
                if model.waitingCount > 0 {
                    QueueBadge(count: model.waitingCount, action: showQueue)
                } else {
                    SendingDot(visible: model.isSending)
                }
            }

            Spacer(minLength: 0)

            if let snapshot {
                timer(snapshot, phase: phase)
                subline(snapshot, phase: phase, compact: compact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func timer(_ snapshot: LiveSnapshot, phase: WatchPhase) -> some View {
        let font = Font.system(size: metrics.timer * timerScale, weight: .semibold, design: .rounded).monospacedDigit()
        Group {
            if phase == .working {
                Text(timerInterval: snapshot.timerStart...Date.distantFuture, countsDown: false)
                    .accessibilityLabel(WatchDisplay.timerAccessibility(snapshot.workedSoFar))
            } else if let start = snapshot.breakStart {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .accessibilityLabel(WatchDisplay.breakLine(state) ?? WatchDisplay.phaseTitle(phase))
            }
        }
        .font(font)
        .foregroundStyle(phase == .working ? Color.white : WatchPalette.sap)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityIdentifier("shiftTimer")
    }

    @ViewBuilder
    private func subline(_ snapshot: LiveSnapshot, phase: WatchPhase, compact: Bool) -> some View {
        if phase == .working {
            if !metrics.isSmall, !compact {
                Text(snapshot.workedLabel)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if !(compact && metrics.isSmall), let place = WatchDisplay.placeLine(state) {
                Text(placeWithHeart(place))
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(dimmed ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        } else {
            Text(WatchDisplay.workedLine(snapshot))
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    /// The 49 mm screen has room for the heart rate on the place line.
    private func placeWithHeart(_ place: String) -> String {
        guard metrics.isLarge, let bpm = ShiftWorkout.shared.live.heartRate else { return place }
        return "\(place) · ♥\(Int(bpm.rounded()))"
    }

    // MARK: The primary button

    @ViewBuilder
    private func primaryButton(_ primary: WatchDisplay.Primary, chips: [RowChip]) -> some View {
        let enabled = WatchDisplay.isPrimaryEnabled(primary)
        Button {
            guard let command = WatchDisplay.command(for: primary) else { return }
            act(command, .button)
            chipIndex = 0
        } label: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    GloveLabel(steps: model.isSlow ? [WatchDisplay.waitingForPhone] : WatchDisplay.primaryLabelSteps(primary),
                               glyph: model.isSlow ? "ellipsis" : WatchDisplay.primaryGlyph(primary),
                               font: metrics.primaryFont)
                    if case .outOfKnownRows = primary {
                        Text(Self.bringPhoneCloser)
                            .font(.system(.caption2, design: .rounded))
                            .opacity(0.8)
                    } else if metrics.isLarge, case .markRow(let chip) = primary {
                        Text(chip.blockName)
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .opacity(0.75)
                    }
                }
                .frame(maxWidth: .infinity)
                if chips.count > 1, case .markRow = primary {
                    CrownDots(count: chips.count, selected: chipIndex)
                        .padding(.trailing, 10)
                }
            }
        }
        .buttonStyle(GloveButtonStyle(tone: .fir, height: metrics.primary))
        .disabled(!enabled)
        .handGestureShortcut(.primaryAction, isEnabled: primaryEnabled && enabled)
        .accessibilityLabel(WatchDisplay.primaryAccessibilityLabel(primary))
        .accessibilityValue(chipValue(primary))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: chipIndex = min(chipIndex + 1, max(0, chips.count - 1))
            case .decrement: chipIndex = max(chipIndex - 1, 0)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("primaryAction")
    }

    /// The second sentence of `WatchDisplay.outOfKnownRows`, under the disabled button.
    static let bringPhoneCloser = WatchDisplay.outOfKnownRows.components(separatedBy: ". ").last ?? ""

    private func chipValue(_ primary: WatchDisplay.Primary) -> String {
        if case .markRow(let chip) = primary { return WatchDisplay.chipValue(chip) }
        return ""
    }

    private func scheduleSnapBack() {
        snapBack?.cancel()
        guard chipIndex != 0 else { return }
        snapBack = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { chipIndex = 0 }
        }
    }
}

/// The Digital Crown's three rows, stacked like the crown's own travel: the chosen one bright.
struct CrownDots: View {
    let count: Int
    let selected: Int

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == selected ? 1 : 0.35))
                    .frame(width: 4, height: i == selected ? 10 : 6)
            }
        }
        .accessibilityHidden(true)
    }
}
