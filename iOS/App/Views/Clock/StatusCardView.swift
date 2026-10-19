import SwiftUI
import TimeCardCore
import UIKit

/// The big card at the top of the Clock tab, as on the web time card: paper while off the
/// clock, fir green while working, sap gold on a break, with a live h:mm:ss.
///
/// The order is what a gloved hand needs: status, the big clock, then the actions (Lunch,
/// Other break, Clock out). Fixing the shift's times is a quiet row under them. At the
/// largest text sizes the actions come right under the clock, before the details.
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

    private var large: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            top
            timer
                .padding(.top, 10)
            if large {
                actions
                    .padding(.top, 14)
                details
                    .padding(.top, 14)
                staleBlock
                shiftRow
            } else {
                details
                staleBlock
                actions
                    .padding(.top, 14)
                shiftRow
            }
        }
        .foregroundStyle(ink)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(border, lineWidth: status.stale != nil ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.25), value: status.phase)
        .task(id: confirmingOut) {
            // "Tap again to clock out" goes back after a while, so a pocket bump can't finish the
            // job later. With VoiceOver or Switch Control it waits much longer (WCAG 2.2.1).
            guard confirmingOut else { return }
            try? await Task.sleep(for: .seconds(ClockOutTap.timeout(assistiveTech: Self.assistiveTechRunning)))
            if !Task.isCancelled { withAnimation { confirmingOut = false } }
        }
    }

    private static var assistiveTechRunning: Bool {
        UIAccessibility.isVoiceOverRunning || UIAccessibility.isSwitchControlRunning
    }

    // MARK: Pieces

    @ViewBuilder
    private var top: some View {
        if large {
            // The date is on the phone's own clock; at these sizes the room goes to the timer.
            ClockPill(text: status.pill, tone: pillTone, pulses: status.stale == nil)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ClockPill(text: status.pill, tone: pillTone, pulses: status.stale == nil)
                    Spacer(minLength: 8)
                    dateLabel
                }
                VStack(alignment: .leading, spacing: 8) {
                    ClockPill(text: status.pill, tone: pillTone, pulses: status.stale == nil)
                    dateLabel
                }
            }
        }
    }

    private var dateLabel: some View {
        Text(status.dateText)
            .font(.subheadline)
    }

    /// "worked today", the break line and the quiet lines under the timer.
    @ViewBuilder
    private var details: some View {
        Text(status.workedLabel)
            .font(.subheadline.weight(.medium))
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
    }

    @ViewBuilder
    private var staleBlock: some View {
        if let stale = status.stale {
            staleWarning(stale)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var timer: some View {
        if status.isWorking {
            // Ticks on the worked time's whole seconds, and adds the time since the card's
            // reading instead of adding up every shift again each second.
            TimelineView(.periodic(from: status.nextWholeSecond, by: 1)) { context in
                bigClock(status.bigClock(at: context.date))
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
        let start = status.breakStart ?? Date()
        let fraction = Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 1)
        return TimelineView(.periodic(from: Date().addingTimeInterval(1 - fraction), by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            Text("\(Text(Fmt.hms(elapsed)).font(.tcNumber).fontWeight(.semibold).monospacedDigit()) so far")
                .font(.callout)
                .accessibilityLabel("\(Fmt.spokenDuration(elapsed)) so far")
        }
    }

    /// A shift left open: a surface box with a rust mark, on a card with a rust edge and no pulse.
    private func staleWarning(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("\(text) \(Speech.fixTheTimes)")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.rust)
            }
            .font(.callout)
            if !status.needsClockOutFix {
                Button("Fix the times", action: onEditShift)
                    .buttonStyle(.glovePrimary)
                    .accessibilityIdentifier("fix-times")
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stale-warning")
    }

    /// Start time and Edit shift: one quiet row under the actions, still glove-sized.
    @ViewBuilder
    private var shiftRow: some View {
        if status.shiftId != nil {
            let chip: CardButtonStyle.Kind = status.isOnBreak ? .chipOnSap : .chipOnFir
            twoUp {
                Button(action: onChangeStart) {
                    Label("Start time", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.card(chip))
                .accessibilityLabel("Change start time")
                .accessibilityInputLabels(["Start time", "Change start time"])
                .accessibilityIdentifier("change-start")
            } second: {
                Button(action: onEditShift) {
                    Label("Edit shift", systemImage: "square.and.pencil")
                }
                .buttonStyle(.card(chip))
                .accessibilityInputLabels(["Edit shift", "Edit this shift"])
                .accessibilityIdentifier("edit-shift")
            }
            .padding(.top, 10)
        }
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
                        .accessibilityInputLabels(["Other break", "Break"])
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

    /// The button stays where it is when armed: the question appears under it, so a second
    /// gloved tap in the same place lands on the same button.
    private func twoStepClockOut(outline: CardButtonStyle.Kind, confirm: CardButtonStyle.Kind) -> some View {
        VStack(spacing: 8) {
            Button {
                switch ClockOutTap.decide(armedAt: confirmingOut ? armedAt : nil, now: Date()) {
                case .arm:
                    armedAt = Date()
                    withAnimation(.easeOut(duration: 0.15)) { confirmingOut = true }
                    if let clockOutQuestion {
                        AccessibilityNotification.Announcement(clockOutQuestion).post()
                    }
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
            .accessibilityLabel(confirmingOut ? "Confirm clock out" : "Clock out")
            .accessibilityValue(confirmingOut ? (clockOutQuestion ?? "") : "")
            .accessibilityInputLabels(["Clock out", "Confirm clock out"])
            .accessibilityIdentifier("clock-out")
            .accessibilityHint(confirmingOut ? "Ends your shift." : "Asks once more before ending your shift.")
            .sensoryFeedback(.impact(weight: .medium), trigger: confirmingOut) { _, new in new }

            if confirmingOut, let clockOutQuestion {
                Text(clockOutQuestion)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
                    // The button's value says it; the announcement said it once already.
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("clock-out-question")
            }
        }
    }

    /// Two buttons side by side, stacked at the largest text sizes.
    @ViewBuilder
    private func twoUp<A: View, B: View>(@ViewBuilder first: () -> A, @ViewBuilder second: () -> B) -> some View {
        if large {
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
        case .working: Palette.firCard
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
        if status.stale != nil { return Palette.rust }
        switch status.phase {
        case .off: return Palette.line
        case .working: return Palette.firCard
        case .onBreak: return Palette.sap
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

    /// How long "Tap again" waits: 5 seconds, or 30 with VoiceOver or Switch Control, which take
    /// longer to reach the button again.
    static func timeout(assistiveTech: Bool) -> TimeInterval {
        assistiveTech ? 30 : 5
    }

    /// `armedAt` is when "Tap again" appeared, or nil when it isn't showing.
    static func decide(armedAt: Date?, now: Date) -> ClockOutTap {
        guard let armedAt else { return .arm }
        return now.timeIntervalSince(armedAt) < settle ? .ignore : .confirm
    }
}
