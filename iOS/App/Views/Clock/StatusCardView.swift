import SwiftUI
import TimeCardCore

/// The big card at the top of the Clock tab, as on the web time card: paper while off the
/// clock, fir green while working, sap gold on a break, with a live h:mm:ss.
struct StatusCardView: View {
    var state: FieldState
    var status: ClockStatus
    /// FieldEngine's question for clocking out: "You’ve worked 7 hours 12 minutes today. Clock out?"
    var clockOutQuestion: String?
    @Binding var confirmingOut: Bool
    var onClockIn: () -> Void
    var onLunch: () -> Void
    var onOtherBreak: () -> Void
    var onBackToWork: () -> Void
    var onClockOut: () -> Void
    var onChangeStart: () -> Void
    var onEditShift: () -> Void
    /// Opens the editor with a clock-out filled in, for a shift open longer than a shift may be.
    var onFixClockOut: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize
    /// When "Tap again to clock out" appeared.
    @State private var armedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            top
            timer
                .padding(.top, 10)
            Text(status.workedLabel)
                .font(.subheadline.weight(.medium))
                .opacity(0.88)
                .fixedSize(horizontal: false, vertical: true)
                // The timer says it, so VoiceOver doesn't hear "worked today" twice.
                .accessibilityHidden(true)
            if status.isOnBreak {
                breakLine
                    .padding(.top, 10)
            }
            ForEach(status.meta, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, status.isOnBreak ? 2 : 10)
                    .accessibilityIdentifier("status-meta")
            }
            if let stale = status.stale {
                staleWarning(stale)
                    .padding(.top, 12)
            }
            if status.shiftId != nil {
                shiftChips
                    .padding(.top, 12)
            }
            actions
                .padding(.top, 14)
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(border, lineWidth: 1))
        .animation(.easeInOut(duration: 0.25), value: status.phase)
        .task(id: confirmingOut) {
            // "Tap again to clock out" waits five seconds, then quietly goes back.
            guard confirmingOut else { return }
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation { confirmingOut = false } }
        }
    }

    // MARK: Pieces

    private var top: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ClockPill(text: status.pill, tone: pillTone)
                Spacer(minLength: 8)
                dateLabel
            }
            VStack(alignment: .leading, spacing: 8) {
                ClockPill(text: status.pill, tone: pillTone)
                dateLabel
            }
        }
    }

    private var dateLabel: some View {
        Text(status.dateText)
            .font(.subheadline)
            .opacity(0.88)
    }

    @ViewBuilder
    private var timer: some View {
        if status.isWorking {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                bigClock(ClockStatus.worked(state: state, now: context.date))
            }
        } else {
            bigClock(status.worked)
        }
    }

    private func bigClock(_ worked: TimeInterval) -> some View {
        Text(Fmt.hms(worked))
            .font(.tcTimer)
            .monospacedDigit()
            .tracking(-1)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
            .accessibilityLabel("\(Fmt.spokenDuration(worked)) \(status.workedLabel.replacingOccurrences(of: " · ", with: ", "))")
            .accessibilityAddTraits(status.isWorking ? .updatesFrequently : [])
            .accessibilityIdentifier("big-timer")
    }

    private var breakLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                breakText
                Spacer(minLength: 4)
                breakSoFar
            }
            VStack(alignment: .leading, spacing: 2) {
                breakText
                breakSoFar
            }
        }
    }

    private var breakText: some View {
        Text(status.breakLine ?? "")
            .font(.callout.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("break-line")
    }

    private var breakSoFar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(status.breakStart ?? context.date)
            Text("\(Text(Fmt.hms(elapsed)).font(.tcNumber).fontWeight(.semibold).monospacedDigit()) so far")
                .font(.callout)
                .accessibilityLabel("\(Fmt.spokenDuration(elapsed)) so far")
        }
    }

    private func staleWarning(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("\(text) \(Speech.fixTheTimes)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(ClockColors.alarm)
            }
            .font(.callout)
            if !status.needsClockOutFix {
                Button("Fix the times", action: onEditShift)
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("fix-times")
            }
        }
        .foregroundStyle(Palette.paperInk)
        .padding(12)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stale-warning")
    }

    private var shiftChips: some View {
        let chip: CardButtonStyle.Kind = status.isOnBreak ? .chipOnSap : .chipOnFir
        return twoUp {
            changeStartButton.buttonStyle(.card(chip))
        } second: {
            editShiftButton.buttonStyle(.card(chip))
        }
    }

    private var changeStartButton: some View {
        Button(action: onChangeStart) {
            Label("Change start time", systemImage: "clock.arrow.circlepath")
        }
        .accessibilityIdentifier("change-start")
    }

    private var editShiftButton: some View {
        Button(action: onEditShift) {
            Label("Edit this shift", systemImage: "square.and.pencil")
        }
        .accessibilityIdentifier("edit-shift")
    }

    @ViewBuilder
    private var actions: some View {
        switch status.phase {
        case .off:
            Button(action: onClockIn) {
                Label("Clock in", systemImage: "play.fill")
            }
            .buttonStyle(.glovePrimary)
            .accessibilityIdentifier("clock-in")

        case .working:
            VStack(spacing: 10) {
                twoUp {
                    Button(action: onLunch) { Label("Lunch", systemImage: "fork.knife") }
                        .buttonStyle(.card(.onFir))
                        .accessibilityIdentifier("start-lunch")
                } second: {
                    Button(action: onOtherBreak) { Label("Other break", systemImage: "cup.and.saucer") }
                        .buttonStyle(.card(.onFir))
                        .accessibilityIdentifier("start-break")
                }
                clockOut(outline: .outlineOnFir, confirm: .confirmOnFir)
            }

        case .onBreak:
            VStack(spacing: 10) {
                Button(action: onBackToWork) {
                    Label("Back to work", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.glovePrimary)
                .accessibilityIdentifier("back-to-work")
                clockOut(outline: .outlineOnSap, confirm: .confirmOnSap)
            }
        }
    }

    @ViewBuilder
    private func clockOut(outline: CardButtonStyle.Kind, confirm: CardButtonStyle.Kind) -> some View {
        if status.needsClockOutFix {
            // Clock out would make a shift longer than 24 hours, which the server refuses.
            Button(action: onFixClockOut) {
                Label("Fix clock-out time", systemImage: "clock.badge.exclamationmark")
            }
            .buttonStyle(.card(confirm))
            .accessibilityIdentifier("fix-clock-out")
            .accessibilityHint("Opens the shift with a clock-out time filled in.")
        } else {
            twoStepClockOut(outline: outline, confirm: confirm)
        }
    }

    private func twoStepClockOut(outline: CardButtonStyle.Kind, confirm: CardButtonStyle.Kind) -> some View {
        VStack(spacing: 8) {
            if confirmingOut, let clockOutQuestion {
                Text(clockOutQuestion)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    .accessibilityIdentifier("clock-out-question")
            }
            Button {
                switch ClockOutTap.decide(armedAt: confirmingOut ? armedAt : nil, now: Date()) {
                case .arm:
                    armedAt = Date()
                    withAnimation(.easeOut(duration: 0.15)) { confirmingOut = true }
                case .ignore:
                    break
                case .confirm:
                    confirmingOut = false
                    armedAt = nil
                    onClockOut()
                }
            } label: {
                Label(confirmingOut ? "Tap again to clock out" : "Clock out", systemImage: confirmingOut ? "exclamationmark.circle.fill" : "stop.fill")
            }
            .buttonStyle(.card(confirmingOut ? confirm : outline))
            .accessibilityIdentifier("clock-out")
            .accessibilityHint(confirmingOut ? "Ends your shift." : "Asks once more before ending your shift.")
            .sensoryFeedback(.impact(weight: .medium), trigger: confirmingOut) { _, new in new }
        }
    }

    /// Two buttons side by side, stacked at the largest text sizes.
    @ViewBuilder
    private func twoUp<A: View, B: View>(@ViewBuilder first: () -> A, @ViewBuilder second: () -> B) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { first(); second() }
        } else {
            HStack(spacing: 10) { first(); second() }
        }
    }

    // MARK: Colors

    private var pillTone: ClockPill.Tone {
        switch status.phase {
        case .off: .off
        case .working: .working
        case .onBreak: .onBreak
        }
    }

    private var background: Color {
        switch status.phase {
        case .off: Palette.surface
        case .working: Palette.fir
        case .onBreak: Palette.sapSoft
        }
    }

    private var ink: Color {
        switch status.phase {
        case .off: Palette.ink
        case .working: Palette.firInk
        case .onBreak: Palette.sapInk
        }
    }

    private var border: Color {
        switch status.phase {
        case .off: Palette.line
        case .working: Palette.fir
        case .onBreak: Palette.sap
        }
    }
}

/// The two-step Clock out. The confirming tap counts only after a short pause, so a bouncy
/// gloved double tap shows "Tap again to clock out" but can't also end the shift.
enum ClockOutTap: Equatable {
    case arm
    case ignore
    case confirm

    static let settle: TimeInterval = 0.6

    /// `armedAt` is when "Tap again" appeared, or nil when it isn't showing.
    static func decide(armedAt: Date?, now: Date) -> ClockOutTap {
        guard let armedAt else { return .arm }
        return now.timeIntervalSince(armedAt) < settle ? .ignore : .confirm
    }
}
