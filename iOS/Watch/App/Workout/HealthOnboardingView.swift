import SwiftUI
import TreeFarmKit

/// The first-launch card's two questions (docs/watch.md 2.4).
enum HealthOnboardingStep: Equatable, Sendable {
    /// "Record shifts as workouts", with Apple's wording for how Other counts calories.
    case health
    /// Shown while the system asks about notifications: "Remind me if a clock-out gets stuck."
    case reminder

    var title: String { WatchDisplay.healthTitle }
    var body: String { self == .health ? WatchDisplay.caloriesNote : WatchDisplay.notificationsAsk }
    var button: String { WatchDisplay.allowHealth }
    /// A heart for Health; for the reminder, the phone out of reach that leaves a clock-out stuck.
    var glyph: String { self == .health ? WatchDisplay.Glyph.heart : WatchDisplay.Glyph.phoneAway }
}

/// The full-screen card the watch shows on its first launch while recording is on and Health
/// was never asked (`ShiftWorkout.needsHealthOnboarding`).
struct HealthOnboardingView: View {
    var workout: ShiftWorkout = .shared

    var body: some View {
        HealthOnboardingCard(step: workout.onboardingStep ?? .health) {
            Task { await workout.allowHealth() }
        }
    }
}

/// The card itself: one glyph, the question, and Allow Health (Double Tap).
struct HealthOnboardingCard: View {
    let step: HealthOnboardingStep
    let onAllow: () -> Void

    @Environment(\.workoutSizeOverride) private var sizeOverride
    @Environment(\.dynamicTypeSize) private var typeSize
    private var size: WorkoutSize { sizeOverride ?? .current }

    /// How the calorie (or reminder) note is set.
    private enum Note { case full, shrinking, hidden }

    var body: some View {
        VStack(spacing: 8) {
            // Never a scroll view: it would take Double Tap from Allow Health. Last resort: at
            // the standard text sizes the note may shrink a little (the 40 mm watch); at the
            // accessibility sizes it never shrinks below what the person chose, it goes instead
            // (VoiceOver still reads it).
            ViewThatFits(in: .vertical) {
                message(showGlyph: true, note: .full)
                message(showGlyph: false, note: .full)
                message(showGlyph: false, note: typeSize.isAccessibilitySize ? .hidden : .shrinking)
            }
            .frame(maxHeight: .infinity)

            Button(action: onAllow) {
                Label(step.button, systemImage: WatchDisplay.Glyph.heart)
            }
            .buttonStyle(WorkoutButtonStyle(fill: WorkoutPalette.fir, height: size.primaryHeight))
            .handGestureShortcut(.primaryAction)
            .disabled(step == .reminder)
            .accessibilityIdentifier("onboarding.allowHealth")
        }
        .animation(.easeInOut(duration: 1), value: step)
    }

    private func message(showGlyph: Bool, note: Note) -> some View {
        VStack(spacing: 4) {
            if showGlyph {
                Image(systemName: step.glyph)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(step == .health ? WorkoutPalette.heart : WorkoutPalette.sapText)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.12)))
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
            }
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
            if note != .hidden {
                Text(step.body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(note == .shrinking ? 0.7 : 1)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: note == .full)
        .accessibilityElement(children: .combine)
        .accessibilityHint(note == .hidden ? step.body : "")
    }
}
