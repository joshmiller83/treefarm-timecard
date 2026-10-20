import SwiftUI
import TreeFarmKit

/// The workout's line on the Today page (docs/watch.md 3.6): recording, waiting for the phone,
/// stopped from outside (with Record again), or why there's no workout.
struct WorkoutStatus: Equatable {
    enum Tone: Equatable { case fir, sap, rust, muted }

    var glyph: String
    var text: String
    var tone: Tone
    /// "Recording stopped": the line carries the Record again button.
    var offersRecordAgain = false

    init?(_ live: WorkoutLive) {
        switch live.recording {
        case .recording: (glyph, text, tone) = (WatchDisplay.Glyph.recording, WatchDisplay.recording, .fir)
        case .paused: (glyph, text, tone) = (WatchDisplay.Glyph.takeBreak, WorkoutWords.paused, .sap)
        case .waitingForClockOut: (glyph, text, tone) = (WatchDisplay.Glyph.phoneAway, WatchDisplay.clockOutWaiting, .sap)
        case .stoppedUnexpectedly:
            (glyph, text, tone) = (WatchDisplay.Glyph.recording, WatchDisplay.recordingStopped, .rust)
            offersRecordAgain = true
        case .notAuthorized: (glyph, text, tone) = (WatchDisplay.Glyph.heart, WatchDisplay.workoutsOff, .muted)
        case .off: (glyph, text, tone) = (WatchDisplay.Glyph.heart, WatchDisplay.actionButtonNeedsWorkouts, .muted)
        case .idle: return nil
        }
    }

    /// "104 bpm · 612 kcal", live from the workout; nil before the first reading.
    static func heartLine(_ live: WorkoutLive) -> String? {
        WatchDisplay.heartLine(bpm: live.heartRate, kcal: live.kcal)
    }

    /// "Heart rate 104, 612 calories": what VoiceOver says for the heart line.
    static func heartLineAccessibility(_ live: WorkoutLive) -> String? {
        WorkoutWords.heartLineAccessibility(bpm: live.heartRate, kcal: live.kcal)
    }

    var color: Color {
        switch tone {
        case .fir: WorkoutPalette.firText
        case .sap: WorkoutPalette.sapText
        case .rust: WorkoutPalette.rustText
        case .muted: .secondary
        }
    }
}

/// The Today page's workout row, with Record again under it when the recording stopped.
struct WorkoutStatusLine: View {
    let live: WorkoutLive
    var onRecordAgain: () -> Void = { ShiftWorkout.shared.recordAgain() }

    var body: some View {
        if let status = WorkoutStatus(live) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(status.text).foregroundStyle(status.tone == .muted ? .secondary : .primary)
                } icon: {
                    Image(systemName: status.glyph).foregroundStyle(status.color)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)

                if status.offersRecordAgain {
                    RecordAgainButton(action: onRecordAgain)
                }
            }
        }
    }
}

/// "♥ 104 bpm · 612 kcal" on the Today page (and the heart on the 49 mm Now page).
struct WorkoutHeartLine: View {
    let live: WorkoutLive
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        if let line = WorkoutStatus.heartLine(live) {
            Label {
                Text(line).monospacedDigit()
            } icon: {
                Image(systemName: WatchDisplay.Glyph.heart)
                    .foregroundStyle(dimmed ? WorkoutPalette.heart.opacity(0.6) : WorkoutPalette.heart)
            }
            .font(.footnote)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WorkoutStatus.heartLineAccessibility(live) ?? line)
        }
    }
}

/// The full-width gold banner while a watch clock-out waits for the phone (docs/watch.md 2.2):
/// the session stays stopped, flushing once a minute, for up to an hour.
struct ClockOutWaitingBanner: View {
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        Label {
            Text(WatchDisplay.clockOutWaiting)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: WatchDisplay.Glyph.phoneAway)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(dimmed ? WorkoutPalette.sapText : WorkoutPalette.sapInk)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dimmed ? Color.clear : WorkoutPalette.sap)
                .strokeBorder(WorkoutPalette.sap, lineWidth: dimmed ? 1.5 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workout.clockOutWaiting")
    }
}

/// "Recording stopped" with a full-width Record again (docs/watch.md 2.5). The shift stays on
/// the clock: the session ended from outside the app (another workout, an error, the system).
struct RecordingStoppedBanner: View {
    var onRecordAgain: () -> Void = { ShiftWorkout.shared.recordAgain() }

    var body: some View {
        VStack(spacing: 6) {
            Label(WatchDisplay.recordingStopped, systemImage: WatchDisplay.Glyph.recording)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WorkoutPalette.rustText)
                .frame(maxWidth: .infinity, alignment: .leading)
            RecordAgainButton(action: onRecordAgain)
        }
        .accessibilityIdentifier("workout.recordingStopped")
    }
}

/// Record again: 48, 52 or 54 pt tall, full width, fir green (it gets the workout going again;
/// the rust stays on "Recording stopped").
struct RecordAgainButton: View {
    let action: () -> Void

    @Environment(\.workoutSizeOverride) private var sizeOverride
    private var size: WorkoutSize { sizeOverride ?? .current }

    var body: some View {
        Button(action: action) {
            Label(WatchDisplay.recordAgain, systemImage: WatchDisplay.Glyph.recording)
        }
        .buttonStyle(GloveButtonStyle(fill: WorkoutPalette.fir, height: size.secondaryHeight))
        .accessibilityIdentifier("workout.recordAgain")
    }
}
